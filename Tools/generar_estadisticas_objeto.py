"""Genera Addon/SimulateX/Data/SimulateX_ItemStats.lua: las estadísticas de cada
objeto equipable (item_template) y las tablas de las DBC del servidor para
sufijos aleatorios y reliquias que escalan con el nivel. El addon las usa en
vez de GetItemStats, que con el addon activo deja al cliente sin pintar en
rojo lo que no se puede usar.

Fórmulas replicadas del core (acore-playerbots):
- Factor de sufijo: GenerateEnchSuffixFactor (ItemEnchantmentMgr.cpp).
- Valor de un sufijo: AllocationPct × factor / 10000 (PlayerStorage.cpp).
- Reliquias: Player::_ApplyItemBonuses con ScalingStatDistribution/Values.

Requiere Data/items_bd.json (extraer_objetos_bd.py) y el env SIMX_DBC_DIR.
"""

import json
import os
import pathlib
import struct

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
ITEMS_BD_PATH = TOOLS_DIR.parent / "Data" / "items_bd.json"
OUT_PATH = TOOLS_DIR.parent / "Addon" / "SimulateX" / "Data" / "SimulateX_ItemStats.lua"

SOCKET_KEYS = {1: "m", 2: "r", 4: "y", 8: "u"}  # meta, rojo, amarillo, azul

# Índice de RandPropPoints por InventoryType (GenerateEnchSuffixFactor).
SUFFIX_SLOT_INDEX = {
    1: 0, 4: 0, 5: 0, 7: 0, 17: 0, 20: 0,
    3: 1, 6: 1, 8: 1, 10: 1, 12: 1,
    2: 2, 9: 2, 11: 2, 14: 2, 16: 2, 23: 2,
    13: 3, 21: 3, 22: 3,
    15: 4, 25: 4, 26: 4,
}
QUALITY_POINTS_OFFSET = {2: 11, 3: 6, 4: 1}  # uncommon, rare, epic en RandPropPoints

ENCHANT_TYPE_RESISTANCE = 4
ENCHANT_TYPE_STAT = 5
PER_LINE = 12


def read_wdbc(path: pathlib.Path) -> dict:
    """id (campo 0) -> tupla de enteros con signo del registro."""
    data = path.read_bytes()
    sig, n_records, n_fields, record_size, _ = struct.unpack("<4s4I", data[:20])
    if sig != b"WDBC" or record_size != n_fields * 4:
        raise ValueError(f"{path.name}: formato WDBC inesperado")
    records = {}
    for i in range(n_records):
        offset = 20 + i * record_size
        row = struct.unpack(f"<{n_fields}i", data[offset:offset + record_size])
        records[row[0]] = row
    return records


def enchant_stats(enchant: tuple) -> list:
    """[(clave, cantidad)] de un SpellItemEnchantment: estadística (tipo 5)
    o armadura (tipo 4, escuela 0). Los demás efectos no son estadísticas."""
    stats = []
    for k in range(3):
        effect, amount, arg = enchant[2 + k], enchant[5 + k], enchant[11 + k]
        if effect == ENCHANT_TYPE_STAT:
            stats.append((str(arg), amount))
        elif effect == ENCHANT_TYPE_RESISTANCE and arg == 0:
            stats.append(("a", amount))
    return stats


def suffix_factor(item: dict, rand_points: dict) -> int:
    points = rand_points.get(item["item_level"])
    slot_index = SUFFIX_SLOT_INDEX.get(item["inventory_type"])
    offset = QUALITY_POINTS_OFFSET.get(item["quality"])
    if not points or slot_index is None or offset is None:
        return 0
    return points[offset + slot_index]


def item_entry(item: dict, rand_points: dict, item_sets: dict) -> str:
    parts = [f"{stat}={value}" for stat, value in item["stats"].items()]
    if item["id"] in item_sets:
        parts.append(f"t={item_sets[item['id']]}")  # ItemSet.dbc, umbrales en SimulateX_ItemSets
    if item["armor"]:
        parts.append(f"a={item['armor']}")
    if item["block"]:
        parts.append(f"b={item['block']}")
    if item["delay"] and (item["dmg_max1"] or item["dmg_max2"]):
        dps = ((item["dmg_min1"] + item["dmg_max1"]) + (item["dmg_min2"] + item["dmg_max2"])) / 2 / (item["delay"] / 1000)
        parts.append(f"d={round(dps, 2)}")
    for color in item["socket_colors"]:
        key = SOCKET_KEYS.get(color)
        if key:
            parts.append(f"{key}=1")
    if item.get("socket_bonus") and any(c in (2, 4, 8) for c in item["socket_colors"]):
        parts.append(f"s={item['socket_bonus']}")  # SpellItemEnchantment, en SimulateX_SocketBonus
    if item["random_suffix"]:
        factor = suffix_factor(item, rand_points)
        if factor:
            parts.append(f"f={factor}")
    if item["scaling_stat_distribution"]:
        parts.append(f"x={item['scaling_stat_distribution']}")
        parts.append(f"v={item['scaling_stat_value']}")
    return ",".join(parts)


