"""Consolida los resultados de simulación (Data/sims/<spec>/*.json) en los
ficheros Lua finales que carga el addon (Addon/SimulateX/Data/*.lua), uno por
clase de WoW, agrupando todas sus specs.

No se ejecuta como parte del addon; es el último paso del pipeline offline.
"""

import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from simular_builds import SPEC_TO_GAME_CLASS

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
BUILDS_DIR = TOOLS_DIR / "builds"
SIMS_DIR = TOOLS_DIR.parent / "Data" / "sims"
OUT_DIR = TOOLS_DIR.parent / "Addon" / "SimulateX" / "Data"

# Rol de la spec: usado por el addon para saber si mostrar el delta como DPS,
# HPS o mitigación de tanque. Se infiere del nombre de spec (ver
# Tools/generar_builds.py, es la misma nomenclatura que usa wowsims en ui/).
SPEC_ROLE = {
    "balance_druid": "dps", "feral_druid": "dps", "restoration_druid": "heal", "feral_tank_druid": "tank",
    "holy_paladin": "heal", "protection_paladin": "tank", "retribution_paladin": "dps",
    "healing_priest": "heal", "shadow_priest": "dps", "smite_priest": "dps",
    "elemental_shaman": "dps", "enhancement_shaman": "dps", "restoration_shaman": "heal",
    "hunter": "dps", "mage": "dps", "rogue": "dps", "warlock": "dps",
    "warrior": "dps", "protection_warrior": "tank",
    "deathknight": "dps", "tank_deathknight": "tank",
}


def phase_number(gear_file: str) -> int:
    match = re.match(r"^(preraid|p(\d+))", gear_file)
    if not match:
        return -1
    return 0 if match.group(1) == "preraid" else int(match.group(2))


def dominant_talent_tree(talents_string: str):
    trees = talents_string.split("-")
    points = [sum(int(d) for d in tree) for tree in trees]
    if not points or max(points) == 0:
        return None
    return points.index(max(points))


def lua_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def format_lua_table(builds: dict) -> str:
    lines = ["local builds = {"]
    for build_id, build in builds.items():
        lines.append(f'  ["{lua_escape(build_id)}"] = {{')
        lines.append(f'    role = "{build["role"]}",')
        lines.append(f'    phase = {build["phase"]},')
        if build["talent_tree"] is not None:
            lines.append(f'    talentTree = {build["talent_tree"]},')
        lines.append(f'    baseDps = {build["base_dps"]},')
        lines.append(f'    baseHps = {build["base_hps"]},')
        lines.append('    items = {')
        for item_id, delta in build["items"].items():
            lines.append(f'      [{item_id}] = {{ dps = {delta["dps_delta"]}, hps = {delta["hps_delta"]} }},')
        lines.append('    },')
        lines.append('  },')
    lines.append("}")
    return "\n".join(lines)


def main() -> None:
    if not SIMS_DIR.exists():
        raise SystemExit(f"No existe {SIMS_DIR}; ejecuta primero Tools/simular_builds.py")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    builds_by_class = {}
    for spec_dir in sorted(SIMS_DIR.iterdir()):
        if not spec_dir.is_dir():
            continue
        spec = spec_dir.name
        game_class = SPEC_TO_GAME_CLASS.get(spec)
        role = SPEC_ROLE.get(spec)
        if not game_class or not role:
            print(f"[{spec}] AVISO: sin clase/rol conocido, se omite")
            continue

        spec_talents_path = BUILDS_DIR / f"{spec}.json"
        talent_sets = {}
        if spec_talents_path.exists():
            spec_data = json.loads(spec_talents_path.read_text(encoding="utf-8"))
            talent_sets = {t["const_name"]: t["talents_string"] for t in spec_data["talent_sets"]}

        mapeo_path = BUILDS_DIR / "_mapeo" / f"{spec}.json"
        talent_set_by_gear = {}
        if mapeo_path.exists():
            mapeo = json.loads(mapeo_path.read_text(encoding="utf-8"))
            for b in mapeo["builds"]:
                talent_set_by_gear[b["gear_file"]] = b.get("talent_set")

        for result_path in sorted(spec_dir.glob("*.json")):
            result = json.loads(result_path.read_text(encoding="utf-8"))
            if result["status"] != "ok":
                continue

            talent_name = talent_set_by_gear.get(result["build_id"])
            talents_string = talent_sets.get(talent_name, "")
            talent_tree = dominant_talent_tree(talents_string) if talents_string else None

            build_id = f"{spec}_{result['build_id']}"
            builds_by_class.setdefault(game_class, {})[build_id] = {
                "role": role,
                "talent_tree": talent_tree,
                "phase": phase_number(result["build_id"]),
                "base_dps": result["base_dps"],
                "base_hps": result["base_hps"],
                "items": result["items"],
            }

    for game_class, builds in builds_by_class.items():
        lua_var = f"SimulateX_Data_{game_class}"
        content = f"{format_lua_table(builds)}\n\n{lua_var} = {{ builds = builds }}\n"
        out_path = OUT_DIR / f"SimulateX_Data_{game_class}.lua"
        out_path.write_text(content, encoding="utf-8")
        n_items = sum(len(b["items"]) for b in builds.values())
        print(f"[{game_class}] {len(builds)} builds, {n_items} entradas de objeto -> {out_path}")


if __name__ == "__main__":
    main()
