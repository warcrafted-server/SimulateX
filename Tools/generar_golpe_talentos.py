"""Genera Addon/SimulateX/Data/SimulateX_GolpeTalentos.lua: el golpe que dan
los talentos, para que los topes usen los del jugador y no los del preset de
wowsims (block.nonGear de modelo_caps.py los lleva ya sumados).

- talentos[CLASE]: talentos que se aplican al propio jugador un aura de golpe
  (SpellAuraDefines.h): 54 MOD_HIT_CHANCE (cuerpo a cuerpo y distancia), 55
  MOD_SPELL_HIT_CHANCE, 199 MOD_INCREASES_SPELL_PCT_TO_HIT (por escuela) o
  107 ADD_FLAT_MODIFIER con SPELLMOD_RESIST_MISS_CHANCE (16, hechizos de la
  clase), en rating de nivel 80 por rango (EffectBasePoints + 1 de
  Spell.dbc, en %). tab/tier/col en la numeración de GetTalentInfo (1-based).
- presets[buildId]: golpe de talentos del preset de cada build, en rating.

wowsims mete en block.nonGear el golpe de algunos talentos (Equilibrio de
poder, Puntería centrada) pero no el de los que van por escuela o hechizo
(Enfoque de las Sombras, Precisión elemental, Enfoque Arcano), que aplica
dentro del hechizo. El addon usa max(0, nonGear - preset) + los del jugador,
así que cuenta todos. No mira condiciones (arma equipada, escuela): los
talentos de golpe de cada spec son de sus propios hechizos.

Requiere SIMX_DBC_DIR. No simula nada.
"""

import os
import pathlib
import struct
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from generar_db_addon import BUILDS_DIR, SIMS_DIR, SPEC_INFO, builds_by_build_id
from simular_builds import load_json
from validar_talentos import CLASS_ID_TO_GAME_CLASS, load_reference, tree_talents
from modelo_caps import MELEE_HIT_PER_PCT, SPELL_HIT_PER_PCT
from rutas_addon import ADDON_ROOT

OUT_PATH = ADDON_ROOT / "SimulateX" / "Data" / "SimulateX_GolpeTalentos.lua"

# Spell.dbc (DBCStructure.h::SpellEntry)
EFFECT_FIELD, BASE_POINTS_FIELD, TARGET_FIELD, AURA_FIELD, MISC_FIELD = 71, 80, 86, 95, 110
SPELL_EFFECT_APPLY_AURA = 6
TARGET_UNIT_CASTER = 1
HIT_AURAS = {54: "meleeHit", 55: "spellHit", 199: "spellHit"}
AURA_ADD_FLAT_MODIFIER, SPELLMOD_RESIST_MISS_CHANCE = 107, 16
RATING_PER_PCT = {"meleeHit": MELEE_HIT_PER_PCT, "spellHit": SPELL_HIT_PER_PCT}
CLASS_FILE = {"Warrior": "WARRIOR", "Paladin": "PALADIN", "Hunter": "HUNTER", "Rogue": "ROGUE",
              "Priest": "PRIEST", "Deathknight": "DEATHKNIGHT", "Shaman": "SHAMAN", "Mage": "MAGE",
              "Warlock": "WARLOCK", "Druid": "DRUID"}


def spell_hit_auras(dbc_dir: pathlib.Path) -> dict:
    """hechizo -> {stat: %} de sus efectos de aura de golpe."""
    data = (dbc_dir / "Spell.dbc").read_bytes()
    _, n_records, _, record_size, _ = struct.unpack("<4s4I", data[:20])
    result = {}
    for i in range(n_records):
        base = 20 + i * record_size
        effects = struct.unpack_from("<3i", data, base + EFFECT_FIELD * 4)
        points = struct.unpack_from("<3i", data, base + BASE_POINTS_FIELD * 4)
        targets = struct.unpack_from("<3i", data, base + TARGET_FIELD * 4)
        auras = struct.unpack_from("<3i", data, base + AURA_FIELD * 4)
        miscs = struct.unpack_from("<3i", data, base + MISC_FIELD * 4)
        for effect, value, target, aura, misc in zip(effects, points, targets, auras, miscs):
            if effect != SPELL_EFFECT_APPLY_AURA or target != TARGET_UNIT_CASTER or value + 1 <= 0:
                continue
            stat = HIT_AURAS.get(aura)
            if aura == AURA_ADD_FLAT_MODIFIER and misc == SPELLMOD_RESIST_MISS_CHANCE:
                stat = "spellHit"
            if stat:
                spell = struct.unpack_from("<i", data, base)[0]
                result.setdefault(spell, {})[stat] = value + 1
    return result


