"""Aproximación tipo GearScore para niveles 1-79, donde no existe ningún dato
de simulación real (wowsims solo cubre nivel 80, ver el plan de simulación).
No es una simulación de combate: es una puntuación ponderada por estadística,
igual que hacen addons de comparación de equipo (Pawn, GearScore) fuera de
contenido end-game.

Fuente de datos: Data/items_bajo_nivel.json (extraído de acore_world vía
Tools/extraer_objetos_bd.py), no scraping HTTP — la base de datos del
servidor ya tiene los stats estructurados en columnas.

Fórmula: score = nivel_objeto * peso_ilvl + Σ(valor_stat_i * peso_stat_i).
"""

import json
import pathlib

DATA_DIR = pathlib.Path(__file__).resolve().parent.parent / "Data"
ITEMS_BAJO_NIVEL_PATH = DATA_DIR / "items_bajo_nivel.json"

# IDs de estadística estándar de item_template/AoWoW (ITEM_MOD_* de la API).
STAT_ID_NAMES = {3: "agility", 4: "strength", 5: "intellect", 6: "spirit", 7: "stamina"}

ARMOR_SUBCLASS_TO_CLASSES = {
    1: ["Priest", "Mage", "Warlock"],
    2: ["Rogue", "Druid"],
    3: ["Hunter", "Shaman"],
    4: ["Warrior", "Paladin", "Deathknight"],
}

STAT_WEIGHTS_BY_SPEC = {
    "feral_druid": {
        "ilvl": 1.0,
        "strength": 1.0,
        "agility": 1.2,
        "stamina": 0.15,
    },
}

SPEC_TO_GAME_CLASS = {"feral_druid": "Druid"}


def is_compatible(item: dict, game_class: str) -> bool:
    if item["class"] == 4 and item["subclass"] in ARMOR_SUBCLASS_TO_CLASSES:
        return game_class in ARMOR_SUBCLASS_TO_CLASSES[item["subclass"]]
    return True  # sin restricción conocida (armas, joyas): se deja pasar, el juego decide


def compute_score(spec: str, item: dict) -> float:
    weights = STAT_WEIGHTS_BY_SPEC[spec]
    score = item["item_level"] * weights.get("ilvl", 1.0)
    for stat_id, value in item["stats"].items():
        stat_name = STAT_ID_NAMES.get(int(stat_id))
        if stat_name:
            score += value * weights.get(stat_name, 0.0)
    return round(score, 1)


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", required=True, choices=list(STAT_WEIGHTS_BY_SPEC.keys()))
    args = parser.parse_args()

    if not ITEMS_BAJO_NIVEL_PATH.exists():
        raise SystemExit(f"No existe {ITEMS_BAJO_NIVEL_PATH}; ejecuta primero extraer_objetos_bd.py")

    items = json.loads(ITEMS_BAJO_NIVEL_PATH.read_text(encoding="utf-8"))
    game_class = SPEC_TO_GAME_CLASS[args.spec]

    scores = {}
    for item_id, item in items.items():
        if not is_compatible(item, game_class):
            continue
        scores[item_id] = {
            "score": compute_score(args.spec, item),
            "required_level": item["required_level"],
            "inventory_type": item["inventory_type"],
        }

    out_path = DATA_DIR / f"scores_bajo_nivel_{args.spec}.json"
    out_path.write_text(json.dumps(scores, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"[{args.spec}] {len(scores)} objetos puntuados -> {out_path}")


if __name__ == "__main__":
    main()
