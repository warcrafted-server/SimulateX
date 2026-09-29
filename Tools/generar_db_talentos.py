"""Consolida Data/talentos/<spec>.json en
Addon/SimulateX_<Clase>/Data/SimulateX_Talentos_<Clase>.lua (v0.7, Nivel
1/2): una tabla por clase, indexada por spec, con las variantes de talentos
ya simuladas (UI/Talentos.lua las lee vía SimulateX_TalentDataVars).

No junta specs sin datos: una spec sin Data/talentos/<spec>.json se omite.
"""

import argparse
import json
import pathlib
import sys

import collections

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from generar_db_addon import SPEC_INFO, lua_value
from rutas_addon import class_data_dir, ensure_class_addon_toc
from simular_builds import apl_suffix

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
DATA_DIR = TOOLS_DIR.parent / "Data"
TALENTOS_DIR = DATA_DIR / "talentos"
BUILDS_DIR = TOOLS_DIR / "builds"

# metric por rol, igual que ROLE_METRIC del addon (SimulateX.lua): una sola
# cifra para comparar variantes, la misma que ya usa el tooltip/comparador.
ROLE_METRIC = {"dps": "dps", "healer": "hps", "tank": "tps"}


def find_reference_glyphs(spec: str, reference_build: str | None) -> dict:
    """Glifos de la variante "estandar" (StandardTalents de wowsims, la
    misma con la que se simuló el gear de referencia): se busca en
    _mapeo/<spec>.json la build cuyo build_id_for coincide con
    reference_build, y desde su talent_set se leen los glifos ya
    extraídos por generar_builds.py en builds/<spec>.json. No se aplica a
    "mas_potp" ni otras variantes con talentos movidos a mano: sus glifos
    no están garantizados iguales a los de StandardTalents.
    """
    if not reference_build:
        return {}
    mapeo_path = BUILDS_DIR / "_mapeo" / f"{spec}.json"
    builds_path = BUILDS_DIR / f"{spec}.json"
    if not mapeo_path.exists() or not builds_path.exists():
        return {}
    mapeo = json.loads(mapeo_path.read_text(encoding="utf-8"))
    ok_builds = [b for b in mapeo["builds"] if b.get("status") == "ok"]
    # mismo build_id que generar_db_addon.py/simular_builds.py: gear_file
    # solo, o + sufijo de APL cuando el gear_file se repite (variantes de
    # rotación reales, ver emparejar_builds.py::pick_candidates).
    gear_file_counts = collections.Counter(b["gear_file"] for b in ok_builds)
    talent_set_name = None
    for build in ok_builds:
        build_id = build["gear_file"]
        if gear_file_counts[build_id] > 1 and build.get("apl"):
            build_id = f"{build_id}_{apl_suffix(build['apl'])}"
        if build_id == reference_build:
            talent_set_name = build["talent_set"]
            break
    if not talent_set_name:
        return {}
    builds_data = json.loads(builds_path.read_text(encoding="utf-8"))
    for talent_set in builds_data["talent_sets"]:
        if talent_set["const_name"] == talent_set_name:
            return talent_set.get("glyphs") or {}
    return {}


def load_spec_talents(spec: str) -> dict | None:
    path = TALENTOS_DIR / f"{spec}.json"
    if not path.exists():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    role = SPEC_INFO[spec][1]
    metric = ROLE_METRIC[role]
    reference_build = data.get("reference_build")
    reference_glyphs = find_reference_glyphs(spec, reference_build)

    variants = []
    for variant in data["variants"]:
        if variant.get("status") != "ok":
            continue
        entry = {
            "label": variant["label"],
            "talents": variant["talents"],
            "dps": variant.get("dps", 0.0),
            "hps": variant.get("hps", 0.0),
            "tps": variant.get("tps", 0.0),
            "dtps": variant.get("dtps", 0.0),
        }
        if variant["label"] == "estandar" and reference_glyphs:
            entry["glyphs"] = reference_glyphs
        variants.append(entry)
    if not variants:
        return None
    return {
        "specLabel": SPEC_INFO[spec][2],
        "metric": metric,
        "referenceBuild": reference_build,
        "variants": variants,
    }


# generar_db_addon.py::lua_table no soporta listas (las builds de gear no las
# necesitan); esta versión sí, para variants.
def lua_table(value, indent: int) -> str:
    pad = "  " * indent
    if isinstance(value, list):
        lines = ["{"]
        for item in value:
            lines.append(f"{pad}  {lua_table(item, indent + 1)},")
        lines.append(pad + "}")
        return "\n".join(lines)
    if isinstance(value, dict):
        lines = ["{"]
        for k, v in value.items():
            key = f'["{k}"]' if not k.isidentifier() else k
            if isinstance(v, (dict, list)):
                lines.append(f"{pad}  {key} = {lua_table(v, indent + 1)},")
            else:
                lines.append(f"{pad}  {key} = {lua_value(v)},")
        lines.append(pad + "}")
        return "\n".join(lines)
    return lua_value(value)


def render_class_lua(class_name: str, specs: dict) -> str:
    lines = [f"SimulateX_Talentos_{class_name} = {{"]
    for spec, entry in specs.items():
        lines.append(f'  ["{spec}"] = {lua_table(entry, 1)},')
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--clase", help="Solo esta clase de wowsims (Druid, Paladin...). Por defecto todas.")
    args = parser.parse_args()

    by_class = {}
    for spec, (game_class, _, _) in SPEC_INFO.items():
        if args.clase and game_class != args.clase:
            continue
        entry = load_spec_talents(spec)
        if entry:
            by_class.setdefault(game_class, {})[spec] = entry

    if not by_class:
        print("sin datos de talentos consolidados para ninguna clase pedida")
        return

    for game_class, specs in by_class.items():
        out_dir = class_data_dir(game_class)
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / f"SimulateX_Talentos_{game_class}.lua"
        out_path.write_text(render_class_lua(game_class, specs), encoding="utf-8")
        ensure_class_addon_toc(game_class)
        variant_count = sum(len(e["variants"]) for e in specs.values())
        print(f"{game_class}: {len(specs)} spec(s), {variant_count} variante(s) -> {out_path}")


if __name__ == "__main__":
    main()
