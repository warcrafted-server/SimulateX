"""Valida una cadena de talentos (formato wowhead: dígitos por árbol
separados por '-') contra Tools/talentos_referencia/talents_wotlk_335_esES.json,
extraído de las DBC reales del servidor (Talent.dbc/TalentTab.dbc).

Única fuente de verdad para máximos de rango, orden fila/columna y
prerrequisitos: ninguna variante de talentos se construye sin pasar por aquí.
"""

import json
import pathlib

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
REFERENCE_PATH = TOOLS_DIR / "talentos_referencia" / "talents_wotlk_335_esES.json"

# id de clase (Talent.dbc/ChrClasses.dbc) -> nombre de clase de wowsims
CLASS_ID_TO_GAME_CLASS = {
    1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest",
    6: "Deathknight", 7: "Shaman", 8: "Mage", 9: "Warlock", 11: "Druid",
}

# Prerrequisitos rotos conocidos en Tools/talentos_referencia/ (huérfanos:
# el talento requerido no existe en Talent.dbc, ver su fichero de validación
# "_validation.txt", sección "Failures"). Se ignoran en vez de bloquear el
# árbol entero; no se adivina cuál era el id correcto.
KNOWN_BROKEN_PREREQUISITES = {1756, 1993}


def load_reference() -> list:
    return json.loads(REFERENCE_PATH.read_text(encoding="utf-8"))


def tree_talents(reference: list, class_id: int, tree_index: int) -> list:
    """Talentos de un árbol, en el mismo orden fila/columna que usa el juego
    para asignar un dígito de la cadena a cada talento."""
    talents = [t for t in reference if t["class_id"] == class_id and t["tree_index"] == tree_index]
    talents.sort(key=lambda t: (t["row"], t["column"]))
    return talents


def validate_tree(talents: list, digits: str) -> tuple[bool, str, int]:
    """Valida un bloque de dígitos (un árbol) contra su lista de talentos. El
    formato wowhead trunca ceros finales (el último talento del árbol casi
    nunca lleva puntos), así que una cadena más corta que el árbol es válida:
    los talentos que faltan al final cuentan como 0. Devuelve (válido,
    motivo_si_no, puntos_gastados).

    Dos pasadas: la fila/columna del juego no siempre coincide con el orden
    de dependencia entre talentos de la MISMA fila (ej. Chamán Mejora fila 6:
    "Especialización en doble empuñadura" va en la columna 0 pero depende de
    "Doble empuñadura", columna 1) — comprobar prerrequisitos incrementalmente
    en orden columna daría un falso negativo. Se registran todos los rangos
    primero y se valida contra el estado final del árbol."""
    if len(digits) > len(talents):
        return False, f"longitud {len(digits)} > {len(talents)} talentos del árbol", 0

    ranks_by_id = {}
    for talent, digit in zip(talents, digits):
        ranks_by_id[talent["talent_id"]] = int(digit)

    spent = 0
    for talent, digit in zip(talents, digits):
        n = int(digit)
        if n > talent["max_rank"]:
            return False, f"{talent['name']} (id {talent['talent_id']}): {n} > máximo {talent['max_rank']}", spent
        if talent["required_points"] > spent and n > 0:
            return False, (f"{talent['name']}: su fila pide {talent['required_points']} puntos "
                            f"gastados en el árbol antes, hay {spent}"), spent
        if talent["required_talent"] and n > 0 and talent["talent_id"] not in KNOWN_BROKEN_PREREQUISITES:
            need_id, need_rank = talent["required_talent"], talent["required_talent_rank"]
            if ranks_by_id.get(need_id, 0) < need_rank:
                return False, f"{talent['name']}: requiere el talento {need_id} a rango {need_rank}", spent
        spent += n
    return True, "", spent


def validate_build(class_id: int, talents_string: str) -> tuple[bool, str]:
    """Valida una cadena completa de wowhead (3 bloques separados por '-')
    para una clase. No compara el total de puntos entre dos builds: eso
    depende del nivel del personaje simulado, ajeno a este fichero."""
    reference = load_reference()
    blocks = talents_string.split("-")
    # wowsims trunca también un tercer bloque vacío entero (no solo sus ceros
    # finales): "50...-50..." sin el "-" final es tan válido como "50...-50...-"
    while len(blocks) < 3:
        blocks.append("")
    if len(blocks) != 3:
        return False, f"se esperaban como máximo 3 bloques separados por '-', hay {len(blocks)}"

    total = 0
    for tree_index, digits in enumerate(blocks):
        talents = tree_talents(reference, class_id, tree_index)
        if not talents and digits:
            return False, f"árbol {tree_index} no tiene talentos pero la cadena trae dígitos"
        ok, motivo, spent = validate_tree(talents, digits)
        if not ok:
            return False, f"árbol {tree_index}: {motivo}"
        total += spent
    return True, f"{total} puntos gastados en total"


def describe_build(class_id: int, talents_string: str) -> str:
    """Lista legible de qué talentos tiene puestos una cadena, para revisión
    humana antes de simularla."""
    reference = load_reference()
    blocks = talents_string.split("-")
    lines = []
    for tree_index, digits in enumerate(blocks):
        talents = tree_talents(reference, class_id, tree_index)
        for talent, digit in zip(talents, digits):
            n = int(digit)
            if n > 0:
                lines.append(f"  árbol {tree_index}, fila {talent['row']}: {talent['name']} {n}/{talent['max_rank']}")
    return "\n".join(lines)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--class-id", type=int, required=True)
    parser.add_argument("--talents", required=True)
    args = parser.parse_args()

    ok, info = validate_build(args.class_id, args.talents)
    print("VÁLIDA" if ok else "INVÁLIDA", "-", info)
    if ok:
        print(describe_build(args.class_id, args.talents))