def lua_string_table(name: str, values: dict) -> list:
    entries = [f'[{key}]="{value}"' for key, value in sorted(values.items()) if value]
    lines = [f"{name} = {{"]
    for i in range(0, len(entries), PER_LINE):
        lines.append("  " + ",".join(entries[i:i + PER_LINE]) + ",")
    lines.append("}")
    return lines


def main() -> None:
    dbc_dir = os.environ.get("SIMX_DBC_DIR")
    if not dbc_dir:
        raise SystemExit("Falta la variable de entorno SIMX_DBC_DIR (directorio con las DBCs del servidor)")
    dbc_dir = pathlib.Path(dbc_dir)
    if not ITEMS_BD_PATH.exists():
        raise SystemExit(f"Falta {ITEMS_BD_PATH}. Ejecuta extraer_objetos_bd.py primero.")

    items = json.loads(ITEMS_BD_PATH.read_text(encoding="utf-8"))
    rand_points = read_wdbc(dbc_dir / "RandPropPoints.dbc")
    enchants = read_wdbc(dbc_dir / "SpellItemEnchantment.dbc")
    rand_props = read_wdbc(dbc_dir / "ItemRandomProperties.dbc")
    rand_suffixes = read_wdbc(dbc_dir / "ItemRandomSuffix.dbc")
    scaling_dist = read_wdbc(dbc_dir / "ScalingStatDistribution.dbc")
    scaling_values = read_wdbc(dbc_dir / "ScalingStatValues.dbc")

    # Conjuntos (ItemSet.dbc): piezas en campos 18-34, umbrales de bonus en 43-50
    item_set_of = {}
    set_thresholds = {}
    for set_id, row in read_wdbc(dbc_dir / "ItemSet.dbc").items():
        thresholds = sorted({t for t in row[43:51] if t > 0})
        if not thresholds:
            continue
        set_thresholds[set_id] = ",".join(str(t) for t in thresholds)
        for item_id in row[18:35]:
            if item_id:
                item_set_of[item_id] = set_id

    item_entries = {item["id"]: item_entry(item, rand_points, item_set_of) for item in items.values()}

    # Propiedad aleatoria (id positivo en el link): cantidades fijas.
    props = {}
    for prop_id, row in rand_props.items():
        stats = [s for enchant_id in row[2:7] if enchant_id in enchants for s in enchant_stats(enchants[enchant_id])]
        props[prop_id] = ",".join(f"{key}={amount}" for key, amount in stats)

    # Sufijo aleatorio (id negativo en el link): porcentaje sobre el factor del objeto.
    suffixes = {}
    for suffix_id, row in rand_suffixes.items():
        stats = []
        for k in range(5):
            enchant_id, pct = row[19 + k], row[24 + k]
            if enchant_id in enchants and pct:
                stats += [(key, pct) for key, _amount in enchant_stats(enchants[enchant_id])]
        suffixes[suffix_id] = ",".join(f"{key}={pct}" for key, pct in stats)

    # Bonificación de ranura (item_template.socketBonus): mismo formato que
    # una propiedad aleatoria, indexada por id de encantamiento
    socket_bonuses = {}
    for item in items.values():
        enchant_id = item.get("socket_bonus")
        if enchant_id and enchant_id in enchants and enchant_id not in socket_bonuses:
            socket_bonuses[enchant_id] = ",".join(f"{key}={amount}" for key, amount in enchant_stats(enchants[enchant_id]))

    used_dist = {item["scaling_stat_distribution"] for item in items.values() if item["scaling_stat_distribution"]}
    dist_lines = ["SimulateX_ScalingDist = {"]
    for dist_id in sorted(used_dist):
        row = scaling_dist[dist_id]
        pairs = ",".join(f"{{{row[1 + i]},{row[11 + i]}}}" for i in range(10) if row[1 + i] >= 0 and row[11 + i])
        dist_lines.append(f"  [{dist_id}] = {{ maxLevel = {row[21]}, stats = {{{pairs}}} }},")
    dist_lines.append("}")

    value_lines = ["SimulateX_ScalingValues = {"]
    for row in sorted(scaling_values.values(), key=lambda r: r[1]):
        ints = lambda a, b: ",".join(str(v) for v in row[a:b])
        value_lines.append(
            f"  [{row[1]}] = {{ ssd = {{{ints(2, 6)}}}, armor = {{{ints(6, 10)}}}, dps = {{{ints(10, 16)}}}, "
            f"spellPower = {row[16]}, ssd2 = {row[17]}, ssd3 = {row[18]}, armor2 = {{{ints(19, 24)}}} }},")
    value_lines.append("}")

    lines = ["-- Generado por Tools/generar_estadisticas_objeto.py desde item_template y las DBC del servidor."]
    lines += lua_string_table("SimulateX_ItemStats", item_entries)
    lines += lua_string_table("SimulateX_RandomProps", props)
    lines += lua_string_table("SimulateX_RandomSuffixes", suffixes)
    lines += lua_string_table("SimulateX_SocketBonus", socket_bonuses)
    lines += lua_string_table("SimulateX_ItemSets", set_thresholds)
    lines += dist_lines + value_lines
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"-> {OUT_PATH} ({sum(1 for v in item_entries.values() if v)} objetos, {len(props)} propiedades, "
          f"{len(suffixes)} sufijos, {len(used_dist)} distribuciones de reliquia)")


if __name__ == "__main__":
    main()
