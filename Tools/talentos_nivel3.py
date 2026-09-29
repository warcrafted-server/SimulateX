"""v0.7 Nivel 3: busca la mejor distribución de talentos de una spec DPS con
el mismo equipo/APL de su build de referencia. Diseño y hechos verificados:
.agents/plans/mejoras-v0.8/talentos-nivel3.DISEÑO.md.

Solo se mueven puntos entre talentos "vivos" (su campo Talents.X aparece en
el código Go de la clase); los demás son relleno para la regla de 5 puntos
por fila, y el relleno prefiere los talentos que ya tenía la build de
partida (conservan su utilidad aunque no den DPS simulado). Toda cadena
pasa validar_talentos.validate_build contra las DBC reales.

Reanudable: Data/talentos_n3/<spec>.json se guarda tras cada simulación.
Uso: nice -n 19 python3 talentos_nivel3.py --spec feral_druid
"""

import argparse
import copy
import json
import pathlib
import random
import re
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from simular_builds import (
    build_env, run_go_extractor, run_wowsimcli, extract_metrics, load_json, WOWSIMS_SRC, TOOLS_DIR,
)
from simular_talentos import pick_reference_build, load_apl_file, GAME_CLASS_TO_CLASS_ID
from validar_talentos import load_reference, tree_talents, validate_build, KNOWN_BROKEN_PREREQUISITES
from generar_db_addon import SPEC_INFO
from specs_metadata import SPEC_GO_PACKAGES

TOTAL_POINTS = 71
SCREEN_ITERATIONS = 1000
CONFIRM_ITERATIONS = 5000
SCREEN_MARGIN = 0.001    # > 0,1 % a 1000 it. para pasar a confirmar
CONFIRM_MARGIN = 0.0005  # > 0,05 % a 5000 it., misma semilla, para aceptar
ROLE_METRIC = {"dps": "dps", "healer": "hps", "tank": "tps"}

DATA_DIR = TOOLS_DIR.parent / "Data"
STATE_DIR = DATA_DIR / "talentos_n3"
TALENTOS_DIR = DATA_DIR / "talentos"


def class_go_dir(game_class: str) -> pathlib.Path:
    return WOWSIMS_SRC / "sim" / game_class.lower()


def proto_talent_fields(game_class: str) -> list:
    """Campos de <Clase>Talents en orden de número (= orden de la cadena)."""
    text = (WOWSIMS_SRC / "proto" / f"{game_class.lower()}.proto").read_text(encoding="utf-8")
    body = re.search(rf"message {game_class}Talents \{{(.*?)\n\}}", text, re.S).group(1)
    fields = re.findall(r"(?:int32|bool) (\w+) = (\d+);", body)
    return [name for name, _ in sorted(fields, key=lambda f: int(f[1]))]


def live_go_fields(game_class: str) -> set:
    used = set()
    for path in class_go_dir(game_class).rglob("*.go"):
        if path.name.endswith("_test.go") or path.name.startswith("zzz_"):
            continue
        used.update(re.findall(r"\.Talents\.(\w+)", path.read_text(encoding="utf-8")))
    return used