def main() -> None:
    dbc_dir = os.environ.get("SIMX_DBC_DIR")
    if not dbc_dir:
        raise SystemExit("Falta la variable de entorno SIMX_DBC_DIR (directorio con las DBCs del servidor)")
    auras = spell_hit_auras(pathlib.Path(dbc_dir))
    reference = load_reference()

    # clase -> [(árbol, índice en la cadena, fila, columna, stat, [% por rango])]
    hit_talents = {}
    for class_id, game_class in CLASS_ID_TO_GAME_CLASS.items():
        for tree in range(3):
            for index, talent in enumerate(tree_talents(reference, class_id, tree)):
                by_stat = {}
                for rank in talent["ranks"]:
                    for stat, value in auras.get(rank["spell_id"], {}).items():
                        by_stat.setdefault(stat, []).append(value)
                for stat, values in by_stat.items():
                    hit_talents.setdefault(game_class, []).append(
                        (tree, index, talent["row"], talent["column"], stat, values, talent["name"]))

    talent_sets = {}
    for spec_file in BUILDS_DIR.glob("*.json"):
        data = load_json(spec_file)
        talent_sets[data["spec"]] = {t["const_name"]: t["talents_string"] for t in data["talent_sets"]}

    presets = {}
    for spec, (game_class, _role, _label) in SPEC_INFO.items():
        sims_dir = SIMS_DIR / spec
        if not sims_dir.exists():
            continue
        builds = builds_by_build_id(spec)
        for sim_file in sims_dir.glob("*.json"):
            build_id = load_json(sim_file).get("build_id")
            build = builds.get(build_id)
            if not build:
                continue
            trees = talent_sets.get(spec, {}).get(build["talent_set"], "").split("-")
            totals = {}
            for tree, index, _row, _col, stat, values, _name in hit_talents.get(game_class, []):
                digits = trees[tree] if tree < len(trees) else ""
                rank = int(digits[index]) if index < len(digits) else 0
                if rank:
                    totals[stat] = totals.get(stat, 0) + values[rank - 1] * RATING_PER_PCT[stat]
            presets[f"{spec}_{build_id}"] = totals

    lines = ["-- Generado por Tools/generar_golpe_talentos.py desde Spell.dbc y los presets de wowsims.",
             "SimulateX_GolpeTalentos = {", "  talentos = {"]
    for game_class in sorted(hit_talents):
        lines.append(f"    {CLASS_FILE[game_class]} = {{")
        for tree, _index, row, col, stat, values, name in hit_talents[game_class]:
            ratings = ", ".join(str(round(v * RATING_PER_PCT[stat], 1)) for v in values)
            lines.append(f'      {{ tab = {tree + 1}, tier = {row + 1}, col = {col + 1}, stat = "{stat}", '
                         f'rating = {{ {ratings} }} }},  -- {name}')
        lines.append("    },")
    lines += ["  },", "  presets = {"]
    for key in sorted(presets):
        stats = ", ".join(f"{stat} = {round(v, 1)}" for stat, v in sorted(presets[key].items()))
        lines.append(f'    ["{key}"] = {{ {stats} }},')
    lines += ["  },", "}"]
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"-> {OUT_PATH} ({sum(len(v) for v in hit_talents.values())} talentos, {len(presets)} builds)")


if __name__ == "__main__":
    main()
