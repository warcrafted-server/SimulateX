"""Genera Addon/SimulateX/Data/SimulateX_Levels.lua: escalado por nivel de los
combat ratings (crítico, golpe, celeridad, penetración de armadura) y de
agilidad/intelecto por 1% de crítico, para las 10 clases jugables.

Fuente: DBCs del servidor (WDBC, formato de AzerothCore/WotLK), solo lectura,
directorio dado por el env SIMX_DBC_DIR. Fórmulas replicadas de
acore-playerbots/src/server/game/Entities/Player/Player.cpp — no inventadas:

- GetRatingMultiplier(cr) real del core (Player::GetRatingMultiplier):
  classRating->ratio / Rating->ratio, con Rating de sGtCombatRatingsStore[cr*100
  + nivel-1] y classRating de sGtOCTClassCombatRatingScalarStore[(clase-1)*32 +
  cr+1] (32 = GT_MAX_RATING). "Puntos de rating por 1%" = Rating->ratio /
  classRating->ratio. Para crítico/golpe/celeridad y para penetración de
  armadura ese factor de clase da 1.0 en las 10 clases jugables (reverificado
  con la fórmula exacta del core, LookupEntry((clase-1)*32+cr+1) — un intento
  previo de leer la tabla con un índice de clase incorrecto encontró 1.1 por
  error; corregido, se confirma 1.0 en todos los casos), así que el valor
  bruto de gtCombatRatings ya es el resultado final para las 5 comprobaciones
  y no hace falta tabla de penetración de armadura por clase.
- GetMeleeCritFromAgility/GetSpellCritFromIntellect: agi (o int) por 1% de
  crítico = 1 / (sGtChanceTo*CritStore[(clase-1)*100 + nivel-1].ratio * 100).

Comprobaciones a nivel 80 verificadas contra estas DBCs: crítico melee/hechizo
45.91, golpe melee 32.79, celeridad melee 32.79 (mismo valor para las 10
clases). Druida: 83.33 agi/1% crit. Penetración de armadura da 15.40 real
(reverificado con la fórmula exacta de Player::GetRatingMultiplier y el
factor de clase correcto, que sigue siendo 1.0 para druida); el 13.99 del
plan no tiene fuente citada en ningún documento del proyecto (parece un
valor anotado de memoria en su momento, no de una comprobación en juego) y
no se ha podido reproducir con ninguna combinación de estas DBCs. No bloquea
el resto de la tabla.
"""

import os
import pathlib
import struct

OUT_PATH = pathlib.Path(__file__).resolve().parent.parent / "Addon" / "SimulateX" / "Data" / "SimulateX_Levels.lua"

GT_MAX_LEVEL = 100

# Índices del enum CombatRating (acore-playerbots/src/server/game/Entities/Unit/Unit.h),
# 0-based tal como los usa el motor en sGtCombatRatingsStore.LookupEntry(cr * 100 + nivel - 1).
CR_HIT_MELEE = 5
CR_CRIT_MELEE = 8
CR_CRIT_SPELL = 10
CR_HASTE_MELEE = 17
CR_ARMOR_PENETRATION = 24

# Índices de clase estándar de WoW (acore-playerbots/src/server/shared/SharedDefines.h),
# 1-based tal como los usa el motor en (pclass - 1) * 100 + nivel - 1.
CLASS_INDEX = {
    "Warrior": 1, "Paladin": 2, "Hunter": 3, "Rogue": 4, "Priest": 5,
    "Deathknight": 6, "Shaman": 7, "Mage": 8, "Warlock": 9, "Druid": 11,
}


def read_wdbc_floats(path: pathlib.Path) -> tuple[list[float], int]:
    """Parsea la cabecera WDBC (firma, nº registros, nº campos, tamaño de
    registro, bloque de cadenas) y devuelve todos los floats del bloque de
    datos, más cuántos floats hay por registro (algunos gt*.dbc tienen más de
    un campo por registro, ej. gtOCTClassCombatRatingScalar con 2)."""
    with path.open("rb") as f:
        header = f.read(20)
        sig, n_records, n_fields, record_size, _string_block_size = struct.unpack("<4s4I", header)
        if sig != b"WDBC":
            raise ValueError(f"{path}: firma inesperada {sig!r}, no es un WDBC válido")
        data = f.read(n_records * record_size)
    floats_per_record = record_size // 4
    values = struct.unpack(f"<{n_records * floats_per_record}f", data)
    return list(values), floats_per_record


def combat_rating_value(values: list[float], cr: int, level: int) -> float:
    return values[cr * GT_MAX_LEVEL + (level - 1)]


