"""Parsea los XML crudos de Data/items/ (extraídos de db.warcrafted.com) y
extrae los campos estructurados necesarios para decidir si un objeto es
candidato válido para una build concreta: slot de equipo, clases permitidas,
nivel de objeto y tipo de arma/armadura.

La restricción de clase no viene en ningún campo XML estructurado del export
de AoWoW: solo aparece como texto libre dentro del htmlTooltip
("Clases: <a href="?class=N">Nombre</a>, ..."), así que se extrae de ahí.
"""

import json
import pathlib
import re

DATA_ITEMS_DIR = pathlib.Path(__file__).resolve().parent.parent / "Data" / "items"
OUT_PATH = pathlib.Path(__file__).resolve().parent.parent / "Data" / "items_procesados.json"

# IDs de clase estándar de la API de WoW (los mismos que usa AoWoW en sus
# enlaces ?class=N), estables desde siempre en el juego.
AOWOW_CLASS_ID_TO_NAME = {
    1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest",
    6: "Deathknight", 7: "Shaman", 8: "Mage", 9: "Warlock", 11: "Druid",
}

INVENTORY_SLOT_RE = re.compile(r'<inventorySlot id="(\d+)">')
ITEM_LEVEL_RE = re.compile(r"<level>(\d+)</level>")
CLASS_LINK_RE = re.compile(r'href="\?class=(\d+)"')
NAME_RE = re.compile(r"<name><!\[CDATA\[([^\]]*)\]\]></name>")
QUALITY_RE = re.compile(r'<quality id="(\d+)">')
SUBCLASS_RE = re.compile(r'<subclass id="(\d+)">')

# Reliquias (inventorySlot 28): el tooltip no lista "Clases: ..." porque la
# restricción es implícita al subtipo de reliquia, no un texto libre.
RELIC_SUBCLASS_TO_CLASS = {
    7: "Paladin",       # Tratados (Libram)
    8: "Druid",         # Ídolos
    9: "Shaman",        # Tótems
    10: "Deathknight",  # Sigilos
}


def parse_item_xml(item_id: int, xml_text: str) -> dict:
    slot_match = INVENTORY_SLOT_RE.search(xml_text)
    level_match = ITEM_LEVEL_RE.search(xml_text)
    name_match = NAME_RE.search(xml_text)
    quality_match = QUALITY_RE.search(xml_text)
    class_ids = sorted({int(c) for c in CLASS_LINK_RE.findall(xml_text)})
    allowed_classes = [AOWOW_CLASS_ID_TO_NAME[c] for c in class_ids if c in AOWOW_CLASS_ID_TO_NAME]

    inventory_slot = int(slot_match.group(1)) if slot_match else None
    if inventory_slot == 28 and not allowed_classes:
        # Reliquia (Libram/Ídolo/Tótem/Sigilo): restricción de clase implícita
        # al subtipo, nunca aparece como texto "Clases: ..." en el tooltip.
        subclass_match = SUBCLASS_RE.search(xml_text)
        subclass_id = int(subclass_match.group(1)) if subclass_match else None
        if subclass_id in RELIC_SUBCLASS_TO_CLASS:
            allowed_classes = [RELIC_SUBCLASS_TO_CLASS[subclass_id]]

    return {
        "id": item_id,
        "name": name_match.group(1) if name_match else None,
        "item_level": int(level_match.group(1)) if level_match else None,
        "quality": int(quality_match.group(1)) if quality_match else None,
        "inventory_slot": inventory_slot,
        # Sin restricción de clase = utilizable por cualquiera (armas/joyas
        # genéricas), no un objeto sin datos.
        "allowed_classes": allowed_classes,
    }


def main() -> None:
    items = {}
    skipped = 0
    for xml_path in sorted(DATA_ITEMS_DIR.glob("*.xml")):
        item_id = int(xml_path.stem)
        xml_text = xml_path.read_text(encoding="utf-8")
        parsed = parse_item_xml(item_id, xml_text)
        if parsed["inventory_slot"] is None:
            skipped += 1
            continue
        items[item_id] = parsed

    OUT_PATH.write_text(json.dumps(items, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Procesados {len(items)} objetos ({skipped} omitidos sin inventorySlot) -> {OUT_PATH}")


if __name__ == "__main__":
    main()
