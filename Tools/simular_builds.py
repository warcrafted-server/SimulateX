"""Orquestador de simulaciones para SimulateX: por cada build de referencia
(Tools/builds/_mapeo/<spec>.json) genera su RaidSimRequest, simula la build
base, y para cada objeto candidato (mismo slot, clase compatible) sustituye
la pieza y re-simula, guardando el delta de dps/hps/tps/dtps en Data/sims/.

Resiliente por diseño: un fallo (ítem incompatible, base de datos incompleta,
timeout) descarta esa build/objeto concreto y sigue con el resto del lote,
nunca aborta el proceso completo. Cada invocación de wowsimcli/go test tiene
un timeout obligatorio: sustituir un ítem en un slot incompatible puede colgar
el motor de simulación indefinidamente en vez de fallar limpiamente (visto en
pruebas manuales con un anillo forzado al slot de arma a distancia).

Al sustituir un objeto se conserva el encantamiento del slot base y se rellenan
sus huecos de gema con las gemas del propio gearset base (meta si el candidato
tiene hueco meta, si no la gema no-meta más frecuente del gearset): sin esto,
el candidato pierde el valor del encantamiento/gemas del objeto que reemplaza y
el delta sale sesgado hacia negativo incluso comparado contra sí mismo (E1,
ver .agents/plans/auditoria-v0.3/auditoria-v0.3.REVIEW.md).
"""

import json
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from mapeo_slots import resolve_item_slot
from specs_metadata import SPEC_GO_PACKAGES, ui_relative_prefix

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
WOWSIMS_SRC = TOOLS_DIR / "wowsimcli-src"
WOWSIMCLI_BIN = TOOLS_DIR / "wowsimcli"
BUILDS_DIR = TOOLS_DIR / "builds"
DATA_DIR = TOOLS_DIR.parent / "Data"
SIMS_OUT_DIR = DATA_DIR / "sims"
ITEMS_BD_PATH = DATA_DIR / "items_bd.json"
WOWSIMS_DB_PATH = WOWSIMS_SRC / "assets" / "database" / "db.json"

GO_TEST_TIMEOUT_S = 30
WOWSIMCLI_TIMEOUT_S = 60

# Bits de AllowableClass (item_template), estándar del juego desde siempre.
CLASS_BIT = {
    "Warrior": 1, "Paladin": 2, "Hunter": 4, "Rogue": 8, "Priest": 16,
    "Deathknight": 32, "Shaman": 64, "Mage": 128, "Warlock": 256, "Druid": 1024,
}

# Clase de wowsims (nombre de spec) -> nombre de clase tal como aparece en
# CLASS_BIT. Usado para filtrar candidatos por AllowableClass.
SPEC_TO_GAME_CLASS = {
    "balance_druid": "Druid", "feral_druid": "Druid", "restoration_druid": "Druid",
    "feral_tank_druid": "Druid",
    "holy_paladin": "Paladin", "protection_paladin": "Paladin", "retribution_paladin": "Paladin",
    "healing_priest": "Priest", "shadow_priest": "Priest", "smite_priest": "Priest",
    "elemental_shaman": "Shaman", "enhancement_shaman": "Shaman", "restoration_shaman": "Shaman",
    "hunter": "Hunter", "mage": "Mage", "rogue": "Rogue", "warlock": "Warlock",
    "warrior": "Warrior", "protection_warrior": "Warrior",
    "deathknight": "Deathknight", "tank_deathknight": "Deathknight",
}

# Specs de doble empuñadura (plan, paso 1): si el gearset base lleva arma en
# mano izquierda, los candidatos de arma de una mano se simulan también ahí.
DUAL_WIELD_SPECS = {"rogue", "enhancement_shaman", "warrior", "tank_deathknight", "deathknight"}

ITEM_SLOT_OFF_HAND = 15
META_GEM_COLOR = 1

# item_template.class == 2 -> arma; subclass 13,15,16,18,19 son de una mano o
# a distancia, nunca van en ambas manos. Ver mapeo_slots.py para el resto.
WEAPON_ITEM_CLASS = 2