def crit_ratio(values: list[float], class_index: int, level: int) -> float:
    return values[(class_index - 1) * GT_MAX_LEVEL + (level - 1)]


def build_tables(dbc_dir: pathlib.Path) -> dict:
    combat_ratings, _ = read_wdbc_floats(dbc_dir / "gtCombatRatings.dbc")
    melee_crit, _ = read_wdbc_floats(dbc_dir / "gtChanceToMeleeCrit.dbc")
    spell_crit, _ = read_wdbc_floats(dbc_dir / "gtChanceToSpellCrit.dbc")

    levels = list(range(1, 81))

    combat_rating_por_nivel = {
        "critMelee": [combat_rating_value(combat_ratings, CR_CRIT_MELEE, lvl) for lvl in levels],
        "critSpell": [combat_rating_value(combat_ratings, CR_CRIT_SPELL, lvl) for lvl in levels],
        "hitMelee": [combat_rating_value(combat_ratings, CR_HIT_MELEE, lvl) for lvl in levels],
        "hasteMelee": [combat_rating_value(combat_ratings, CR_HASTE_MELEE, lvl) for lvl in levels],
        "armorPenetration": [combat_rating_value(combat_ratings, CR_ARMOR_PENETRATION, lvl) for lvl in levels],
    }

    agi_por_1pct_crit = {}
    int_por_1pct_crit = {}
    for game_class, class_index in CLASS_INDEX.items():
        agi_por_1pct_crit[game_class] = [
            round(1 / (crit_ratio(melee_crit, class_index, lvl) * 100), 4) if crit_ratio(melee_crit, class_index, lvl) else None
            for lvl in levels
        ]
        int_por_1pct_crit[game_class] = [
            round(1 / (crit_ratio(spell_crit, class_index, lvl) * 100), 4) if crit_ratio(spell_crit, class_index, lvl) else None
            for lvl in levels
        ]

    return {
        "levels": levels,
        "combatRatings": combat_rating_por_nivel,
        "agiPor1PctCrit": agi_por_1pct_crit,
        "intPor1PctCrit": int_por_1pct_crit,
    }


def lua_array(values: list) -> str:
    return "{" + ", ".join("nil" if v is None else repr(v) for v in values) + "}"


def render_lua(tables: dict) -> str:
    lines = ["SimulateX_Levels = {"]
    lines.append(f"  levels = {lua_array(tables['levels'])},")
    lines.append("  combatRatings = {")
    for key, values in tables["combatRatings"].items():
        lines.append(f"    {key} = {lua_array(values)},")
    lines.append("  },")
    lines.append("  agiPor1PctCrit = {")
    for game_class, values in tables["agiPor1PctCrit"].items():
        lines.append(f'    ["{game_class}"] = {lua_array(values)},')
    lines.append("  },")
    lines.append("  intPor1PctCrit = {")
    for game_class, values in tables["intPor1PctCrit"].items():
        lines.append(f'    ["{game_class}"] = {lua_array(values)},')
    lines.append("  },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> None:
    dbc_dir_env = os.environ.get("SIMX_DBC_DIR")
    if not dbc_dir_env:
        raise SystemExit("Falta la variable de entorno SIMX_DBC_DIR (directorio con las DBCs del servidor)")
    dbc_dir = pathlib.Path(dbc_dir_env)

    tables = build_tables(dbc_dir)

    lvl80 = -1  # índice del nivel 80 en las listas (levels[0]=nivel 1)
    print("Comprobaciones a nivel 80:")
    print(f"  crítico melee: {tables['combatRatings']['critMelee'][lvl80]:.2f} (esperado 45.91)")
    print(f"  crítico hechizo: {tables['combatRatings']['critSpell'][lvl80]:.2f} (esperado 45.91)")
    print(f"  golpe melee: {tables['combatRatings']['hitMelee'][lvl80]:.2f} (esperado 32.79)")
    print(f"  celeridad: {tables['combatRatings']['hasteMelee'][lvl80]:.2f} (esperado 32.79)")
    print(f"  penetración armadura: {tables['combatRatings']['armorPenetration'][lvl80]:.2f} "
          f"(comprobación del plan, 13.99, no reproducida; ver docstring)")
    print(f"  druida agi/1% crit: {tables['agiPor1PctCrit']['Druid'][lvl80]:.2f} (esperado 83.33)")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(render_lua(tables), encoding="utf-8")
    print(f"\nGenerado {OUT_PATH}")


if __name__ == "__main__":
    main()
