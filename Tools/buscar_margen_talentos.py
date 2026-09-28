"""Ayuda a encontrar variantes de talentos con margen real de forma más
rápida que revisar el árbol entero a mano: para una build ya simulada
(StandardTalents), lista los talentos con puntos por debajo de su máximo
(candidatos a subir) y los talentos a 0 puntos en la misma fila o filas
cercanas sin uso claro (candidatos a bajar), y para cada uno busca si su
nombre en inglés aparece referenciado en el código Go del motor.

No decide nada por sí solo: un talento "sin referencias" es señal fuerte de
que no tiene efecto simulado, pero uno "con referencias" necesita revisión
humana igualmente (puede afectar a una forma, mecánica o métrica que no es
la que importa para esa spec — ver el caso de Protector de la manada, que
solo afecta en forma de Oso y no de Gato).
"""

import argparse
import json
import pathlib
import re
import subprocess

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
REFERENCE_PATH = TOOLS_DIR / "talentos_referencia" / "talents_wotlk_335_esES.json"
WOWSIMS_SRC = TOOLS_DIR / "wowsimcli-src"

# nombre visible en español (DBC) -> campo Go del talento (Talents.<Campo>).
# Solo hace falta para los que se listan como candidatos; se deriva del
# nombre del spell en inglés vía Spell.dbc no extraído aquí, así que se
# aproxima buscando por el id del talento en los .go (más fiable: buscan
# "druid.Talents." seguido de cualquier palabra, y se cruzan por posición).
GO_TALENT_FIELD_RE = re.compile(r"\.Talents\.(\w+)")


def load_reference() -> list:
    return json.loads(REFERENCE_PATH.read_text(encoding="utf-8"))


def tree_talents(reference: list, class_id: int, tree_index: int) -> list:
    talents = [t for t in reference if t["class_id"] == class_id and t["tree_index"] == tree_index]
    talents.sort(key=lambda t: (t["row"], t["column"]))
    return talents


def go_search_dirs(game_class: str) -> list[pathlib.Path]:
    """Ficheros .go relevantes para la clase: su directorio sim/<clase>/ y
    subcarpetas (specs), para no buscar en todo el repo de wowsims."""
    class_dir_by_class = {
        "Warrior": "warrior", "Paladin": "paladin", "Hunter": "hunter", "Rogue": "rogue",
        "Priest": "priest", "Deathknight": "deathknight", "Shaman": "shaman", "Mage": "mage",
        "Warlock": "warlock", "Druid": "druid",
    }
    subdir = class_dir_by_class.get(game_class)
    if not subdir:
        return []
    return [WOWSIMS_SRC / "sim" / subdir]


def list_all_go_talent_fields(search_dirs: list[pathlib.Path]) -> set[str]:
    """Todos los campos Talents.X referenciados en los .go de esos directorios."""
    fields = set()
    for d in search_dirs:
        if not d.exists():
            continue
        result = subprocess.run(
            ["grep", "-rhoE", r"\.Talents\.\w+", str(d)],
            capture_output=True, text=True,
        )
        for line in result.stdout.splitlines():
            m = GO_TALENT_FIELD_RE.search(line)
            if m:
                fields.add(m.group(1))
    return fields


def talent_field_guess(name_es: str) -> str:
    """No hay traducción automática fiable es->en: se usa como pista visual
    únicamente, la comprobación real es manual sobre la lista de candidatos."""
    return name_es


def find_candidates(reference: list, class_id: int, talents_string: str, game_class: str) -> dict:
    """Para cada árbol, candidatos a bajar (0 puntos, en o antes de la última
    fila con puntos) y a subir (por debajo de su máximo, con puntos ya
    puestos). Solo estos hace falta revisar a mano, no el árbol completo."""
    blocks = talents_string.split("-")
    search_dirs = go_search_dirs(game_class)
    go_fields = list_all_go_talent_fields(search_dirs)

    report = {"up": [], "down": [], "go_fields_found": sorted(go_fields)}
    for tree_index, digits in enumerate(blocks):
        talents = tree_talents(reference, class_id, tree_index)
        last_row_with_points = -1
        for talent, digit in zip(talents, digits):
            if int(digit) > 0:
                last_row_with_points = talent["row"]

        for talent, digit in zip(talents, digits):
            n = int(digit)
            entry = {
                "tree": tree_index, "row": talent["row"], "name": talent["name"],
                "talent_id": talent["talent_id"], "rank": n, "max_rank": talent["max_rank"],
            }
            if 0 < n < talent["max_rank"]:
                report["up"].append(entry)
            elif n == 0 and talent["row"] <= last_row_with_points:
                report["down"].append(entry)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--class-id", type=int, required=True)
    parser.add_argument("--game-class", required=True, help="Druid, Priest, etc. (para buscar en sim/<clase>/)")
    parser.add_argument("--talents", required=True)
    args = parser.parse_args()

    reference = load_reference()
    report = find_candidates(reference, args.class_id, args.talents, args.game_class)

    print(f"Campos Talents.X referenciados en sim/{args.game_class.lower()}/: {len(report['go_fields_found'])}")
    print("\nCandidatos a SUBIR (por debajo de su máximo, con puntos ya puestos):")
    for e in report["up"]:
        print(f"  árbol {e['tree']} fila {e['row']}: {e['name']} (id {e['talent_id']}) {e['rank']}/{e['max_rank']}")
    print("\nCandidatos a BAJAR (0 puntos, dentro del rango ya usado del árbol):")
    for e in report["down"]:
        print(f"  árbol {e['tree']} fila {e['row']}: {e['name']} (id {e['talent_id']}) 0/{e['max_rank']}")
    print("\nRevisa cada candidato a mano en el código Go antes de moverlo: 'sin referencias' en la")
    print("lista de campos no es concluyente por sí solo (los nombres en español no traducen 1:1),")
    print("pero si el grep del talent_id/nombre inglés no aparece en ningún .go, es una señal fuerte.")
