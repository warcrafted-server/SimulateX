"""Vuelca la estructura completa de los árboles de talentos (fila, columna,
máximo de rango, prerrequisito, spellId por rango) a
Addon/SimulateX_<Clase>/Data/SimulateX_ArbolTalentos_<Clase>.lua, para que la
pestaña Talentos dibuje el árbol real en vez de una tabla de comparación.

Fuente: Tools/talentos_referencia/talents_wotlk_335_esES.json (Talent.dbc/
TalentTab.dbc reales del servidor). El icono de cada talento lo saca el
addon en el cliente con GetSpellInfo(spellId), no hace falta guardarlo aquí.
"""

import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from generar_db_addon import SPEC_INFO, lua_value
from validar_talentos import REFERENCE_PATH, CLASS_ID_TO_GAME_CLASS
from rutas_addon import class_data_dir, ensure_class_addon_toc

TOOLS_DIR = pathlib.Path(__file__).resolve().parent

# game_class de wowsims (SPEC_INFO) -> class_id de Talent.dbc
GAME_CLASS_TO_CLASS_ID = {v: k for k, v in CLASS_ID_TO_GAME_CLASS.items()}


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


def tree_names_for_class(reference: list, class_id: int) -> list:
    """Nombres de los 3 árboles en orden de tree_index."""
    names = {}
    for t in reference:
        if t["class_id"] == class_id:
            names[t["tree_index"]] = t["tree"]
    return [names.get(i, "") for i in range(3)]


def build_class_tree(reference: list, class_id: int) -> dict:
    trees = []
    for tree_index in range(3):
        talents = [t for t in reference if t["class_id"] == class_id and t["tree_index"] == tree_index]
        talents.sort(key=lambda t: (t["row"], t["column"]))
        tree_name = talents[0]["tree"] if talents else ""
        entries = []
        for t in talents:
            entries.append({
                "id": t["talent_id"],
                "name": t["name"],
                "row": t["row"],
                "col": t["column"],
                "maxRank": t["max_rank"],
                "reqPoints": t["required_points"],
                "reqTalent": t["required_talent"],
                "reqRank": t["required_talent_rank"],
                # spellId por rango, para GetSpellInfo() en el cliente
                "ranks": [r["spell_id"] for r in t["ranks"]],
            })
        trees.append({"name": tree_name, "talents": entries})
    return {"trees": trees}


def render_class_lua(class_name: str, tree: dict) -> str:
    return f"SimulateX_ArbolTalentos_{class_name} = {lua_table(tree, 0)}\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--clase", help="Solo esta clase de wowsims (Druid, Paladin...). Por defecto todas.")
    args = parser.parse_args()

    reference = json.loads(REFERENCE_PATH.read_text(encoding="utf-8"))

    game_classes = {game_class for game_class, _, _ in SPEC_INFO.values()}
    if args.clase:
        game_classes = {args.clase} if args.clase in game_classes else set()

    for game_class in sorted(game_classes):
        class_id = GAME_CLASS_TO_CLASS_ID.get(game_class)
        if class_id is None:
            print(f"{game_class}: sin class_id de Talent.dbc, se omite")
            continue
        tree = build_class_tree(reference, class_id)
        talent_count = sum(len(t["talents"]) for t in tree["trees"])
        out_dir = class_data_dir(game_class)
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / f"SimulateX_ArbolTalentos_{game_class}.lua"
        out_path.write_text(render_class_lua(game_class, tree), encoding="utf-8")
        ensure_class_addon_toc(game_class)
        print(f"{game_class}: {talent_count} talentos -> {out_path}")


if __name__ == "__main__":
    main()
