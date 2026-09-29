"""Genera Addon/SimulateX/Data/SimulateX_Gemas.lua: las gemas candidatas para
las gemas ideales, con sus estadísticas en claves ITEM_MOD_* (las de
build.weights). El addon elige la mejor de cada color con los pesos reales
del jugador, con golpe/pericia/penetración a 0 si ya está en el tope; los
valores fijos de build.gems (generar_db_addon.ideal_gems) usan los pesos del
preset y nunca eligen gemas de golpe si el preset va topado.

Mismo filtro que ideal_gems: sin meta, calidad rara o mejor, sin únicas ni
de joyero. No simula nada.
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from simular_builds import WOWSIMS_DB_PATH, META_GEM_COLOR, load_json
from mapeo_stats import STAT_TO_ITEM_MOD, RATING_TO_STATS
from rutas_addon import ADDON_ROOT

OUT_PATH = ADDON_ROOT / "SimulateX" / "Data" / "SimulateX_Gemas.lua"

# proto.GemColor -> máscara de colores de hueco que cumple (1 rojo, 2 amarillo, 4 azul)
COLOR_MASK = {2: 1, 3: 4, 4: 2, 5: 6, 6: 3, 7: 5, 8: 7}


def item_mod_stats(stats: list) -> dict:
    result = {}
    for index, key in STAT_TO_ITEM_MOD.items():
        if index < len(stats) and stats[index]:
            result[key] = stats[index]
    # un rating de gema alimenta a la vez el Stat cuerpo a cuerpo y el de hechizo
    for key, indices in RATING_TO_STATS.items():
        value = max((stats[i] for i in indices if i < len(stats)), default=0)
        if value:
            result[key] = value
    return result


def main() -> None:
    gems = set()
    for gem in load_json(WOWSIMS_DB_PATH).get("gems", []):
        if (gem["color"] == META_GEM_COLOR or gem.get("quality", 0) < 3
                or gem.get("unique") or gem.get("requiredProfession") or gem["color"] not in COLOR_MASK):
            continue
        stats = item_mod_stats(gem["stats"])
        if stats:
            gems.add((COLOR_MASK[gem["color"]], tuple(sorted(stats.items()))))
    lines = ["-- Generado por Tools/generar_gemas.py desde la base de datos de wowsims.",
             "-- m: colores que cumple (1 rojo, 2 amarillo, 4 azul); s: estadísticas",
             "SimulateX_Gemas = {"]
    for mask, stats in sorted(gems):
        parts = ", ".join(f"{key} = {value:g}" for key, value in stats)
        lines.append(f"  {{ m = {mask}, s = {{ {parts} }} }},")
    lines.append("}")
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"-> {OUT_PATH} ({len(gems)} gemas)")


if __name__ == "__main__":
    main()
