"""Genera el sub-addon SimulateX_Origenes (lista de la compra): de dónde
sale cada objeto equipable (calidad poco común o mejor), con nombres esES.

Orígenes que se incluyen:
- Botín de jefes (rank 3 o crédito de instance_encounters), de criaturas de
  mazmorra/banda y de raros del mundo (rank 2 y 4). El resto de criaturas
  del mundo se ignora.
- Cofres (gameobject tipo 3) que no aparecen solo en los continentes.
- Vendedores con spawn, con coste en oro, honor, arena u objetos
  (ItemExtendedCost.dbc).
- Recompensas de misión que alguien puede empezar y que no están desactivadas.
- Profesiones: hechizo que crea el objeto (Spell.dbc), aprendido de instructor
  o de una receta que a su vez tenga origen (o salga de algún botín de mundo).
- Bolsas (item_loot_template) con origen propio que contienen el objeto.

Las referencias de botín sin ningún objeto BoP y compartidas por más de
WORLD_POOL_MIN_USES fuentes son los botines de mundo al azar (BoE): se
descartan, esos objetos se compran en la subasta.

Probabilidad aproximada según las reglas de LootTemplate del core: una tirada
por fila sin grupo, un objeto por grupo (las filas con Chance 0 se reparten
lo que dejan las explícitas) y MaxCount procesados por referencia.

Requiere SIMX_DB_* (solo lectura) y SIMX_DBC_DIR.
"""

import collections
import os
import pathlib
import struct
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from extraer_objetos_bd import run_query
from rutas_addon import ADDON_ROOT, VERSION

OUT_DIR = ADDON_ROOT / "SimulateX_Origenes"
OUT_PATH = OUT_DIR / "Data" / "SimulateX_Origenes.lua"
TOC_PATH = OUT_DIR / "SimulateX_Origenes.toc"

WORLD_POOL_MIN_USES = 5
MIN_CHANCE_PCT = 0.1
MAX_VENDORS_PER_ITEM = 3
# Por debajo, la bolsa es de contenido al azar (decenas de objetos a ~1 %)
MIN_BAG_CHANCE_PCT = 5
# Más criaturas que esto soltando lo mismo en un mapa y dificultad: una sola
# entrada "varias criaturas" en vez de la lista.
MAX_TRASH_SOURCES = 3

# Camisa, bolsa, tabardo, munición y carcaj: no se comparan.
NOT_COMPARABLE_INVTYPES = {0, 4, 18, 19, 24, 27}
CONTINENT_MAPS = {0, 1, 530, 571}
ALLIANCE_RACES = 1 | 4 | 8 | 64 | 1024
HORDE_RACES = 2 | 16 | 32 | 128 | 512
# Flags2 de item_template (ITEM_FLAG2_FACTION_HORDE / _ALLIANCE)
ITEM_FLAG2_HORDE, ITEM_FLAG2_ALLIANCE, ITEM_FLAG2_DONT_IGNORE_BUY_PRICE = 1, 2, 4
# FactionTemplate.dbc: máscaras de grupo de facción
FACTION_MASK_ALLIANCE, FACTION_MASK_HORDE = 2, 4
FACTION_ALLIANCE_ID, FACTION_HORDE_ID = 469, 67

TOC_TEMPLATE = """## Interface: 30300
## Title: SimulateX (orígenes de objetos)
## Notes: Dónde conseguir cada objeto, para la lista de la compra de SimulateX. Se carga al abrir la pestaña Mejoras.
## Author: WarCrafted
## Version: {version}
## Dependencies: SimulateX
## LoadOnDemand: 1

Data\\SimulateX_Origenes.lua
"""


def read_wdbc(path: pathlib.Path) -> dict:
    data = path.read_bytes()
    sig, n_records, n_fields, record_size, _ = struct.unpack("<4s4I", data[:20])
    if sig != b"WDBC" or record_size != n_fields * 4:
        raise ValueError(f"{path.name}: formato WDBC inesperado")
    return {
        row[0]: row
        for row in (struct.unpack(f"<{n_fields}i", data[20 + i * record_size:20 + (i + 1) * record_size])
                    for i in range(n_records))
    }


def ints(rows: list, *keys) -> list:
    return [tuple(int(r[k]) for k in keys) for r in rows]


# ---------------------------------------------------------------- botín