def load_json(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def build_env(spec: str, gear_file: str, apl_file: str, apl_subdir: str, talents_string: str,
              out_file: pathlib.Path, iterations: int = 300):
    prefix = ui_relative_prefix(spec)
    ui_spec_dir = f"{prefix}ui/{spec}"
    env = {
        "SIMX_GEAR_DIR": f"{ui_spec_dir}/gear_sets",
        "SIMX_GEAR_FILE": gear_file,
        "SIMX_TALENTS": talents_string,
        "SIMX_OUT_FILE": str(out_file),
        "SIMX_ITERATIONS": str(iterations),
    }
    if apl_file:
        env["SIMX_APL_DIR"] = f"{ui_spec_dir}/apls"
        env["SIMX_APL_FILE"] = apl_file
    else:
        # Sin APL real disponible: se reutiliza el propio gearset como
        # "rotación" es incorrecto, así que se deja vacío y el generador Go
        # usará la rotación simple por defecto (sin GetAplRotation).
        env["SIMX_APL_DIR"] = ""
        env["SIMX_APL_FILE"] = ""
    return env


def run_go_extractor(spec: str, env_overrides: dict) -> bool:
    import os
    package = SPEC_GO_PACKAGES[spec]
    env = {**os.environ, **env_overrides}
    try:
        result = subprocess.run(
            ["go", "test", "-tags", "with_db", "-run", "TestGenExtractor", f"./sim/{package}/..."],
            cwd=WOWSIMS_SRC, env=env, capture_output=True, text=True, timeout=GO_TEST_TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        return False
    return result.returncode == 0


def run_wowsimcli(input_path: pathlib.Path, output_path: pathlib.Path) -> dict | None:
    try:
        result = subprocess.run(
            [str(WOWSIMCLI_BIN), "sim", "--infile", str(input_path), "--outfile", str(output_path)],
            capture_output=True, text=True, timeout=WOWSIMCLI_TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        return None
    if result.returncode != 0 or not output_path.exists():
        return None
    return load_json(output_path)


def extract_metrics(sim_result: dict) -> dict:
    players = sim_result.get("raidMetrics", {}).get("parties", [{}])[0].get("players", [{}])
    player = players[0] if players else {}
    return {
        "dps": player.get("dps", {}).get("avg", 0.0),
        "hps": player.get("hps", {}).get("avg", 0.0),
        "tps": player.get("threat", {}).get("avg", 0.0),
        "dtps": player.get("dtps", {}).get("avg", 0.0),
    }


def load_gem_colors() -> dict:
    """color de cada gema (id de item de gema -> color), desde la BD de
    wowsims (assets/database/db.json). item_template.socketColor_* describe
    los HUECOS de una pieza de armadura, no sirve para saber el color de una
    gema en sí; ese dato solo está en la propia BD de gemas de wowsims
    (confirmado: id 41398 "Relentless Earthsiege Diamond" -> color 1 = meta)."""
    data = load_json(WOWSIMS_DB_PATH)
    return {g["id"]: g["color"] for g in data.get("gems", [])}


def base_gear_gem_pool(gear_items: list, gem_colors: dict) -> tuple:
    """Devuelve (meta_gem_id, main_gem_id): la gema meta (color 1) y la gema
    no-meta más frecuente entre todas las que lleva el gearset base. None si
    el gearset base no usa ese tipo de gema (ej. build sin meta socket)."""
    meta_gem = None
    main_gem_counts: dict[int, int] = {}
    for it in gear_items:
        for gem_id in it.get("gems", []):
            if not gem_id:
                continue
            color = gem_colors.get(gem_id)
            if color == META_GEM_COLOR:
                meta_gem = meta_gem or gem_id
            else:
                main_gem_counts[gem_id] = main_gem_counts.get(gem_id, 0) + 1
    main_gem = max(main_gem_counts, key=main_gem_counts.get) if main_gem_counts else None
    return meta_gem, main_gem


def gems_for_candidate(candidate_socket_colors: list, meta_gem: int | None, main_gem: int | None,
                        base_extra_gem_needed: bool) -> list:
    """Rellena cada hueco de socket del candidato: el primer hueco de color meta
    usa la gema meta del gearset base, el resto la gema principal. Si el
    candidato no declara huecos pero el slot base tenía más gemas que huecos
    (hebilla de cinturón), se añade igualmente una gema principal."""
    gems = []
    for color in candidate_socket_colors:
        if color == META_GEM_COLOR and meta_gem:
            gems.append(meta_gem)
        elif main_gem:
            gems.append(main_gem)
    if not candidate_socket_colors and base_extra_gem_needed and main_gem:
        gems.append(main_gem)
    return gems


def swap_item_in_gear(gear_path: pathlib.Path, item_slot: int, candidate: dict,
                       gem_colors: dict, out_path: pathlib.Path):
    data = load_json(gear_path)
    items = data["raid"]["parties"][0]["players"][0]["equipment"]["items"]
    base_slot_item = items[item_slot] if item_slot < len(items) else {}

    meta_gem, main_gem = base_gear_gem_pool(items, gem_colors)
    base_gem_count = len(base_slot_item.get("gems", []))
    candidate_sockets = candidate.get("socket_colors", [])
    extra_gem_needed = base_gem_count > len(candidate_sockets)

    new_item = {"id": candidate["id"]}
    if "enchant" in base_slot_item:
        new_item["enchant"] = base_slot_item["enchant"]
    gems = gems_for_candidate(candidate_sockets, meta_gem, main_gem, extra_gem_needed)
    if gems:
        new_item["gems"] = gems

    items[item_slot] = new_item
    out_path.write_text(json.dumps(data), encoding="utf-8")


ITEM_LEVEL_MARGIN = 20  # objetos fuera de este margen respecto al gearset base no son una comparación realista


def gear_item_level_range(base_input_path: pathlib.Path, items_by_id: dict) -> tuple:
    data = load_json(base_input_path)
    equipped_ids = [it.get("id") for it in data["raid"]["parties"][0]["players"][0]["equipment"]["items"] if it.get("id")]
    levels = [items_by_id[str(i)]["item_level"] for i in equipped_ids
              if str(i) in items_by_id and items_by_id[str(i)]["item_level"]]
    if not levels:
        return (0, 999)
    return (min(levels) - ITEM_LEVEL_MARGIN, max(levels) + ITEM_LEVEL_MARGIN)


def is_one_handed_weapon(item: dict) -> bool:
    return item.get("class") == WEAPON_ITEM_CLASS and item.get("inventory_type") == 13


def load_candidate_items(spec: str, items_by_id: dict, limit: int = None, item_level_range: tuple = None) -> list:
    game_class = SPEC_TO_GAME_CLASS[spec]
    class_bit = CLASS_BIT[game_class]
    candidates = []
    for item_id_str, item in items_by_id.items():
        mask = item.get("allowable_class_mask", -1)
        if mask != -1 and not (mask & class_bit):
            continue
        slot = resolve_item_slot(item["inventory_type"], occupied_slots=set())
        if slot is None:
            continue
        if item_level_range and not (item_level_range[0] <= item["item_level"] <= item_level_range[1]):
            continue
        candidates.append({**item, "id": int(item_id_str), "resolved_slot": slot})
    if limit:
        candidates = candidates[:limit]
    return candidates


def base_gear_items(base_input_path: pathlib.Path) -> list:
    data = load_json(base_input_path)
    return data["raid"]["parties"][0]["players"][0]["equipment"]["items"]


def simulate_one_swap(base_input: pathlib.Path, item_slot: int, candidate: dict, gem_colors: dict,
                       work_dir: pathlib.Path, tag: str) -> dict | None:
    swapped_input = work_dir / f"{tag}.json"
    swap_item_in_gear(base_input, item_slot, candidate, gem_colors, swapped_input)

    swapped_output = work_dir / f"{tag}_out.json"
    result = run_wowsimcli(swapped_input, swapped_output)

    swapped_input.unlink(missing_ok=True)
    swapped_output.unlink(missing_ok=True)

    return extract_metrics(result) if result is not None else None


def simulate_build(spec: str, build: dict, talents_string: str, work_dir: pathlib.Path,
                    items_by_id: dict, gem_colors: dict, iterations: int) -> dict:
    build_id = f"{build['gear_file']}"
    base_input = work_dir / f"{build_id}_base.json"

    env = build_env(spec, build["gear_file"], build.get("apl_file"), None, talents_string, base_input, iterations)
    if not run_go_extractor(spec, env):
        return {"build_id": build_id, "status": "error", "motivo": "fallo generando RaidSimRequest base"}

    base_output = work_dir / f"{build_id}_base_out.json"
    base_result = run_wowsimcli(base_input, base_output)
    if base_result is None:
        return {"build_id": build_id, "status": "error", "motivo": "wowsimcli falló o excedió el timeout en la build base"}

    base_metrics = extract_metrics(base_result)

    ilvl_range = gear_item_level_range(base_input, items_by_id)
    candidates = load_candidate_items(spec, items_by_id, limit=build.get("_limit_items"), item_level_range=ilvl_range)

    gear_items = base_gear_items(base_input)
    offhand_is_one_handed = spec in DUAL_WIELD_SPECS and is_one_handed_weapon(
        items_by_id.get(str(gear_items[ITEM_SLOT_OFF_HAND].get("id")), {})
        if ITEM_SLOT_OFF_HAND < len(gear_items) and gear_items[ITEM_SLOT_OFF_HAND].get("id") else {}
    )

    item_deltas = {}
    for item in candidates:
        # También se simula cada objeto ya equipado en el gearset base con esta
        # misma regla de gemas/encantamiento: sirve de referencia "equipado" en
        # el addon y de validación (delta contra sí mismo ≈ 0).
        metrics = simulate_one_swap(base_input, item["resolved_slot"], item, gem_colors, work_dir, f"{build_id}_{item['id']}")
        if metrics is None:
            continue
        entry = {
            "dps": round(metrics["dps"] - base_metrics["dps"], 1),
            "hps": round(metrics["hps"] - base_metrics["hps"], 1),
            "tps": round(metrics["tps"] - base_metrics["tps"], 1),
            "dtps": round(metrics["dtps"] - base_metrics["dtps"], 1),
        }

        if is_one_handed_weapon(item) and offhand_is_one_handed:
            oh_metrics = simulate_one_swap(base_input, ITEM_SLOT_OFF_HAND, item, gem_colors, work_dir, f"{build_id}_{item['id']}_oh")
            if oh_metrics is not None:
                entry["dpsOH"] = round(oh_metrics["dps"] - base_metrics["dps"], 1)

        item_deltas[item["id"]] = entry

    return {
        "build_id": build_id,
        "status": "ok",
        "base_dps": round(base_metrics["dps"], 1),
        "base_hps": round(base_metrics["hps"], 1),
        "base_tps": round(base_metrics["tps"], 1),
        "base_dtps": round(base_metrics["dtps"], 1),
        "items": item_deltas,
    }


def main() -> None:
    import argparse
    import tempfile

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", help="Solo simular esta spec (por defecto, todas)")
    parser.add_argument("--limit-builds", type=int, help="Límite de builds a procesar por spec (para pruebas)")
    parser.add_argument("--limit-items", type=int, help="Límite de objetos candidatos por build (para pruebas)")
    parser.add_argument("--iterations", type=int, default=300,
                         help="Iteraciones de Monte Carlo por simulación (por defecto 300; wowsims usa 2000 para su propio 'Average')")
    args = parser.parse_args()

    if not ITEMS_BD_PATH.exists():
        raise SystemExit(f"Falta {ITEMS_BD_PATH}. Ejecuta extraer_objetos_bd.py primero.")
    items_by_id = load_json(ITEMS_BD_PATH)
    gem_colors = load_gem_colors()

    talent_sets_by_spec = {}
    apl_files_by_spec = {}
    for spec_file in BUILDS_DIR.glob("*.json"):
        if spec_file.parent.name == "_mapeo":
            continue
        data = load_json(spec_file)
        talent_sets_by_spec[data["spec"]] = {t["const_name"]: t["talents_string"] for t in data["talent_sets"]}
        apl_files_by_spec[data["spec"]] = {a["const_name"]: a["apl_file"] for a in data["apl_presets"]}

    SIMS_OUT_DIR.mkdir(exist_ok=True)

    specs = [args.spec] if args.spec else list(SPEC_GO_PACKAGES.keys())
    for spec in specs:
        mapeo_path = BUILDS_DIR / "_mapeo" / f"{spec}.json"
        if not mapeo_path.exists():
            print(f"[{spec}] sin fichero de mapeo, se omite")
            continue

        mapeo = load_json(mapeo_path)
        builds = [b for b in mapeo["builds"] if b["status"] == "ok"]
        if args.limit_builds:
            builds = builds[:args.limit_builds]

        spec_out_dir = SIMS_OUT_DIR / spec
        spec_out_dir.mkdir(exist_ok=True)

        with tempfile.TemporaryDirectory(dir=WOWSIMS_SRC / "sim" / SPEC_GO_PACKAGES[spec]) as tmp:
            work_dir = pathlib.Path(tmp)
            for build in builds:
                talents_string = talent_sets_by_spec.get(spec, {}).get(build["talent_set"], "")
                apl_file = apl_files_by_spec.get(spec, {}).get(build["apl"]) if build.get("apl") else None
                build_with_apl = {**build, "apl_file": apl_file, "_limit_items": args.limit_items}

                result = simulate_build(spec, build_with_apl, talents_string, work_dir, items_by_id, gem_colors, args.iterations)
                out_path = spec_out_dir / f"{result['build_id']}.json"
                out_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")

                status_marker = "OK" if result["status"] == "ok" else f"ERROR: {result.get('motivo')}"
                n_items = len(result.get("items", {}))

                validation_note = ""
                if result["status"] == "ok":
                    base_ids = {it.get("id") for it in base_gear_items(work_dir / f"{build['gear_file']}_base.json") if it.get("id")}
                    base_metric_name = "dps" if result["base_dps"] else "hps"
                    base_metric_value = result["base_dps"] or result["base_hps"]
                    if base_metric_value:
                        threshold = abs(base_metric_value) * 0.005
                        base_deltas = [result["items"][i][base_metric_name] for i in base_ids if i in result["items"]]
                        within = [d for d in base_deltas if abs(d) < threshold]
                        if base_deltas:
                            ratio = len(within) / len(base_deltas)
                            validation_note = f", validación objetos base: {ratio:.0%}"
                            if ratio < 0.9:
                                print(f"[{spec}/{result['build_id']}] AVISO: solo {ratio:.0%} de objetos base dentro de "
                                      f"±0.5% ({len(within)}/{len(base_deltas)}) — revisar antes de seguir")

                print(f"[{spec}/{result['build_id']}] {status_marker} ({n_items} objetos){validation_note}")


if __name__ == "__main__":
    main()