class TalentModel:
    """Árboles de la clase (DBC) con qué talentos afectan a la simulación."""

    def __init__(self, game_class: str, class_id: int):
        reference = load_reference()
        self.trees = [tree_talents(reference, class_id, t) for t in range(3)]
        fields = proto_talent_fields(game_class)
        flat = [talent for tree in self.trees for talent in tree]
        if len(fields) != len(flat):
            raise SystemExit(f"{game_class}: {len(fields)} campos proto y {len(flat)} talentos DBC, no cuadran")
        used = live_go_fields(game_class)
        go_name = lambda f: "".join(part.capitalize() for part in f.split("_"))
        self.slots = []  # (árbol, posición) en orden de cadena
        self.live = set()
        for tree_index, tree in enumerate(self.trees):
            for pos, talent in enumerate(tree):
                slot = (tree_index, pos)
                self.slots.append(slot)
                if go_name(fields[len(self.slots) - 1]) in used:
                    self.live.add(slot)
        self.by_id = {talent["talent_id"]: (t, p) for t, tree in enumerate(self.trees) for p, talent in enumerate(tree)}

    def talent(self, slot):
        return self.trees[slot[0]][slot[1]]

    def parse(self, talents_string: str) -> dict:
        blocks = (talents_string.split("-") + ["", "", ""])[:3]
        ranks = {}
        for tree_index, digits in enumerate(blocks):
            for pos, digit in enumerate(digits):
                if digit != "0":
                    ranks[(tree_index, pos)] = int(digit)
        return ranks

    def render(self, ranks: dict) -> str:
        blocks = []
        for tree_index, tree in enumerate(self.trees):
            digits = "".join(str(ranks.get((tree_index, pos), 0)) for pos in range(len(tree)))
            blocks.append(digits.rstrip("0"))
        return "-".join(blocks)

    def _prereq_ok(self, ranks: dict, slot) -> bool:
        talent = self.talent(slot)
        need = talent["required_talent"]
        if not need or talent["talent_id"] in KNOWN_BROKEN_PREREQUISITES:
            return True
        return ranks.get(self.by_id[need], 0) >= talent["required_talent_rank"]

    def _points_above(self, ranks: dict, tree_index: int, row: int) -> int:
        return sum(n for (t, p), n in ranks.items() if t == tree_index and self.trees[t][p]["row"] < row)

    def realize(self, live_ranks: dict, keep: dict):
        """Cadena completa con relleno muerto, o None si no cabe. keep: build
        de partida, cuyos talentos muertos se prefieren como relleno."""
        ranks = {slot: n for slot, n in live_ranks.items() if n > 0}
        for slot, n in ranks.items():
            if n > self.talent(slot)["max_rank"]:
                return None

        # prerrequisitos: los muertos se ponen, los vivos tienen que cumplirse ya
        changed = True
        while changed:
            changed = False
            for slot in list(ranks):
                talent = self.talent(slot)
                need = talent["required_talent"]
                if not need or talent["talent_id"] in KNOWN_BROKEN_PREREQUISITES:
                    continue
                need_slot = self.by_id[need]
                if ranks.get(need_slot, 0) < talent["required_talent_rank"]:
                    if need_slot in self.live:
                        return None
                    ranks[need_slot] = talent["required_talent_rank"]
                    changed = True

        def filler_order(tree_index, max_row):
            candidates = [(tree_index, p) for p, t in enumerate(self.trees[tree_index])
                          if (tree_index, p) not in self.live and t["row"] < max_row]
            return sorted(candidates, key=lambda s: (s not in keep, self.talent(s)["row"], s[1]))

        # 5 puntos por fila: se rellena desde arriba con talentos muertos
        for tree_index, tree in enumerate(self.trees):
            deepest = max((tree[p]["row"] for (t, p) in ranks if t == tree_index), default=0)
            for row in range(1, deepest + 1):
                deficit = 5 * row - self._points_above(ranks, tree_index, row)
                for slot in filler_order(tree_index, row):
                    if deficit <= 0:
                        break
                    if not self._prereq_ok(ranks, slot):
                        continue
                    room = self.talent(slot)["max_rank"] - ranks.get(slot, 0)
                    add = min(room, deficit)
                    if add > 0:
                        ranks[slot] = ranks.get(slot, 0) + add
                        deficit -= add
                if deficit > 0:
                    return None

        # sobrante hasta 71: relleno muerto donde la fila ya esté permitida
        remaining = TOTAL_POINTS - sum(ranks.values())
        if remaining < 0:
            return None
        points_by_tree = lambda t: sum(n for (tt, _), n in ranks.items() if tt == t)
        while remaining > 0:
            placed = False
            for tree_index in sorted(range(3), key=points_by_tree, reverse=True):
                for slot in filler_order(tree_index, 99):
                    talent = self.talent(slot)
                    if (ranks.get(slot, 0) < talent["max_rank"] and self._prereq_ok(ranks, slot)
                            and self._points_above(ranks, tree_index, talent["row"]) >= 5 * talent["row"]):
                        ranks[slot] = ranks.get(slot, 0) + 1
                        remaining -= 1
                        placed = True
                        break
                if placed:
                    break
            if not placed:
                return None

        talents_string = self.render(ranks)
        return talents_string

    def neighbors(self, current: dict) -> list:
        live = sorted(self.live)
        rank = lambda s: current.get(s, 0)
        moves = []
        for a in live:
            if rank(a) == 0:
                continue
            for b in live:
                room = self.talent(b)["max_rank"] - rank(b)
                if a == b or room == 0:
                    continue
                for amount in sorted({1, min(rank(a), room)}):
                    moved = dict(current)
                    moved[a] = rank(a) - amount
                    moved[b] = rank(b) + amount
                    moves.append(moved)
        for s in live:
            if rank(s) < self.talent(s)["max_rank"]:
                moves.append({**current, s: rank(s) + 1})
            if rank(s) > 0:
                moves.append({**current, s: rank(s) - 1})
        return moves