class Loot:
    """wanted: objetos cuyo botín interesa; equip: los que cuentan para decidir
    si una referencia es un botín de mundo (sin nada BoP)."""

    def __init__(self, wanted: dict, equip: dict):
        self.wanted = wanted
        self.equip = equip
        self.refs = self._load("reference_loot_template")
        self.ref_uses = collections.Counter()
        for table in ("creature_loot_template", "gameobject_loot_template", "reference_loot_template"):
            for ref, _entry in ints(run_query(f"SELECT Reference, Entry FROM {table} WHERE Reference > 0 "
                                              f"GROUP BY Reference, Entry"), "Reference", "Entry"):
                self.ref_uses[ref] += 1
        self._memo = {}

    @staticmethod
    def _load(table: str) -> dict:
        rows = run_query(f"SELECT Entry, Item, Reference, Chance, QuestRequired, GroupId, MaxCount FROM {table}")
        by_entry = collections.defaultdict(list)
        for r in rows:
            by_entry[int(r["Entry"])].append((
                int(r["Item"]), int(r["Reference"]), float(r["Chance"]),
                r["QuestRequired"] not in ("0", ""), int(r["GroupId"]), max(1, int(r["MaxCount"]))))
        return by_entry

    def is_world_pool(self, ref: int) -> bool:
        has_bop = any(self.equip.get(item, {}).get("bop") for item, sub, *_ in self.refs.get(ref, ()) if not sub)
        return not has_bop and self.ref_uses[ref] >= WORLD_POOL_MIN_USES

    def ref_dist(self, ref: int, stack=()) -> dict:
        if ref in self._memo:
            return self._memo[ref]
        if ref in stack or self.is_world_pool(ref):
            return {}
        dist = self.template_dist(self.refs.get(ref, []), stack + (ref,))
        self._memo[ref] = dist
        return dist

    def template_dist(self, rows: list, stack=()) -> dict:
        """objeto equipable -> probabilidad de que salga al menos uno."""
        miss = collections.defaultdict(lambda: 1.0)

        def add(item_or_ref, is_ref, p, times):
            if p <= 0:
                return
            if not is_ref:
                if item_or_ref in self.wanted:
                    miss[item_or_ref] *= 1 - min(1.0, p)
                return
            for item, sub_p in self.ref_dist(item_or_ref, stack).items():
                miss[item] *= (1 - min(1.0, p) * sub_p) ** times

        groups = collections.defaultdict(list)
        for row in rows:
            item, ref, chance, quest, group, max_count = row
            if quest:
                continue
            if group == 0:
                add(ref or item, bool(ref), (100.0 if ref and chance == 0 else abs(chance)) / 100, max_count if ref else 1)
            else:
                groups[group].append(row)
        for group_rows in groups.values():
            explicit = sum(abs(r[2]) for r in group_rows if r[2])
            zero = [r for r in group_rows if not r[2]]
            share = max(0.0, 100 - explicit) / len(zero) if zero else 0
            for item, ref, chance, _q, _g, max_count in group_rows:
                add(ref or item, bool(ref), (abs(chance) or share) / 100, max_count if ref else 1)
        return {item: 1 - m for item, m in miss.items() if 1 - m > 0}


# ---------------------------------------------------------------- mapas y facciones

def difficulty_labels(dbc_dir: pathlib.Path) -> tuple:
    """(mapa -> tipo de instancia, (mapa, dificultad) -> etiqueta).
    Etiquetas: "N"/"H" en mazmorras con modo heroico, "10"/"25"/"10H"/"25H"
    en bandas con varios modos; "" si el mapa tiene un solo modo."""
    map_type = {map_id: row[2] for map_id, row in read_wdbc(dbc_dir / "Map.dbc").items()}
    modes = collections.defaultdict(dict)
    for row in read_wdbc(dbc_dir / "MapDifficulty.dbc").values():
        modes[row[1]][row[2]] = row[21]
    labels = {}
    for map_id, by_diff in modes.items():
        if len(by_diff) < 2:
            continue
        for diff, players in by_diff.items():
            if map_type.get(map_id) == 2:
                labels[(map_id, diff)] = f"{players}{'H' if diff >= 2 else ''}"
            else:
                labels[(map_id, diff)] = "H" if diff >= 1 else "N"
    return map_type, labels


