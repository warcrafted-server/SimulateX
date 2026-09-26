"""Metadatos por spec necesarios para invocar su extractor Go generado
(Tools/generar_extractores_go.py): paquete Go, y cuántos niveles hay que subir
para llegar a ui/<spec>/ en rutas relativas (depende de si la spec vive en un
subpaquete anidado, ej. sim/druid/balance, o directo en sim/, ej. sim/hunter).
"""

SPEC_GO_PACKAGES = {
    "balance_druid": "druid/balance",
    "feral_druid": "druid/feral",
    "restoration_druid": "druid/restoration",
    "feral_tank_druid": "druid/tank",
    "holy_paladin": "paladin/holy",
    "protection_paladin": "paladin/protection",
    "retribution_paladin": "paladin/retribution",
    "healing_priest": "priest/healing",
    "shadow_priest": "priest/shadow",
    "smite_priest": "priest/smite",
    "elemental_shaman": "shaman/elemental",
    "enhancement_shaman": "shaman/enhancement",
    "restoration_shaman": "shaman/restoration",
    "hunter": "hunter",
    "mage": "mage",
    "rogue": "rogue",
    "warlock": "warlock",
    "warrior": "warrior/dps",
    "protection_warrior": "warrior/protection",
    "deathknight": "deathknight/dps",
    "tank_deathknight": "deathknight/tank",
}


def ui_relative_prefix(spec: str) -> str:
    depth = SPEC_GO_PACKAGES[spec].count("/") + 1  # sim/<pkg...> -> niveles hasta sim/
    return "../" * (depth + 1)  # +1 para subir también desde sim/ a la raíz del repo
