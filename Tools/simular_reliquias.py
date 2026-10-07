"""Compara el DPS de reliquias con el hueco a distancia vacío."""

import argparse
import copy
import json
import pathlib
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from simular_builds import build_env, extract_metrics, load_json, run_go_extractor, run_wowsimcli, TOOLS_DIR
from simular_talentos import load_apl_file, pick_reference_build


DATA_DIR = TOOLS_DIR.parent / "Data"
OUT_DIR = DATA_DIR / "reliquias"
ITEMS_BD_PATH = DATA_DIR / "items_bd.json"
RANGED_SLOT_INDEX = 16
RANDOM_SEED = 101

SPEC_TO_CLASS_DIR = {
    "balance_druid": "druid",
    "feral_druid": "druid",
    "elemental_shaman": "shaman",
    "enhancement_shaman": "shaman",
    "retribution_paladin": "paladin",
    "deathknight": "deathknight",
}

# Los ayudantes de registro también reciben IDs que terminan en NewItemEffect.
ITEM_ID_PATTERNS = (
    re.compile(r"\bcore\.NewItemEffect\(\s*(\d+)\b"),
    re.compile(r"\baddItemEffect\(\s*(\d+)\b"),
    re.compile(r"\bmakeGladiatorIdolEffect\(\s*(\d+)\b"),
    re.compile(r"\bCreateGladiatorsSigil\(\s*(\d+)\b"),
    re.compile(r'\bregisterSpellPVPTotem\(\s*"[^"]*"\s*,\s*(\d+)\b'),
)


def effect_item_ids(class_dir: str) -> set[int]:
    class_path = TOOLS_DIR / "wowsimcli-src" / "sim" / class_dir
    items_files = sorted(path for path in class_path.glob("*.go") if not path.name.endswith("_test.go"))
    if not items_files:
        raise SystemExit(f"no se encontraron archivos Go de efectos de objetos: {class_path}")

    ids = set()
    for items_file in items_files:
        source = items_file.read_text(encoding="utf-8")
        for pattern in ITEM_ID_PATTERNS:
            ids.update(int(value) for value in pattern.findall(source))
    return ids


def reference_talents(spec: str, build: dict) -> str:
    """Usa el punto de partida de Nivel 3 o el talent_set de la build elegida."""
    talents_path = DATA_DIR / "talentos_n3" / f"{spec}.json"
    if talents_path.is_file():
        talent_state = load_json(talents_path)
        talents = talent_state.get("start")
        if talent_state.get("reference_build") == build["_build_id"] and isinstance(talents, str) and talents:
            return talents

    builds_data = load_json(TOOLS_DIR / "builds" / f"{spec}.json")
    talent_sets = {item["const_name"]: item["talents_string"] for item in builds_data["talent_sets"]}
    talents = talent_sets.get(build.get("talent_set"))
    if not talents:
        raise SystemExit(f"no se encontró la cadena de talentos de la build de referencia para {spec}")
    return talents


def cached_relics(item_ids: set[int]) -> dict[str, dict]:
    if not ITEMS_BD_PATH.is_file():
        return {}
    items = load_json(ITEMS_BD_PATH)
    return {
        str(item_id): {"nombre": item.get("name", str(item_id))}
        for item_id in item_ids
        if (item := items.get(str(item_id), {})).get("inventory_type") == 28
    }


