"""Mapeo entre el índice Stat de wowsims/wotlk (proto/common.proto) y la clave
que GetItemStats(link, tabla) devuelve en la API de WoW 3.3.5a (constantes
ITEM_MOD_* globales del cliente).

SIN VERIFICAR EN EL CLIENTE REAL: STAT_TO_ITEM_MOD son los nombres estándar
documentados de la API WotLK, no confirmados contra un cliente 3.3.5a real.
El paso 6 del plan (`/simulatex debug` + link, con acceso al juego) es donde
se verifican de verdad y se corrige aquí cualquier nombre que no coincida
antes de usarlos en el addon.

Regla del paso 3 del plan: el crítico/golpe/celeridad "de objeto" (un único
rating en el ítem) alimenta el mismo stat de wowsims según el tipo de ataque
(melee/distancia/hechizo) — su peso final es la SUMA de los pesos de esos
stats en wowsims, no una elección entre ellos. Ver combine_rating_weight().
"""

# Stat de wowsims (índice del enum, ver proto/common.proto) -> clave única de
# GetItemStats. Solo estadísticas "primarias", con una correspondencia 1:1.
STAT_TO_ITEM_MOD = {
    0: "ITEM_MOD_STRENGTH_SHORT",
    1: "ITEM_MOD_AGILITY_SHORT",
    2: "ITEM_MOD_STAMINA_SHORT",
    3: "ITEM_MOD_INTELLECT_SHORT",
    4: "ITEM_MOD_SPIRIT_SHORT",
    5: "ITEM_MOD_SPELL_POWER_SHORT",
    6: "ITEM_MOD_MANA_REGENERATION_SHORT",  # mp5
    15: "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
    16: "ITEM_MOD_EXPERTISE_RATING_SHORT",
    11: "ITEM_MOD_ATTACK_POWER_SHORT",
    21: "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    22: "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
    23: "ITEM_MOD_BLOCK_RATING_SHORT",
    24: "ITEM_MOD_BLOCK_VALUE_SHORT",
    25: "ITEM_MOD_DODGE_RATING_SHORT",
    26: "ITEM_MOD_PARRY_RATING_SHORT",
    27: "ITEM_MOD_RESILIENCE_RATING_SHORT",
    20: "RESISTANCE0_NAME",  # armadura: no es un ITEM_MOD_*, viene de GetItemStats con esta clave
}

# Rating "de objeto" (una sola clave en GetItemStats) que alimenta varios Stat
# de wowsims a la vez según el tipo de ataque: el peso final de esa clave es
# la suma de los pesos de los Stat que existan para la spec (algunas specs no
# pesan spell, o no pesan ranged, etc.).
RATING_TO_STATS = {
    "ITEM_MOD_CRIT_RATING_SHORT": [13, 8],       # crítico: MeleeCrit + SpellCrit (ranged usa MeleeCrit en wowsims)
    "ITEM_MOD_HIT_RATING_SHORT": [12, 7],        # golpe: MeleeHit + SpellHit (ranged usa MeleeHit en wowsims)
    "ITEM_MOD_HASTE_RATING_SHORT": [14, 9],      # celeridad: MeleeHaste + SpellHaste (ranged usa MeleeHaste en wowsims)
}

# Constante de forms.go (druid/forms.go): PA feral por punto de DPS de arma
# por encima de este umbral. No es un Stat de wowsims (no existe
# FeralAttackPower en el proto): se calcula aparte y su EP es el de PA.
FERAL_AP_DPS_THRESHOLD = 54.8
FERAL_AP_PER_DPS = 14


def combine_rating_weight(weights_by_stat_index: dict, item_mod_key: str) -> float | None:
    """Peso EP de una clave de GetItemStats que es "un solo rating de objeto"
    pero alimenta varios Stat de wowsims (crítico/golpe/celeridad): suma los
    pesos de los Stat que la spec realmente pesa (weights_by_stat_index),
    ignorando los que no aplican a esa spec (peso 0 o ausente)."""
    stat_indices = RATING_TO_STATS.get(item_mod_key)
    if stat_indices is None:
        return None
    total = sum(weights_by_stat_index.get(i, 0.0) for i in stat_indices)
    return total if total else None


def feral_attack_power(dps_arma: float) -> float:
    """PA feral aportado por el DPS de un arma, fórmula exacta de
    druid/forms.go: fap = floor((dps - 54.8) * 14). Solo se aplica cuando el
    arma va en la mano principal de una build feral (cat/bear)."""
    import math
    return math.floor((dps_arma - FERAL_AP_DPS_THRESHOLD) * FERAL_AP_PER_DPS)


def gem_ep_value(gem_stats: list, weights_by_stat_index: dict) -> float:
    """Valor de hueco (EP) de una gema: producto escalar de su vector stats
    (assets/database/db.json, índice = índice del enum Stat) por los pesos
    brutos de la build (dps.weights.stats de TestGenStatWeights). No incluye
    pseudo-stats: ninguna gema aporta DPS de arma."""
    return sum(weights_by_stat_index.get(i, 0.0) * value for i, value in enumerate(gem_stats) if value)
