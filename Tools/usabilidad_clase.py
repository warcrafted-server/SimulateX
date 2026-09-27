"""Tabla de usabilidad por clase para el catálogo de nivel 80 (paso 2 del plan
datos-completos-v0.4): qué subclases de armadura/arma de item_template puede
llevar realmente cada clase, más allá de lo que impide el propio juego (que no
bloquea equiparse un tipo de armadura ajeno, solo penaliza su rendimiento).

class=2 (armas): subclass 0/1 hacha 1M/2M, 2 arco, 3 arma de fuego, 4/5 maza
1M/2M, 6 asta, 7/8 espada 1M/2M, 10 bastón, 13 puño, 15 daga, 16 arrojadiza,
18 ballesta, 19 varita.
class=4 (armadura): subclass 0 varios (anillos/cuellos/abalorios/objetos de
mano izquierda "sostener", sin restricción de tipo), 1 tela, 2 cuero, 3 malla,
4 placas, 6 escudo, 7 tratado, 8 ídolo, 9 tótem, 10 sigilo.

En caso de duda se incluye: solo cuesta tiempo de simulación, nunca produce un
falso "no usable" en el addon.
"""

WEAPON_CLASS = 2
ARMOR_CLASS = 4

# subclass 0 (Misc): anillos, cuellos, abalorios y objetos de mano izquierda
# "sostener" (InventoryType 23) — sin restricción de tipo, valen para cualquier
# clase.
ARMOR_SUBCLASS_UNRESTRICTED = 0

# Las capas son subclass 1 (tela) en item_template aunque valen para cualquier
# clase (no dan la armadura de tela, solo su valor base + stats): filtrarlas
# por subclase excluiría casi todas para clases no-tela (plan, nota "Capas").
CLOAK_INVENTORY_TYPE = 16

USABILIDAD_POR_CLASE = {
    "Warrior":     {"armor": {4, 6}, "weapon": {0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18}},
    "Paladin":     {"armor": {4, 6, 7}, "weapon": {0, 1, 4, 5, 6, 7, 8}},
    "Hunter":      {"armor": {3}, "weapon": {0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18}},
    "Rogue":       {"armor": {2}, "weapon": {0, 2, 3, 4, 7, 13, 15, 16, 18}},
    "Priest":      {"armor": {1}, "weapon": {4, 10, 15, 19}},
    "Deathknight": {"armor": {4, 10}, "weapon": {0, 1, 4, 5, 6, 7, 8}},
    "Shaman":      {"armor": {3, 6, 9}, "weapon": {0, 1, 4, 5, 10, 13, 15}},
    "Mage":        {"armor": {1}, "weapon": {7, 10, 15, 19}},
    "Warlock":     {"armor": {1}, "weapon": {7, 10, 15, 19}},
    "Druid":       {"armor": {2, 8}, "weapon": {4, 5, 6, 10, 13, 15}},
}


def is_item_usable(game_class: str, item_class: int, item_subclass: int, inventory_type: int) -> bool:
    """True si la subclase del objeto es de un tipo que la clase puede llevar
    con su rendimiento completo. Objetos que no son armadura ni arma (joyas,
    reliquias) siempre se consideran usables aquí: su restricción real ya
    viene de AllowableClass o de la tabla de reliquias, no del tipo."""
    if item_class not in (WEAPON_CLASS, ARMOR_CLASS):
        return True

    allowed = USABILIDAD_POR_CLASE[game_class]
    if item_class == ARMOR_CLASS:
        if item_subclass == ARMOR_SUBCLASS_UNRESTRICTED or inventory_type == CLOAK_INVENTORY_TYPE:
            return True
        return item_subclass in allowed["armor"]

    return item_subclass in allowed["weapon"]