def faction_of_template(dbc_dir: pathlib.Path) -> dict:
    """FactionTemplate id -> 0 ambas, 1 Alianza, 2 Horda (según con quién es
    amistoso u hostil el PNJ)."""
    result = {}
    for tid, row in read_wdbc(dbc_dir / "FactionTemplate.dbc").items():
        friend, hostile = row[4] | row[3], row[5]
        enemies, friends = set(row[6:10]), set(row[10:14])
        ally = friend & FACTION_MASK_ALLIANCE or FACTION_ALLIANCE_ID in friends
        horde = friend & FACTION_MASK_HORDE or FACTION_HORDE_ID in friends
        ally_hostile = hostile & FACTION_MASK_ALLIANCE or FACTION_ALLIANCE_ID in enemies
        horde_hostile = hostile & FACTION_MASK_HORDE or FACTION_HORDE_ID in enemies
        if (ally and not horde) or (horde_hostile and not ally_hostile):
            result[tid] = 1
        elif (horde and not ally) or (ally_hostile and not horde_hostile):
            result[tid] = 2
        else:
            result[tid] = 0
    return result


def race_faction(mask: int) -> int:
    if mask <= 0:
        return 0
    ally, horde = mask & ALLIANCE_RACES, mask & HORDE_RACES
    if ally and not horde:
        return 1
    if horde and not ally:
        return 2
    return 0


def present(text: str) -> bool:
    """mysql --batch escribe NULL como texto."""
    return bool(text) and text != "NULL"


def pct(p: float) -> str:
    value = round(p * 100, 1)
    return str(int(value)) if value == int(value) else str(value)


# ---------------------------------------------------------------- profesiones

# Profesiones que fabrican equipo (SkillLine.dbc)
CRAFT_SKILLS = {164, 165, 197, 202, 755, 773}
SPELL_EFFECT_CREATE_ITEM = 24
RECIPE_LEARN_SPELL = 483
MAX_RECIPES_PER_ITEM = 2

# Spell.dbc (DBCStructure.h::SpellEntry): Effect 71-73, EffectItemType
# 107-109, SpellName 136 (enUS)
SPELL_EFFECT_FIELD, SPELL_ITEM_FIELD, SPELL_NAME_FIELD = 71, 107, 136


def read_spells(dbc_dir: pathlib.Path) -> tuple:
    """(hechizo -> objeto que crea, hechizo -> nombre enUS)."""
    data = (dbc_dir / "Spell.dbc").read_bytes()
    _, n_records, n_fields, record_size, _ = struct.unpack("<4s4I", data[:20])
    strings = data[20 + n_records * record_size:]
    creates, spell_names = {}, {}
    for i in range(n_records):
        base = 20 + i * record_size
        spell = struct.unpack_from("<i", data, base)[0]
        effects = struct.unpack_from("<3i", data, base + SPELL_EFFECT_FIELD * 4)
        items = struct.unpack_from("<3i", data, base + SPELL_ITEM_FIELD * 4)
        for effect, item in zip(effects, items):
            if effect == SPELL_EFFECT_CREATE_ITEM and item:
                creates[spell] = item
        name_offset = struct.unpack_from("<i", data, base + SPELL_NAME_FIELD * 4)[0]
        if 0 < name_offset < len(strings):
            spell_names[spell] = strings[name_offset:strings.index(b"\0", name_offset)].decode("utf-8", "replace")
    return creates, spell_names


def read_skill_names(dbc_dir: pathlib.Path) -> dict:
    data = (dbc_dir / "SkillLine.dbc").read_bytes()
    _, n_records, n_fields, record_size, _ = struct.unpack("<4s4I", data[:20])
    strings = data[20 + n_records * record_size:]
    names = {}
    for i in range(n_records):
        row = struct.unpack_from(f"<{n_fields}i", data, 20 + i * record_size)
        offset = row[3]  # DisplayName enUS
        if 0 < offset < len(strings):
            names[row[0]] = strings[offset:strings.index(b"\0", offset)].decode("utf-8", "replace")
    return names


def profession_spells(sla: dict, spell_names: dict, skill_names: dict, skills: set) -> dict:
    """skillLine -> hechizo de la profesión (el de la línea con el mismo
    nombre), para que el addon saque el nombre traducido con GetSpellInfo."""
    result = {}
    for spell, (skill, _rank) in sorted(sla.items()):
        if skill in skills and skill not in result and spell_names.get(spell) == skill_names.get(skill):
            result[skill] = spell
    return result


# ---------------------------------------------------------------- main

