"""Orquestador de simulaciones para SimulateX: por cada build de referencia
(Tools/builds/_mapeo/<spec>.json) genera su RaidSimRequest, simula la build
base, y para cada objeto candidato (mismo slot, clase compatible) sustituye
la pieza y re-simula, guardando el delta de DPS/HPS en Data/sims/.

Resiliente por diseño: un fallo (ítem incompatible, base de datos incompleta,
timeout) descarta esa build/objeto concreto y sigue con el resto del lote,
nunca aborta el proceso completo. Cada invocación de wowsimcli/go test tiene
un timeout obligatorio: sustituir un ítem en un slot incompatible puede colgar
el motor de simulación indefinidamente en vez de fallar limpiamente (visto en
pruebas manuales con un anillo forzado al slot de arma a distancia).
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

GO_TEST_TIMEOUT_S = 30
WOWSIMCLI_TIMEOUT_S = 60

# Clase de wowsims (nombre de spec) -> nombre de clase tal como aparece en
# allowed_classes de items_procesados.json (ver procesar_objetos.py). Un
# objeto sin restricción de clase (allowed_classes vacía) es compatible con
# cualquiera.
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
    raid = sim_result.get("raidMetrics", {})
    return {
        "dps": raid.get("dps", {}).get("avg", 0.0),
        "hps": raid.get("hps", {}).get("avg", 0.0),
    }


def swap_item_in_gear(gear_path: pathlib.Path, item_slot: int, new_item_id: int, out_path: pathlib.Path):
    data = load_json(gear_path)
    items = data["raid"]["parties"][0]["players"][0]["equipment"]["items"]
    items[item_slot] = {"id": new_item_id}
    out_path.write_text(json.dumps(data), encoding="utf-8")


def load_candidate_items(spec: str, limit: int = None) -> list:
    items_path = DATA_DIR / "items_procesados.json"
    if not items_path.exists():
        return []
    items = load_json(items_path)
    game_class = SPEC_TO_GAME_CLASS[spec]
    candidates = []
    for item_id_str, item in items.items():
        allowed = item.get("allowed_classes") or []
        if allowed and game_class not in allowed:
            continue
        slot = resolve_item_slot(item["inventory_slot"], occupied_slots=set())
        if slot is None:
            continue
        candidates.append({**item, "id": int(item_id_str), "resolved_slot": slot})
    if limit:
        candidates = candidates[:limit]
    return candidates


def simulate_build(spec: str, build: dict, talents_string: str, work_dir: pathlib.Path, iterations: int) -> dict:
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

    candidates = load_candidate_items(spec, limit=build.get("_limit_items"))
    item_deltas = {}
    for item in candidates:
        swapped_input = work_dir / f"{build_id}_{item['id']}.json"
        swap_item_in_gear(base_input, item["resolved_slot"], item["id"], swapped_input)

        swapped_output = work_dir / f"{build_id}_{item['id']}_out.json"
        swapped_result = run_wowsimcli(swapped_input, swapped_output)

        swapped_input.unlink(missing_ok=True)
        swapped_output.unlink(missing_ok=True)

        if swapped_result is None:
            continue
        swapped_metrics = extract_metrics(swapped_result)
        item_deltas[item["id"]] = {
            "dps_delta": round(swapped_metrics["dps"] - base_metrics["dps"], 1),
            "hps_delta": round(swapped_metrics["hps"] - base_metrics["hps"], 1),
        }

    return {
        "build_id": build_id,
        "status": "ok",
        "base_dps": round(base_metrics["dps"], 1),
        "base_hps": round(base_metrics["hps"], 1),
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

                result = simulate_build(spec, build_with_apl, talents_string, work_dir, args.iterations)
                out_path = spec_out_dir / f"{result['build_id']}.json"
                out_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")

                status_marker = "OK" if result["status"] == "ok" else f"ERROR: {result.get('motivo')}"
                n_items = len(result.get("items", {}))
                print(f"[{spec}/{result['build_id']}] {status_marker} ({n_items} objetos)")


if __name__ == "__main__":
    main()