def discover_relics(class_dir: str) -> dict[str, dict]:
    item_ids = effect_item_ids(class_dir)
    if not item_ids:
        raise SystemExit(f"no se encontraron efectos de reliquia para {class_dir}")

    try:
        from extraer_objetos_bd import run_query

        ids_csv = ",".join(str(item_id) for item_id in sorted(item_ids))
        rows = run_query(
            "SELECT entry, name, InventoryType FROM item_template "
            f"WHERE InventoryType = 28 AND entry IN ({ids_csv}) ORDER BY entry"
        )
    except (KeyError, OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
        reliquias = cached_relics(item_ids)
        if not reliquias:
            raise SystemExit(
                f"no se pudo consultar item_template ni hay catálogo local de reliquias: {type(exc).__name__}"
            ) from exc
        print("aviso: no se pudo consultar la BD; se usa Data/items_bd.json como respaldo")
        return reliquias

    return {
        str(row["entry"]): {"nombre": row["name"]}
        for row in rows
        if int(row["InventoryType"]) == 28
    }


def set_ranged_item(request: dict, item_id: int | None) -> dict:
    updated = copy.deepcopy(request)
    items = updated["raid"]["parties"][0]["players"][0]["equipment"]["items"]
    if len(items) <= RANGED_SLOT_INDEX:
        raise SystemExit(
            f"RaidSimRequest solo contiene {len(items)} huecos de equipo; no aparece ItemSlotRanged"
        )

    # ItemSlotRanged vale 16 en proto; en la lista de 17 elementos ocupa el último.
    items[RANGED_SLOT_INDEX] = {"id": item_id} if item_id is not None else {}
    updated.setdefault("simOptions", {})["randomSeed"] = RANDOM_SEED
    return updated


def write_request(path: pathlib.Path, request: dict) -> None:
    path.write_text(json.dumps(request), encoding="utf-8")


def save_results(path: pathlib.Path, data: dict) -> None:
    temp_path = path.with_suffix(".json.tmp")
    temp_path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    temp_path.replace(path)


def simulate_dps(request: dict, item_id: int | None, label: str,
                 work_dir: pathlib.Path) -> float:
    input_path = work_dir / f"{label}.json"
    output_path = work_dir / f"{label}_out.json"
    write_request(input_path, set_ranged_item(request, item_id))
    result = run_wowsimcli(input_path, output_path)
    if result is None:
        raise SystemExit(f"wowsimcli falló o excedió el tiempo al simular {label}")
    dps = float(extract_metrics(result)["dps"])
    if dps <= 0:
        raise SystemExit(f"wowsimcli devolvió DPS no válido para {label}: {dps}")
    return dps


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", required=True, help="spec DPS que se va a simular")
    parser.add_argument("--iterations", type=int, default=5000)
    parser.add_argument("--force", action="store_true", help="repite la línea base y las reliquias seleccionadas")
    parser.add_argument("--solo-id", type=int, help="simula solo este ID de reliquia (más la línea base)")
    args = parser.parse_args()

    class_dir = SPEC_TO_CLASS_DIR.get(args.spec)
    if class_dir is None:
        allowed = ", ".join(SPEC_TO_CLASS_DIR)
        raise SystemExit(f"spec no admitida: {args.spec}; solo se admiten specs DPS: {allowed}")
    if args.iterations <= 0:
        raise SystemExit("--iterations debe ser mayor que cero")

    build = pick_reference_build(args.spec)
    talents = reference_talents(args.spec, build)
    reliquias = discover_relics(class_dir)
    if not reliquias:
        raise SystemExit(f"no hay reliquias con efecto en wowsims y InventoryType=28 para {args.spec}")
    if args.solo_id is not None and str(args.solo_id) not in reliquias:
        raise SystemExit(f"el ID {args.solo_id} no es una reliquia válida con efecto simulado para {args.spec}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / f"{args.spec}.json"
    previous = load_json(out_path) if out_path.exists() else {}
    same_run = (
        previous.get("spec") == args.spec
        and previous.get("reference_build") == build["_build_id"]
        and previous.get("iterations") == args.iterations
        and previous.get("talents") == talents
    )
    if same_run:
        results = {
            item_id: result
            for item_id, result in previous.get("reliquias", {}).items()
            if item_id in reliquias
        }
        baseline = previous.get("baseline")
        if not isinstance(baseline, dict) or float(baseline.get("dps", 0)) <= 0:
            baseline = None
    else:
        if previous:
            print("los resultados existentes usan otra build, talentos o iteraciones; se recalcularán")
        results = {}
        baseline = None

    selected_ids = [str(args.solo_id)] if args.solo_id is not None else sorted(reliquias, key=int)
    need_baseline = baseline is None or args.force
    data = {
        "spec": args.spec,
        "reference_build": build["_build_id"],
        "iterations": args.iterations,
        "talents": talents,
        "baseline": baseline,
        "reliquias": results,
    }
    pending_ids = [item_id for item_id in selected_ids if item_id not in results or args.force]
    if not need_baseline:
        print(f"línea base: ya simulada con {args.iterations} iteraciones, se reutiliza")
    if not need_baseline and not pending_ids:
        for item_id in selected_ids:
            print(f"{item_id} {reliquias[item_id]['nombre']}: ya simulada, se salta")
        print(f"resultados ya guardados en {out_path}")
        return

    apl_file = load_apl_file(args.spec, build.get("apl"))
    with tempfile.TemporaryDirectory(prefix="simular_reliquias_") as temp_dir:
        work_dir = pathlib.Path(temp_dir)
        request_path = work_dir / "request.json"
        env = build_env(args.spec, build["gear_file"], apl_file, None, talents, request_path, args.iterations)
        if not run_go_extractor(args.spec, env):
            raise SystemExit("falló la generación de RaidSimRequest")
        request = load_json(request_path)

        if need_baseline:
            print("simulando línea base sin reliquia...", end=" ", flush=True)
            baseline_dps = simulate_dps(request, None, "baseline", work_dir)
            data["baseline"] = {"dps": round(baseline_dps, 1)}
            save_results(out_path, data)
            print(f"{data['baseline']['dps']} DPS")
        baseline_dps = float(data["baseline"]["dps"])

        for item_id in selected_ids:
            if item_id in results and not args.force:
                print(f"{item_id} {reliquias[item_id]['nombre']}: ya simulada, se salta")
                continue
            print(f"simulando {item_id} {reliquias[item_id]['nombre']}...", end=" ", flush=True)
            relic_dps = simulate_dps(request, int(item_id), f"reliquia_{item_id}", work_dir)
            shown_dps = round(relic_dps, 1)
            delta_pct = (shown_dps / baseline_dps - 1) * 100
            results[item_id] = {
                "nombre": reliquias[item_id]["nombre"],
                "dps": shown_dps,
                "delta_pct": round(delta_pct, 2),
            }
            data["reliquias"] = dict(sorted(results.items(), key=lambda pair: int(pair[0])))
            save_results(out_path, data)
            print(f"{results[item_id]['dps']} DPS ({results[item_id]['delta_pct']:+.2f}%)")
    print(f"guardado en {out_path}")


if __name__ == "__main__":
    main()