def item_attributes(r: dict) -> dict:
    flags2 = int(r["FlagsExtra"])
    faction = race_faction(int(r["AllowableRace"]))
    if flags2 & ITEM_FLAG2_HORDE:
        faction = 2
    elif flags2 & ITEM_FLAG2_ALLIANCE:
        faction = 1
    return {
        "name": r["name"], "q": int(r["Quality"]), "inv": int(r["InventoryType"]),
        "req": int(r["RequiredLevel"]), "bop": r["bonding"] == "1", "faction": faction,
        "price": int(r["BuyPrice"]), "gold_with_ext": bool(flags2 & ITEM_FLAG2_DONT_IGNORE_BUY_PRICE),
        "skill": int(r["RequiredSkill"]),
    }


ITEM_COLUMNS = ("entry, name, Quality, InventoryType, RequiredLevel, bonding, AllowableRace, FlagsExtra, "
                "BuyPrice, RequiredSkill")


def main() -> None:
    dbc_dir = os.environ.get("SIMX_DBC_DIR")
    if not dbc_dir:
        raise SystemExit("Falta la variable de entorno SIMX_DBC_DIR (directorio con las DBCs del servidor)")
    dbc_dir = pathlib.Path(dbc_dir)

    equip = {}
    for r in run_query(f"SELECT {ITEM_COLUMNS} FROM item_template WHERE class IN (2, 4) AND Quality BETWEEN 2 AND 5"):
        if int(r["InventoryType"]) not in NOT_COMPARABLE_INVTYPES:
            equip[int(r["entry"])] = item_attributes(r)

    # Intermediarios: recetas que enseñan a fabricar equipo y bolsas con equipo
    # dentro. Se buscan sus orígenes igual que los del equipo.
    creates, spell_names = read_spells(dbc_dir)
    sla = {}
    for row in read_wdbc(dbc_dir / "SkillLineAbility.dbc").values():
        sla.setdefault(row[2], (row[1], row[7]))
    recipes_by_spell = collections.defaultdict(list)
    intermediates = {}
    for r in run_query(f"SELECT {ITEM_COLUMNS}, spellid_2, RequiredSkillRank FROM item_template "
                       f"WHERE class = 9 AND spellid_1 = {RECIPE_LEARN_SPELL} AND spellid_2 > 0"):
        spell = int(r["spellid_2"])
        if creates.get(spell) in equip:
            recipe = int(r["entry"])
            intermediates[recipe] = item_attributes(r)
            recipes_by_spell[spell].append((recipe, int(r["RequiredSkillRank"])))
    item_loot = Loot._load("item_loot_template")
    containers = [c for c, rows in item_loot.items() if any(row[0] in equip for row in rows)]
    if containers:
        for r in run_query(f"SELECT {ITEM_COLUMNS} FROM item_template WHERE entry IN ({','.join(map(str, containers))})"):
            intermediates[int(r["entry"])] = item_attributes(r)
    wanted = {**equip, **intermediates}

    map_type, diff_label = difficulty_labels(dbc_dir)
    instance_maps = {m for m, t in map_type.items() if t in (1, 2)}
    instance_maps |= {int(r["map"]) for r in run_query("SELECT map FROM instance_template")}

    creatures = {int(r["entry"]): r for r in run_query(
        "SELECT entry, name, `rank`, lootid, faction, difficulty_entry_1, difficulty_entry_2, difficulty_entry_3 "
        "FROM creature_template")}
    base_of = {}
    for entry, r in creatures.items():
        for idx in (1, 2, 3):
            diff_entry = int(r[f"difficulty_entry_{idx}"])
            if diff_entry:
                base_of[diff_entry] = (entry, idx)
    spawn_maps = collections.defaultdict(set)
    for npc, map_id in ints(run_query("SELECT DISTINCT id, map FROM creature"), "id", "map"):
        spawn_maps[npc].add(map_id)
    encounters = read_wdbc(dbc_dir / "DungeonEncounter.dbc")
    boss_map = {}
    for credit, enc in ints(run_query("SELECT creditEntry, entry FROM instance_encounters WHERE creditType = 0"),
                            "creditEntry", "entry"):
        credit = base_of.get(credit, (credit, 0))[0]
        if enc in encounters:
            boss_map.setdefault(credit, encounters[enc][1])

    loot = Loot(wanted, equip)
    origins = collections.defaultdict(list)  # objeto -> [(tipo, campos...)]
    names = {"criaturas": {}, "cofres": {}, "misiones": {}}

    # Botín de criaturas
    by_lootid = collections.defaultdict(list)
    for entry, r in creatures.items():
        if int(r["lootid"]):
            by_lootid[int(r["lootid"])].append(entry)
    creature_loot = Loot._load("creature_loot_template")
    trash = collections.defaultdict(lambda: collections.defaultdict(dict))  # objeto -> (mapa, dif) -> pnj -> p
    for loot_id, rows in creature_loot.items():
        dist = None
        for entry in by_lootid.get(loot_id, ()):
            base, idx = base_of.get(entry, (entry, 0))
            info = creatures.get(base)
            if not info:
                continue
            rank = int(info["rank"])
            maps = spawn_maps.get(base, set())
            inst_maps = sorted(maps & instance_maps)
            is_boss = rank == 3 or base in boss_map
            map_id = inst_maps[0] if inst_maps else boss_map.get(base, min(maps) if maps else 0)
            in_instance = map_id in instance_maps
            if not (is_boss or in_instance or rank in (2, 4)):
                continue
            if dist is None:
                dist = loot.template_dist(rows)
            label = diff_label.get((map_id, idx), "") if in_instance else ""
            for item, p in dist.items():
                if p * 100 < MIN_CHANCE_PCT:
                    continue
                if is_boss:
                    origins[item].append(("j", base, map_id, label, p))
                elif in_instance:
                    trash[item][(map_id, label)][base] = max(p, trash[item][(map_id, label)].get(base, 0))
                else:
                    origins[item].append(("r", base, map_id, p))
                names["criaturas"][base] = None
    for item, by_place in trash.items():
        for (map_id, label), npcs in by_place.items():
            if len(npcs) > MAX_TRASH_SOURCES:
                origins[item].append(("m", 0, map_id, label, max(npcs.values()), len(npcs)))
            else:
                for npc, p in npcs.items():
                    origins[item].append(("m", npc, map_id, label, p))

    # Cofres
    go_loot = Loot._load("gameobject_loot_template")
    go_spawns = collections.defaultdict(list)
    for go, map_id, mask in ints(run_query("SELECT id, map, spawnMask FROM gameobject"), "id", "map", "spawnMask"):
        go_spawns[go].append((map_id, mask))
    for r in run_query("SELECT entry, name, Data1 FROM gameobject_template WHERE type = 3 AND Data1 > 0"):
        go, loot_id = int(r["entry"]), int(r["Data1"])
        spawns = go_spawns.get(go, [])
        if spawns and all(m in CONTINENT_MAPS for m, _ in spawns):
            continue
        dist = loot.template_dist(go_loot.get(loot_id, []))
        # Sin nada BoP es un cofre de botín al azar (BoE), no el de un jefe
        if not any(equip[item]["bop"] for item in dist if item in equip):
            continue
        map_id, label = 0, ""
        if spawns:
            map_id, mask = spawns[0]
            if len({m for m, _ in spawns}) == 1 and mask and mask & (mask - 1) == 0:
                label = diff_label.get((map_id, mask.bit_length() - 1), "")
        for item, p in dist.items():
            if p * 100 >= MIN_CHANCE_PCT:
                origins[item].append(("c", go, map_id, label, p))
                names["cofres"][go] = r["name"]

    # Vendedores
    ext_costs = read_wdbc(dbc_dir / "ItemExtendedCost.dbc")
    npc_faction = faction_of_template(dbc_dir)
    vendors = collections.defaultdict(list)
    for npc, item, ext in ints(run_query("SELECT DISTINCT entry, item, ExtendedCost FROM npc_vendor WHERE item > 0"),
                               "entry", "item", "ExtendedCost"):
        if item not in wanted or npc not in spawn_maps or npc not in creatures:
            continue
        honor = arena = rating = 0
        currencies = []
        if ext and ext in ext_costs:
            row = ext_costs[ext]
            honor, arena, rating = row[1], row[2], row[14]
            currencies = [(row[4 + k], row[9 + k]) for k in range(5) if row[4 + k]]
        faction = npc_faction.get(int(creatures[npc]["faction"]), 0)
        # CreatureData.h, VendorItem::IsGoldRequired
        copper = wanted[item]["price"] if not ext or wanted[item]["gold_with_ext"] else 0
        vendors[item].append(("v", npc, faction, copper, honor, arena, rating, currencies))
    currency_items = set()
    for item, entries in vendors.items():
        # Mismo coste y facción: basta un vendedor
        entries.sort(key=lambda v: v[1])
        picked, seen = [], set()
        for v in entries:
            key = (v[2], v[3:7], tuple(v[7]))
            if key not in seen:
                picked.append(v)
                seen.add(key)
        for v in picked[:MAX_VENDORS_PER_ITEM]:
            origins[item].append(v)
            names["criaturas"][v[1]] = None
            currency_items.update(c for c, _ in v[7])

    # Misiones
    startable = {q for (q,) in ints(run_query(
        "SELECT quest FROM creature_queststarter UNION SELECT quest FROM gameobject_queststarter "
        "UNION SELECT startquest AS quest FROM item_template WHERE startquest > 0"), "quest")}
    disabled = {q for (q,) in ints(run_query("SELECT entry FROM disables WHERE sourceType = 1"), "entry")}
    reward_cols = [f"RewardItem{i}" for i in range(1, 5)] + [f"RewardChoiceItemID{i}" for i in range(1, 7)]
    for r in run_query(f"SELECT ID, LogTitle, QuestLevel, MinLevel, AllowableRaces, {', '.join(reward_cols)} "
                       f"FROM quest_template"):
        quest = int(r["ID"])
        if quest not in startable or quest in disabled:
            continue
        level = int(r["QuestLevel"]) if int(r["QuestLevel"]) > 0 else int(r["MinLevel"])
        faction = race_faction(int(r["AllowableRaces"]))
        for col in reward_cols:
            item = int(r[col])
            if item in wanted:
                origins[item].append(("q", quest, level, faction))
                names["misiones"][quest] = r["LogTitle"]

    # Recetas que no salen de ningún sitio concreto pero sí de algún botín:
    # botín de mundo al azar, se compran en la subasta
    anywhere = {row[0] for table in (creature_loot, go_loot, loot.refs, item_loot)
                for rows in table.values() for row in rows if not row[1]}
    for recipe in intermediates:
        if not origins.get(recipe) and recipe in anywhere:
            origins[recipe].append(("w",))

    # Bolsas: el objeto sale de una bolsa que a su vez tiene orígenes
    for container, rows in item_loot.items():
        if not origins.get(container):
            continue
        for item, p in loot.template_dist(rows).items():
            if item in equip and p * 100 >= MIN_BAG_CHANCE_PCT:
                origins[item].append(("b", container, p))

    # Profesiones: instructor, o receta con algún origen
    trainer_rank = {spell: rank for spell, rank in ints(run_query(
        f"SELECT SpellId, MIN(ReqSkillRank) AS req FROM trainer_spell "
        f"WHERE ReqSkillLine IN ({','.join(map(str, CRAFT_SKILLS))}) GROUP BY SpellId"), "SpellId", "req")}
    crafted = collections.defaultdict(dict)  # objeto -> (skill, receta|t) -> rango
    for spell, item in creates.items():
        skill = sla.get(spell, (0, 0))[0]
        if item not in equip or skill not in CRAFT_SKILLS:
            continue
        if spell in trainer_rank:
            crafted[item][(skill, "t")] = trainer_rank[spell]
        known_recipes = [(r, rank) for r, rank in recipes_by_spell.get(spell, ()) if origins.get(r)]
        for recipe, rank in sorted(known_recipes, key=lambda x: x[1])[:MAX_RECIPES_PER_ITEM]:
            crafted[item][(skill, recipe)] = rank
    for item, sources in crafted.items():
        for (skill, source), rank in sorted(sources.items(), key=lambda kv: kv[1]):
            origins[item].append(("p", skill, rank, source))

    skill_names = read_skill_names(dbc_dir)
    used_skills = CRAFT_SKILLS | {e["skill"] for e in equip.values() if e["skill"]}
    professions = profession_spells(sla, spell_names, skill_names, used_skills)

    # Nombres esES (inglés si falta la traducción)
    for r in run_query("SELECT entry, Name FROM creature_template_locale WHERE locale = 'esES'"):
        if int(r["entry"]) in names["criaturas"] and present(r["Name"]):
            names["criaturas"][int(r["entry"])] = r["Name"]
    for npc, name in names["criaturas"].items():
        if not name:
            names["criaturas"][npc] = creatures[npc]["name"]
    for r in run_query("SELECT entry, name FROM gameobject_template_locale WHERE locale = 'esES'"):
        if int(r["entry"]) in names["cofres"] and present(r["name"]):
            names["cofres"][int(r["entry"])] = r["name"]
    for r in run_query("SELECT ID, Title FROM quest_template_locale WHERE locale = 'esES'"):
        if int(r["ID"]) in names["misiones"] and present(r["Title"]):
            names["misiones"][int(r["ID"])] = r["Title"]

    equip_origins = {item: origins[item] for item in equip if origins.get(item)}
    used_intermediates = {source for sources in equip_origins.values() for o in sources
                          for source in ((o[1],) if o[0] == "b" else (o[3],) if o[0] == "p" and o[3] != "t" else ())}
    intermediate_origins = {item: origins[item] for item in used_intermediates}
    item_names = {item: wanted[item]["name"] for item in (*equip_origins, *intermediate_origins)}
    if currency_items:
        for r in run_query(f"SELECT entry, name FROM item_template WHERE entry IN ({','.join(map(str, currency_items))})"):
            item_names[int(r["entry"])] = r["name"]
    for r in run_query("SELECT ID, Name FROM item_template_locale WHERE locale = 'esES'"):
        if int(r["ID"]) in item_names and present(r["Name"]):
            item_names[int(r["ID"])] = r["Name"]

    write_lua(equip_origins, intermediate_origins, equip, names, item_names, professions)
    TOC_PATH.write_text(TOC_TEMPLATE.format(version=VERSION), encoding="utf-8")
    kinds = collections.Counter(o[0] for sources in equip_origins.values() for o in sources)
    print(f"-> {OUT_PATH} ({len(equip_origins)} objetos, {len(intermediate_origins)} recetas y bolsas; "
          f"orígenes: {dict(kinds)}; {OUT_PATH.stat().st_size // 1024} KB)")


