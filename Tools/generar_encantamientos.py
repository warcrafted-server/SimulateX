"""Genera las mejoras de encantamiento puntuables para SimulateX."""

import collections
import json
import os
import pathlib
import struct
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from mapeo_stats import RATING_TO_STATS, STAT_TO_ITEM_MOD
from rutas_addon import ADDON_ROOT

DB_PATH = pathlib.Path(__file__).resolve().parent / "wowsimcli-src" / "assets" / "database" / "db.json"
OUT_PATH = ADDON_ROOT / "SimulateX" / "Data" / "SimulateX_Encantamientos.lua"

# Los tipos ItemType 1-11 son huecos; kits también usan extraTypes. Los anillos
# comparten Finger. En armas, EnchantType separa arma de una mano, 2M, escudo y bastón.
ITEM_TYPE_TO_SLOT = {
    1: "Head", 3: "Shoulder", 4: "Back", 5: "Chest", 6: "Wrist", 7: "Hands",
    8: "Waist", 9: "Legs", 10: "Feet", 11: "Finger",
}
WEAPON_ENCHANT_TYPE_TO_SLOT = {0: "Weapon", 1: "TwoHandWeapon", 2: "Shield", 4: "Staff"}
SLOT_ORDER = (
    "Head", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs",
    "Feet", "Finger", "Weapon", "TwoHandWeapon", "Staff", "Shield", "Ranged",
)
# Profession del proto.common.proto -> SkillLine de World of Warcraft.
PROFESSION_TO_SKILL_LINE = {2: 164, 3: 333, 4: 202, 6: 773, 7: 755, 8: 165, 11: 197}


def item_mod_stats(stats: list) -> dict:
    result = {}
    for index, key in STAT_TO_ITEM_MOD.items():
        if index < len(stats) and stats[index]:
            result[key] = stats[index]
    # Un rating de objeto alimenta a la vez los índices de melee y hechizo.
    for key, indices in RATING_TO_STATS.items():
        value = max((stats[i] for i in indices if i < len(stats)), default=0)
        if value:
            result[key] = value
    return result


def read_wdbc_ids(path: pathlib.Path) -> set:
    data = path.read_bytes()
    signature, record_count, field_count, record_size, _ = struct.unpack("<4s4I", data[:20])
    if signature != b"WDBC" or record_size != field_count * 4:
        raise ValueError(f"{path.name}: formato WDBC inesperado")
    return {
        struct.unpack_from("<i", data, 20 + index * record_size)[0]
        for index in range(record_count)
    }


def slots_for(enchant: dict) -> list:
    if enchant["type"] == 13:
        slot = WEAPON_ENCHANT_TYPE_TO_SLOT.get(enchant.get("enchantType", 0))
        if slot is None:
            raise ValueError(f"EnchantType desconocido en {enchant['effectId']}: {enchant.get('enchantType')}")
        return [slot]
    if enchant["type"] == 14:
        return ["Ranged"]
    slots = [ITEM_TYPE_TO_SLOT[enchant["type"]]]
    slots.extend(ITEM_TYPE_TO_SLOT[extra_type] for extra_type in enchant.get("extraTypes", []))
    return slots


def lua_stats(stats: dict) -> str:
    parts = ", ".join(f"{key} = {value:g}" for key, value in sorted(stats.items()))
    return f"{{ {parts} }}"


def main() -> None:
    dbc_dir = os.environ.get("SIMX_DBC_DIR")
    if not dbc_dir:
        raise SystemExit("Falta SIMX_DBC_DIR (directorio con las DBC del servidor)")

    enchants = json.loads(DB_PATH.read_text(encoding="utf-8")).get("enchants", [])
    enchantment_ids = read_wdbc_ids(pathlib.Path(dbc_dir) / "SpellItemEnchantment.dbc")
    spell_ids = read_wdbc_ids(pathlib.Path(dbc_dir) / "Spell.dbc")
    by_slot = collections.defaultdict(list)
    omitted = collections.Counter()
    untranslated_professions = set()

    for enchant in enchants:
        stats = item_mod_stats(enchant.get("stats", []))
        if not stats:
            omitted["sin estadísticas puntuables"] += 1
            continue
        if enchant["effectId"] not in enchantment_ids or enchant["spellId"] not in spell_ids:
            omitted["fuera de 3.3.5a"] += 1
            continue

        profession = enchant.get("requiredProfession")
        if profession is None:
            skill_line = None
        else:
            skill_line = PROFESSION_TO_SKILL_LINE.get(profession, profession)
            if profession not in PROFESSION_TO_SKILL_LINE:
                untranslated_professions.add(profession)

        record = {
            "effect": enchant["effectId"],
            "spell": enchant["spellId"],
            "stats": stats,
            "prof": skill_line,
            "quality": enchant["quality"],
        }
        for slot in slots_for(enchant):
            by_slot[slot].append(record)

    lines = [
        "-- Generado por Tools/generar_encantamientos.py desde wowsims y las DBC del servidor.",
        "-- Finger agrupa ambos anillos; Weapon, TwoHandWeapon, Shield y Staff distinguen EnchantType.",
        "SimulateX_Encantamientos = {",
    ]
    for slot in SLOT_ORDER:
        if slot not in by_slot:
            continue
        lines.append(f'  ["{slot}"] = {{')
        for record in sorted(by_slot[slot], key=lambda item: item["effect"]):
            prof = "nil" if record["prof"] is None else str(record["prof"])
            lines.append(
                f"    {{ effect = {record['effect']}, spell = {record['spell']}, "
                f"stats = {lua_stats(record['stats'])}, prof = {prof}, quality = {record['quality']} }},"
            )
        lines.append("  },")
    lines.append("}")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    counts = {slot: len(by_slot[slot]) for slot in SLOT_ORDER if slot in by_slot}
    print(f"-> {OUT_PATH} ({sum(counts.values())} entradas por hueco: {counts})")
    print(f"Omitidos sin estadísticas puntuables: {omitted['sin estadísticas puntuables']}")
    print(f"Omitidos fuera de 3.3.5a: {omitted['fuera de 3.3.5a']}")
    if untranslated_professions:
        print(f"AVISO: enum de profesión sin traducir: {sorted(untranslated_professions)}")


if __name__ == "__main__":
    main()
