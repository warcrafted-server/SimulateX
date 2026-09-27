"""Extrae objetos de acore_world (tabla item_template) para cubrir niveles de
personaje bajos/medios (1-79), donde no existe ningún gearset de wowsims ni
dato de simulación real. Alternativa a scrapear db.warcrafted.com: los datos
ya vienen estructurados en columnas (stats, slot, clases permitidas), sin
necesidad de parsear HTML.

Requiere las credenciales de conexión como variables de entorno (nunca se
escriben en este repo): SIMX_DB_HOST, SIMX_DB_PORT, SIMX_DB_USER,
SIMX_DB_PASS, SIMX_DB_NAME. Solo ejecuta SELECT, de solo lectura.
"""

import json
import os
import pathlib
import subprocess

DATA_DIR = pathlib.Path(__file__).resolve().parent.parent / "Data"

# InventoryType (mismo estándar usado en mapeo_slots.py) -> nombre de slot,
# solo para referencia legible en el JSON de salida.
INVTYPE_NAMES = {
    1: "head", 2: "neck", 3: "shoulder", 4: "shirt", 5: "chest", 6: "waist",
    7: "legs", 8: "feet", 9: "wrist", 10: "hands", 11: "finger", 12: "trinket",
    13: "weapon", 14: "shield", 15: "ranged", 16: "cloak", 17: "weapon2h",
    20: "robe", 21: "weapon_mainhand", 22: "weapon_offhand", 23: "holdable",
    25: "thrown", 26: "ranged_right", 28: "relic",
}

QUERY = """
SELECT entry, name, class, subclass, InventoryType, AllowableClass,
       ItemLevel, RequiredLevel,
       stat_type1, stat_value1, stat_type2, stat_value2,
       stat_type3, stat_value3, stat_type4, stat_value4,
       stat_type5, stat_value5, stat_type6, stat_value6
FROM item_template
WHERE (RequiredLevel = 0 OR RequiredLevel BETWEEN {min_level} AND {max_level})
  AND InventoryType != 0
ORDER BY entry;
"""


def run_query(query: str) -> list:
    env = os.environ
    cmd = [
        "mysql",
        "-h", env["SIMX_DB_HOST"],
        "-P", env["SIMX_DB_PORT"],
        "-u", env["SIMX_DB_USER"],
        f"-p{env['SIMX_DB_PASS']}",
        env["SIMX_DB_NAME"],
        "--batch", "--raw",
        "-e", query,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(f"consulta fallida: {result.stderr}")

    lines = result.stdout.strip().split("\n")
    header = lines[0].split("\t")
    rows = [line.split("\t") for line in lines[1:]]
    return [dict(zip(header, row)) for row in rows]


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--min-level", type=int, default=1)
    parser.add_argument("--max-level", type=int, default=79)
    args = parser.parse_args()

    required_env = ["SIMX_DB_HOST", "SIMX_DB_PORT", "SIMX_DB_USER", "SIMX_DB_PASS", "SIMX_DB_NAME"]
    missing = [v for v in required_env if v not in os.environ]
    if missing:
        raise SystemExit(f"Faltan variables de entorno: {missing}")

    rows = run_query(QUERY.format(min_level=args.min_level, max_level=args.max_level))

    items = {}
    for row in rows:
        entry = int(row["entry"])
        stats = {}
        for i in range(1, 7):
            stat_type = int(row[f"stat_type{i}"])
            stat_value = int(row[f"stat_value{i}"])
            if stat_type and stat_value:
                stats[stat_type] = stats.get(stat_type, 0) + stat_value

        items[entry] = {
            "id": entry,
            "name": row["name"],
            "item_level": int(row["ItemLevel"]),
            "required_level": int(row["RequiredLevel"]),
            "class": int(row["class"]),
            "subclass": int(row["subclass"]),
            "inventory_type": int(row["InventoryType"]),
            "allowable_class_mask": int(row["AllowableClass"]),
            "stats": stats,
        }

    out_path = DATA_DIR / "items_bajo_nivel.json"
    out_path.write_text(json.dumps(items, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Extraídos {len(items)} objetos (nivel {args.min_level}-{args.max_level}) -> {out_path}")


if __name__ == "__main__":
    main()
