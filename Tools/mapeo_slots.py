"""Mapeo entre el campo inventorySlot de AoWoW (db.warcrafted.com, estándar
INVTYPE_* de la API de WoW) y el índice ItemSlot que usa wowsims/wotlk en sus
ficheros de gearset (proto.ItemSlot, orden fijo 0-16, ver
sim/core/proto/common.pb.go).

Referencia INVTYPE_* (estable en el juego desde siempre, no específica de esta
versión): https://wowpedia.fandom.com/wiki/ItemEquipLoc
"""

# inventorySlot (AoWoW) -> índice ItemSlot (wowsims). None = slot que wowsims
# no modela como pieza de equipo simulable (tabardo, forma, etc.) o que puede
# ir en más de un slot según el hueco libre (anillos/joyas/armas de una mano).
INVTYPE_TO_ITEM_SLOT = {
    1: 0,    # INVTYPE_HEAD -> ItemSlotHead
    2: 1,    # INVTYPE_NECK -> ItemSlotNeck
    3: 2,    # INVTYPE_SHOULDER -> ItemSlotShoulder
    4: 4,    # INVTYPE_BODY (camisa) -> sin slot simulable, wowsims no modela camisas
    5: 4,    # INVTYPE_CHEST -> ItemSlotChest
    6: 7,    # INVTYPE_WAIST -> ItemSlotWaist
    7: 8,    # INVTYPE_LEGS -> ItemSlotLegs
    8: 9,    # INVTYPE_FEET -> ItemSlotFeet
    9: 5,    # INVTYPE_WRISTS -> ItemSlotWrist
    10: 6,   # INVTYPE_HANDS -> ItemSlotHands
    11: None,  # INVTYPE_FINGER -> ambos anillos (10, 11), se decide por slot libre
    12: None,  # INVTYPE_TRINKET -> ambos trinkets (12, 13), idem
    13: None,  # INVTYPE_WEAPON (una mano, cualquier mano) -> MainHand u OffHand
    14: 15,  # INVTYPE_SHIELD -> ItemSlotOffHand
    15: 16,  # INVTYPE_RANGED (arcos/armas a distancia) -> ItemSlotRanged
    16: 3,   # INVTYPE_CLOAK -> ItemSlotBack
    17: 14,  # INVTYPE_2HWEAPON -> ItemSlotMainHand
    18: 4,   # INVTYPE_BAG -> no equipable como armadura, se ignora en la práctica
    19: 4,   # INVTYPE_TABARD -> sin slot simulable en wowsims
    20: 4,   # INVTYPE_ROBE (túnica) -> ItemSlotChest
    21: 14,  # INVTYPE_WEAPONMAINHAND -> ItemSlotMainHand
    22: 15,  # INVTYPE_WEAPONOFFHAND -> ItemSlotOffHand
    23: 15,  # INVTYPE_HOLDABLE (objeto de mano izquierda) -> ItemSlotOffHand
    24: None,  # INVTYPE_AMMO -> no es un "slot" de equipo en wowsims (se configura aparte)
    25: 16,  # INVTYPE_THROWN -> ItemSlotRanged
    26: 16,  # INVTYPE_RANGEDRIGHT (varitas) -> ItemSlotRanged
    28: None,  # INVTYPE_RELIC (libram/tótem/ídolo) -> ItemSlotRanged en wowsims
}

# Slots que pueden ocupar más de una posición física: se decide en tiempo de
# sustitución según cuál de las dos posiciones está libre/es más razonable.
AMBIGUOUS_SLOTS = {
    11: [10, 11],   # anillos
    12: [12, 13],   # trinkets
    13: [14, 15],   # arma de una mano: principal o secundaria
    28: [16],       # relic/libram/tótem -> wowsims lo trata como Ranged
}


def resolve_item_slot(inventory_slot_id: int, occupied_slots: set) -> int | None:
    """Devuelve el índice ItemSlot de wowsims para un inventorySlot de AoWoW,
    eligiendo entre posiciones ambiguas (anillo/trinket/arma) la primera que
    no esté ya usada por otro objeto candidato en la misma simulación."""
    if inventory_slot_id in AMBIGUOUS_SLOTS:
        for slot in AMBIGUOUS_SLOTS[inventory_slot_id]:
            if slot not in occupied_slots:
                return slot
        return AMBIGUOUS_SLOTS[inventory_slot_id][0]
    return INVTYPE_TO_ITEM_SLOT.get(inventory_slot_id)


def ambiguous_positions(inventory_slot_id: int) -> list[int]:
    """Todas las posiciones físicas donde puede ir un inventorySlot ambiguo
    (anillo/trinket/arma de una mano): probar el swap en cada una es necesario
    para comparar contra el objeto base correcto (un candidato puede coincidir
    con el objeto ya equipado en la SEGUNDA posición, no en la que resolve_item_slot
    elegiría por defecto)."""
    return AMBIGUOUS_SLOTS.get(inventory_slot_id, [])
