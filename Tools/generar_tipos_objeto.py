"""Genera Addon/SimulateX/Data/SimulateX_ItemTypes.lua con dos tablas que el
addon usa para saber si la clase puede equiparse un objeto sin leer su
tooltip (construir un tooltip oculto mientras se muestra otro le quita al
cliente el rojo de "no usable"):

- SimulateX_ItemTypes: id -> clase × 100 + subclase de item_template, para
  armas y armaduras con restricción de tipo. Se omiten armadura subclase 0
  (anillos, cuellos, abalorios, sostener) y capas: cualquier clase los lleva.
- SimulateX_ItemClasses: id -> AllowableClass, solo para objetos equipables
  restringidos a algunas clases (la línea "Clases:" del tooltip).
"""

import json
import pathlib

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
ITEMS_BD_PATH = TOOLS_DIR.parent / "Data" / "items_bd.json"
OUT_PATH = TOOLS_DIR.parent / "Addon" / "SimulateX" / "Data" / "SimulateX_ItemTypes.lua"

WEAPON_CLASS = 2
ARMOR_CLASS = 4
ARMOR_SUBCLASS_MISC = 0
INVTYPE_CLOAK = 16
ALL_CLASSES_MASK = 1535  # bits de las 10 clases (el 1024 es druida, el 512 no se usa)
PER_LINE = 20


def item_type_code(item: dict) -> int | None:
    if item["class"] == WEAPON_CLASS:
        return WEAPON_CLASS * 100 + item["subclass"]
    if item["class"] == ARMOR_CLASS:
        if item["subclass"] == ARMOR_SUBCLASS_MISC or item["inventory_type"] == INVTYPE_CLOAK:
            return None
        return ARMOR_CLASS * 100 + item["subclass"]
    return None


def lua_table(name: str, values: dict) -> list:
    entries = [f"[{item_id}]={value}" for item_id, value in sorted(values.items())]
    lines = [f"{name} = {{"]
    for i in range(0, len(entries), PER_LINE):
        lines.append("  " + ",".join(entries[i:i + PER_LINE]) + ",")
    lines.append("}")
    return lines


def main() -> None:
    if not ITEMS_BD_PATH.exists():
        raise SystemExit(f"Falta {ITEMS_BD_PATH}. Ejecuta extraer_objetos_bd.py primero.")
    items = json.loads(ITEMS_BD_PATH.read_text(encoding="utf-8"))

    codes, class_masks = {}, {}
    for item in items.values():
        code = item_type_code(item)
        if code is not None:
            codes[item["id"]] = code
        mask = item["allowable_class_mask"]
        if item["inventory_type"] and mask not in (-1, 0) and (mask & ALL_CLASSES_MASK) not in (0, ALL_CLASSES_MASK):
            class_masks[item["id"]] = mask & ALL_CLASSES_MASK

    lines = ["-- Generado por Tools/generar_tipos_objeto.py desde item_template."]
    lines += lua_table("SimulateX_ItemTypes", codes)
    lines += lua_table("SimulateX_ItemClasses", class_masks)
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"-> {OUT_PATH} ({len(codes)} tipos, {len(class_masks)} con restricción de clase)")


if __name__ == "__main__":
    main()