class Simulator:
    def __init__(self, spec: str, request: dict, metric: str):
        self.spec, self.request, self.metric = spec, request, metric
        self.work_dir = pathlib.Path(tempfile.mkdtemp(dir=WOWSIMS_SRC / "sim" / SPEC_GO_PACKAGES[spec]))

    def run(self, talents_string: str, iterations: int):
        request = copy.deepcopy(self.request)
        request["raid"]["parties"][0]["players"][0]["talentsString"] = talents_string
        request["simOptions"]["iterations"] = iterations
        in_path = self.work_dir / "n3_in.json"
        in_path.write_text(json.dumps(request), encoding="utf-8")
        result = run_wowsimcli(in_path, self.work_dir / "n3_out.json")
        return None if result is None else extract_metrics(result)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--max-sims", type=int, default=6000)
    args = parser.parse_args()

    game_class, role, _ = SPEC_INFO[args.spec]
    if role != "dps":
        raise SystemExit(f"{args.spec}: Nivel 3 solo para specs DPS (ver diseño)")
    metric = ROLE_METRIC[role]
    model = TalentModel(game_class, GAME_CLASS_TO_CLASS_ID[game_class])
    print(f"{args.spec}: {len(model.live)} talentos vivos de {len(model.slots)}")

    build = pick_reference_build(args.spec)
    builds_data = load_json(TOOLS_DIR / "builds" / f"{args.spec}.json")
    preset_talents = {t["const_name"]: t["talents_string"] for t in builds_data["talent_sets"]}[build["talent_set"]]
    with tempfile.TemporaryDirectory(dir=WOWSIMS_SRC / "sim" / SPEC_GO_PACKAGES[args.spec]) as tmp:
        request_path = pathlib.Path(tmp) / "base.json"
        env = build_env(args.spec, build["gear_file"], load_apl_file(args.spec, build.get("apl")), None,
                        preset_talents, request_path, SCREEN_ITERATIONS)
        if not run_go_extractor(args.spec, env):
            raise SystemExit("no se pudo generar la petición base")
        request = load_json(request_path)
    sim = Simulator(args.spec, request, metric)

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state_path = STATE_DIR / f"{args.spec}.json"
    state = load_json(state_path) if state_path.exists() else {
        "spec": args.spec, "reference_build": build["_build_id"], "cache": {}, "history": []}
    if state.get("reference_build") != build["_build_id"]:
        state = {"spec": args.spec, "reference_build": build["_build_id"], "cache": {}, "history": []}

    def save():
        state_path.write_text(json.dumps(state, indent=1, ensure_ascii=False), encoding="utf-8")

    def value(talents_string: str, iterations: int = SCREEN_ITERATIONS):
        key = f"{talents_string}@{iterations}"
        if key not in state["cache"]:
            metrics = sim.run(talents_string, iterations)
            state["cache"][key] = metrics[metric] if metrics else None
            save()
        return state["cache"][key]

    # partida: la mejor entre el preset y las variantes ya simuladas (Nivel 1/2)
    seeds = [preset_talents]
    prior = TALENTOS_DIR / f"{args.spec}.json"
    if prior.exists():
        seeds += [v["talents"] for v in load_json(prior)["variants"]
                  if v.get("status") == "ok" and v.get("label") != "nivel3"]
    class_id = GAME_CLASS_TO_CLASS_ID[game_class]
    seeds = [s for s in dict.fromkeys(seeds) if validate_build(class_id, s)[0]]
    if "current" not in state:
        state["start"] = max(seeds, key=lambda s: value(s) or 0)
        state["current"] = state["start"]
    keep = model.parse(state["start"])
    print(f"partida {state['start']}: {value(state['start']):.1f} {metric}")

    while True:
        current = state["current"]
        current_value = value(current)
        current_live = {s: n for s, n in model.parse(current).items() if s in model.live}
        candidates = []
        for moved in model.neighbors(current_live):
            talents_string = model.realize(moved, keep)
            if talents_string and talents_string != current and validate_build(class_id, talents_string)[0]:
                candidates.append(talents_string)
        candidates = list(dict.fromkeys(candidates))
        random.Random(len(state["history"])).shuffle(candidates)
        print(f"ronda {len(state['history']) + 1}: {len(candidates)} vecinos válidos, actual {current_value:.1f}")

        accepted = None
        for talents_string in candidates:
            if sum(1 for v in state["cache"].values() if v is not None) >= args.max_sims:
                print("límite de simulaciones alcanzado")
                break
            candidate_value = value(talents_string)
            if candidate_value and candidate_value > current_value * (1 + SCREEN_MARGIN):
                base_confirm = value(current, CONFIRM_ITERATIONS)
                candidate_confirm = value(talents_string, CONFIRM_ITERATIONS)
                print(f"  candidato {talents_string}: {candidate_value:.1f} "
                      f"(a {CONFIRM_ITERATIONS}: {candidate_confirm:.1f} frente a {base_confirm:.1f})")
                if candidate_confirm > base_confirm * (1 + CONFIRM_MARGIN):
                    accepted = talents_string
                    break
        if not accepted:
            break
        state["history"].append({"from": current, "to": accepted})
        state["current"] = accepted
        save()

    start_value, best_value = value(state["start"]), value(state["current"])
    gain = (best_value / start_value - 1) * 100
    print(f"fin: {state['current']} {best_value:.1f} ({gain:+.2f} % sobre la partida)")
    state["finished"] = True
    save()

    if state["current"] != state["start"]:
        data = load_json(prior) if prior.exists() else {"spec": args.spec, "reference_build": build["_build_id"],
                                                         "iterations": SCREEN_ITERATIONS, "variants": []}
        metrics = sim.run(state["current"], SCREEN_ITERATIONS)
        data["variants"] = [v for v in data["variants"] if v.get("label") != "nivel3"] + [{
            "label": "nivel3", "status": "ok", "talents": state["current"],
            "dps": round(metrics["dps"], 1), "hps": round(metrics["hps"], 1),
            "tps": round(metrics["tps"], 1), "dtps": round(metrics["dtps"], 1),
            "_iterations": SCREEN_ITERATIONS,
        }]
        prior.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"variante nivel3 guardada en {prior}")


if __name__ == "__main__":
    main()
