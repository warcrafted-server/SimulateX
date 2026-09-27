"""Parsea ui/<spec>/sim.ts (código fuente de wowsims/wotlk) para extraer, sin
transcribir a mano, qué estadísticas pesar (epStats/epPseudoStats) y contra
cuál referencia (epReferenceStat) usa cada spec para calcular EP — necesario
para generar TestGenStatWeights (paso 3 del plan datos-completos-v0.4).

Specs de la decisión 3 del plan (sanador sin rotación en wowsims:
restoration_druid, holy_paladin, y restoration_shaman si aplica) no se
simulan: se usa directamente epWeights, el preset de EP por defecto que trae
la propia spec en sim.ts (weightsKind = "preset" en el addon).
"""

import pathlib
import re

WOWSIMS_SRC = pathlib.Path(__file__).resolve().parent / "wowsimcli-src"
UI_DIR = WOWSIMS_SRC / "ui"

# Decisión 3 del plan datos-completos-v0.4: estas specs SÍ tienen epStats en
# sim.ts (wowsims calcula EP para su selector de gemas/gear), pero su rotación
# da 0 HPS en la simulación real (comprobado: 0 de 302 deltas ≠ 0 para
# restoration_druid). No se simulan: se usa epWeights (preset) siempre, aunque
# epStats exista.
SPECS_SIN_ROTACION = {"restoration_druid", "holy_paladin", "restoration_shaman"}

EP_STATS_RE = re.compile(r"epStats:\s*\[(.*?)\]", re.DOTALL)
EP_PSEUDO_STATS_RE = re.compile(r"epPseudoStats:\s*\[(.*?)\]", re.DOTALL)
EP_REFERENCE_STAT_RE = re.compile(r"epReferenceStat:\s*Stat\.(\w+)")
EP_WEIGHTS_RE = re.compile(r"epWeights:\s*Stats\.fromMap\(\{(.*?)\}\)", re.DOTALL)
STAT_ENTRY_RE = re.compile(r"Stat\.(\w+)")
PSEUDO_STAT_ENTRY_RE = re.compile(r"PseudoStat\.(\w+)")
EP_WEIGHT_PAIR_RE = re.compile(r"\[Stat\.(\w+)\]:\s*([\d.eE+-]+)")


def extract_ep_config(spec: str) -> dict:
    """Devuelve {stats_to_weigh, pseudo_stats_to_weigh, ep_reference_stat} (los
    nombres de constante Go tal como aparecen en el enum del proto, sin el
    prefijo Stat_/PseudoStat_) leídos de epStats/epPseudoStats/epReferenceStat,
    o {epWeights: {nombre_stat: peso}} si la spec no tiene epStats propio
    (decisión 3: sanadores sin rotación en wowsims, solo preset)."""
    sim_ts_path = UI_DIR / spec / "sim.ts"
    text = sim_ts_path.read_text(encoding="utf-8")

    ep_stats_match = None if spec in SPECS_SIN_ROTACION else EP_STATS_RE.search(text)
    if ep_stats_match:
        stats_to_weigh = STAT_ENTRY_RE.findall(ep_stats_match.group(1))
        pseudo_match = EP_PSEUDO_STATS_RE.search(text)
        pseudo_stats_to_weigh = PSEUDO_STAT_ENTRY_RE.findall(pseudo_match.group(1)) if pseudo_match else []
        ref_match = EP_REFERENCE_STAT_RE.search(text)
        if not ref_match:
            raise ValueError(f"{spec}: epStats presente pero sin epReferenceStat")
        return {
            "kind": "sim",
            "stats_to_weigh": stats_to_weigh,
            "pseudo_stats_to_weigh": pseudo_stats_to_weigh,
            "ep_reference_stat": ref_match.group(1),
        }

    weights_match = EP_WEIGHTS_RE.search(text)
    if weights_match:
        pairs = EP_WEIGHT_PAIR_RE.findall(weights_match.group(1))
        return {"kind": "preset", "ep_weights": {name: float(value) for name, value in pairs}}

    raise ValueError(f"{spec}: no se encontró epStats ni epWeights en {sim_ts_path}")


def main() -> None:
    import argparse
    import json

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec")
    args = parser.parse_args()

    print(json.dumps(extract_ep_config(args.spec), indent=2))


if __name__ == "__main__":
    main()