def encode(origin: tuple) -> str:
    kind = origin[0]
    if kind in ("j", "c"):
        _, ident, map_id, label, p = origin
        return f"{kind}{ident}:{map_id}:{label}:{pct(p)}"
    if kind == "m":
        extra = f":{origin[5]}" if len(origin) > 5 else ""
        return f"m{origin[1]}:{origin[2]}:{origin[3]}:{pct(origin[4])}{extra}"
    if kind == "r":
        return f"r{origin[1]}:{origin[2]}:{pct(origin[3])}"
    if kind == "v":
        _, npc, faction, copper, honor, arena, rating, currencies = origin
        items = "+".join(f"{c}x{n}" for c, n in currencies)
        return f"v{npc}:{faction}:{copper}:{honor}:{arena}:{rating}:{items}"
    if kind == "b":
        return f"b{origin[1]}:{pct(origin[2])}"
    if kind == "p":
        return f"p{origin[1]}:{origin[2]}:{origin[3]}"
    if kind == "w":
        return "w"
    _, quest, level, faction = origin
    return f"q{quest}:{level}:{faction}"


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_lua(origins: dict, intermediates: dict, equip: dict, names: dict, item_names: dict,
              professions: dict) -> None:
    lines = ["-- Generado por Tools/generar_origenes.py desde acore_world y las DBC del servidor.",
             "-- id = \"nivel,inventario,calidad,facción,profesión para llevarlo|origen;origen...\"",
             "SimulateX_Origenes = {"]
    for item in sorted(origins):
        e = equip[item]
        sources = ";".join(encode(o) for o in origins[item])
        lines.append(f'[{item}]="{e["req"]},{e["inv"]},{e["q"]},{e["faction"]},{e["skill"]}|{sources}",')
    lines.append("}")
    lines.append("-- Recetas y bolsas de las que sale equipo: id = \"origen;origen...\"")
    lines.append("SimulateX_OrigenesIntermedios = {")
    for item in sorted(intermediates):
        lines.append(f'[{item}]="{";".join(encode(o) for o in intermediates[item])}",')
    lines.append("}")
    lines.append("SimulateX_OrigenesNombres = {")
    for key, table in (("objetos", item_names), *names.items()):
        lines.append(f"  {key} = {{")
        for ident in sorted(table):
            lines.append(f"    [{ident}]={lua_str(table[ident])},")
        lines.append("  },")
    lines.append("}")
    lines.append("-- Línea de habilidad -> hechizo de la profesión (nombre traducido con GetSpellInfo)")
    lines.append("SimulateX_OrigenesProfesiones = {")
    lines.append("  " + ", ".join(f"[{skill}]={spell}" for skill, spell in sorted(professions.items())))
    lines.append("}")
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
