"""Consolida los datos de cada spec en Addon/SimulateX/Data/SimulateX_Data_<Clase>.lua
(paso 5 del plan datos-completos-v0.4): por cada build (spec + fase) con datos
en Data/sims/<spec>/<build>.json, calcula sus pesos (TestGenStatWeights o
epWeights preset, según la decisión 3), el nivel de objeto medio del gearset,
el valor de hueco (gema meta/principal) y el componente de crítico agi/int, y
vuelca todo en el formato de datos por build definido en el plan.

No junta specs sin datos reales de simulación: una build sin
Data/sims/<spec>/<build>.json se omite (aparecerá tras el paso 7).
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from extraer_ep_stats import extract_ep_config
from mapeo_stats import STAT_TO_ITEM_MOD, RATING_TO_STATS, combine_rating_weight, gem_ep_value
from simular_builds import (
    build_env, run_go_extractor, run_go_stat_weights, load_json, ITEMS_BD_PATH, WOWSIMS_DB_PATH,
    base_gear_gem_pool, base_gear_items, load_gem_colors, WOWSIMS_SRC,
)
from specs_metadata import SPEC_GO_PACKAGES

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
DATA_DIR = TOOLS_DIR.parent / "Data"
SIMS_DIR = DATA_DIR / "sims"
BUILDS_DIR = TOOLS_DIR / "builds"
ADDON_DATA_DIR = TOOLS_DIR.parent / "Addon" / "SimulateX" / "Data"

ITEM_SLOT_MAIN_HAND = 14
INVTYPE_2HWEAPON = 17

# Spec de wowsims -> (nombre de clase en el addon, rol). El rol solo distingue
# "healer" (métrica principal = hps) del resto (dps); tanque también usa dps
# como base pero su "Amenaza"/"Supervivencia" se calculan en el addon (paso 6)
# a partir de tps/dtps, no aquí.
SPEC_INFO = {
    "balance_druid": ("Druid", "dps"), "feral_druid": ("Druid", "dps"),
    "restoration_druid": ("Druid", "healer"), "feral_tank_druid": ("Druid", "tank"),
    "holy_paladin": ("Paladin", "healer"), "protection_paladin": ("Paladin", "tank"),
    "retribution_paladin": ("Paladin", "dps"),
    "healing_priest": ("Priest", "healer"), "shadow_priest": ("Priest", "dps"),
    "smite_priest": ("Priest", "dps"),
    "elemental_shaman": ("Shaman", "dps"), "enhancement_shaman": ("Shaman", "dps"),
    "restoration_shaman": ("Shaman", "healer"),
    "hunter": ("Hunter", "dps"), "mage": ("Mage", "dps"), "rogue": ("Rogue", "dps"),
    "warlock": ("Warlock", "dps"), "warrior": ("Warrior", "dps"),
    "protection_warrior": ("Warrior", "tank"),
    "deathknight": ("Deathknight", "dps"), "tank_deathknight": ("Deathknight", "tank"),
}

STAT_NAME_TO_INDEX = {
    "StatStrength": 0, "StatAgility": 1, "StatStamina": 2, "StatIntellect": 3, "StatSpirit": 4,
    "StatSpellPower": 5, "StatMP5": 6, "StatSpellHit": 7, "StatSpellCrit": 8, "StatSpellHaste": 9,
    "StatSpellPenetration": 10, "StatAttackPower": 11, "StatMeleeHit": 12, "StatMeleeCrit": 13,
    "StatMeleeHaste": 14, "StatArmorPenetration": 15, "StatExpertise": 16,
}

# Stat de crítico melee/hechizo (índice del enum), para critComponent.
MELEE_CRIT_INDEX = 13
SPELL_CRIT_INDEX = 8


def compute_stat_weights(spec: str, build: dict, talents_string: str, work_dir: pathlib.Path) -> dict | None:
    """Ejecuta TestGenStatWeights (paso 3) para esta build y devuelve
    dps.weights.stats/pseudoStats (pesos brutos), o None si falla."""
    out_file = work_dir / f"{build['gear_file']}_sw.json"
    env = build_env(spec, build["gear_file"], build.get("apl_file"), None, talents_string, out_file)
    env["SIMX_SW_OUT_FILE"] = str(out_file)
    env["SIMX_SW_ITERATIONS"] = "5000"
    if not run_go_stat_weights(spec, env):
        return None
    if not out_file.exists():
        return None
    result = load_json(out_file)
    out_file.unlink(missing_ok=True)
    return result.get("dps", {}).get("weights", {})


def weights_by_stat_index(raw_weights: dict) -> dict:
    stats = raw_weights.get("stats", [])
    return {i: v for i, v in enumerate(stats) if v}


def build_item_mod_weights(weights_index: dict) -> dict:
    """Convierte los pesos por índice Stat a claves ITEM_MOD_* del addon
    (mapeo_stats.py): primarias 1:1, crítico/golpe/celeridad combinados."""
    item_mod_weights = {}
    for stat_idx, item_mod_key in STAT_TO_ITEM_MOD.items():
        weight = weights_index.get(stat_idx, 0.0)
        if weight:
            item_mod_weights[item_mod_key] = round(weight, 4)
    for item_mod_key in RATING_TO_STATS:
        combined = combine_rating_weight(weights_index, item_mod_key)
        if combined:
            item_mod_weights[item_mod_key] = round(combined, 4)
    return item_mod_weights


def compute_avg_item_level(gear_items: list, items_by_id: dict) -> float:
    levels = []
    for slot, it in enumerate(gear_items):
        item_id = it.get("id")
        if not item_id:
            continue
        item = items_by_id.get(str(item_id))
        if not item or not item["item_level"]:
            continue
        levels.append(item["item_level"])
        if slot == ITEM_SLOT_MAIN_HAND and item["inventory_type"] == INVTYPE_2HWEAPON:
            levels.append(item["item_level"])  # 2M cuenta doble
    return round(sum(levels) / len(levels), 1) if levels else 0.0


def compute_socket_values(gear_items: list, items_by_id: dict, gem_colors: dict, weights_index: dict) -> tuple:
    meta_gem, main_gem = base_gear_gem_pool(gear_items, gem_colors)
    gems_by_id = {g["id"]: g for g in load_json(WOWSIMS_DB_PATH).get("gems", [])}
    socket_value = gem_ep_value(gems_by_id[main_gem]["stats"], weights_index) if main_gem in gems_by_id else 0.0
    meta_socket_value = gem_ep_value(gems_by_id[meta_gem]["stats"], weights_index) if meta_gem in gems_by_id else 0.0
    return round(socket_value, 2), round(meta_socket_value, 2)


def build_entry(spec: str, build_id: str, sim_result: dict, weights_index: dict, weights_kind: str,
                 gear_items: list, items_by_id: dict, gem_colors: dict) -> dict:
    game_class, role = SPEC_INFO[spec]
    avg_item_level = compute_avg_item_level(gear_items, items_by_id)
    socket_value, meta_socket_value = compute_socket_values(gear_items, items_by_id, gem_colors, weights_index)

    # critComponent: cuánto vale 1% de crítico melee/hechizo en la métrica de
    # la build, para que el addon reescale agilidad/intelecto con
    # SimulateX_Levels.lua (paso 4) a niveles distintos de 80.
    crit_component = {
        "melee": round(weights_index.get(MELEE_CRIT_INDEX, 0.0), 4),
        "spell": round(weights_index.get(SPELL_CRIT_INDEX, 0.0), 4),
    }

    items = {}
    for item_id, deltas in sim_result.get("items", {}).items():
        entry = {"dps": deltas.get("dps", 0.0), "hps": deltas.get("hps", 0.0),
                 "tps": deltas.get("tps", 0.0), "dtps": deltas.get("dtps", 0.0)}
        if "dpsOH" in deltas:
            entry["dpsOH"] = deltas["dpsOH"]
        items[int(item_id)] = entry

    return {
        "spec": spec,
        "role": role,
        "phase": build_id,
        "avgItemLevel": avg_item_level,
        "base": {
            "dps": sim_result.get("base_dps", 0.0),
            "hps": sim_result.get("base_hps", 0.0),
            "tps": sim_result.get("base_tps", 0.0),
            "dtps": sim_result.get("base_dtps", 0.0),
        },
        "weights": build_item_mod_weights(weights_index),
        "weightsKind": weights_kind,
        "critComponent": crit_component,
        "socketValue": socket_value,
        "metaSocketValue": meta_socket_value,
        "items": items,
    }


def lua_value(v) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return str(v)


def lua_table(d: dict, indent: int) -> str:
    pad = "  " * indent
    lines = ["{"]
    for k, v in d.items():
        key = f'["{k}"]' if isinstance(k, str) and not k.isidentifier() else (k if isinstance(k, str) else f"[{k}]")
        if isinstance(v, dict):
            lines.append(f"{pad}  {key} = {lua_table(v, indent + 1)},")
        else:
            lines.append(f"{pad}  {key} = {lua_value(v)},")
    lines.append(pad + "}")
    return "\n".join(lines)


def render_class_lua(class_name: str, entries: dict) -> str:
    lines = [f"SimulateX_Data_{class_name} = {{"]
    for build_key, entry in entries.items():
        lines.append(f'  ["{build_key}"] = {lua_table(entry, 1)},')
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> None:
    import argparse
    import tempfile

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", help="Solo consolidar esta spec (por defecto, todas las que tengan datos en Data/sims/)")
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

    specs = [args.spec] if args.spec else [s for s in SPEC_INFO if (SIMS_DIR / s).exists()]

    entries_by_class: dict[str, dict] = {}
    for spec in specs:
        if spec not in SPEC_INFO:
            print(f"[{spec}] spec desconocida, se omite")
            continue
        game_class, _role = SPEC_INFO[spec]
        spec_sims_dir = SIMS_DIR / spec
        if not spec_sims_dir.exists():
            print(f"[{spec}] sin Data/sims/{spec}/, se omite (pendiente del paso 7)")
            continue

        mapeo_path = BUILDS_DIR / "_mapeo" / f"{spec}.json"
        mapeo = load_json(mapeo_path) if mapeo_path.exists() else {"builds": []}
        builds_by_gear_file = {b["gear_file"]: b for b in mapeo["builds"] if b["status"] == "ok"}

        try:
            ep_config = extract_ep_config(spec)
        except (FileNotFoundError, ValueError) as exc:
            print(f"[{spec}] ERROR leyendo epStats/epWeights: {exc}, se omite")
            continue

        with tempfile.TemporaryDirectory(dir=WOWSIMS_SRC / "sim" / SPEC_GO_PACKAGES[spec]) as tmp:
            work_dir = pathlib.Path(tmp)
            for sim_file in sorted(spec_sims_dir.glob("*.json")):
                sim_result = load_json(sim_file)
                if sim_result.get("status") != "ok":
                    print(f"[{spec}/{sim_file.stem}] sin status ok, se omite")
                    continue

                build = builds_by_gear_file.get(sim_result["build_id"])
                if build is None:
                    print(f"[{spec}/{sim_file.stem}] sin build de referencia en el mapeo, se omite")
                    continue

                talents_string = talent_sets_by_spec.get(spec, {}).get(build["talent_set"], "")
                apl_file = apl_files_by_spec.get(spec, {}).get(build["apl"]) if build.get("apl") else None
                build_with_apl = {**build, "apl_file": apl_file}

                base_input = work_dir / f"{sim_result['build_id']}_base.json"
                env = build_env(spec, build["gear_file"], apl_file, None, talents_string, base_input)
                if not run_go_extractor(spec, env):
                    print(f"[{spec}/{sim_file.stem}] fallo reconstruyendo el gearset base, se omite")
                    continue
                gear_items = base_gear_items(base_input)

                if ep_config["kind"] == "preset":
                    weights_index = {STAT_NAME_TO_INDEX[name]: value for name, value in ep_config["ep_weights"].items()
                                      if name in STAT_NAME_TO_INDEX}
                    weights_kind = "preset"
                else:
                    raw_weights = compute_stat_weights(spec, build_with_apl, talents_string, work_dir)
                    if raw_weights is None:
                        print(f"[{spec}/{sim_file.stem}] fallo generando pesos (TestGenStatWeights), se omite")
                        continue
                    weights_index = weights_by_stat_index(raw_weights)
                    weights_kind = "sim"

                entry = build_entry(spec, sim_result["build_id"], sim_result, weights_index, weights_kind,
                                     gear_items, items_by_id, gem_colors)
                build_key = f"{spec}_{sim_result['build_id']}"
                entries_by_class.setdefault(game_class, {})[build_key] = entry
                print(f"[{spec}/{sim_result['build_id']}] consolidado ({len(entry['items'])} objetos, "
                      f"pesos={weights_kind}, avgItemLevel={entry['avgItemLevel']})")

    ADDON_DATA_DIR.mkdir(parents=True, exist_ok=True)
    for class_name, entries in entries_by_class.items():
        out_path = ADDON_DATA_DIR / f"SimulateX_Data_{class_name}.lua"
        out_path.write_text(render_class_lua(class_name, entries), encoding="utf-8")
        print(f"-> {out_path} ({len(entries)} builds)")


if __name__ == "__main__":
    main()
