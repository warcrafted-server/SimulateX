"""v0.7 (Nivel 1): simula varias distribuciones de talentos para una spec con
el MISMO gear/APL (el best-in-slot ya elegido para esa build), y guarda el
dps/hps/tps/dtps de cada una en Data/talentos/<spec>.json.

No genera combinaciones nuevas de talentos: eso es un problema combinatorio
aparte (miles de simulaciones), fuera de alcance por ahora. Aquí solo se
compara un puñado de distribuciones ya definidas a mano en TALENT_VARIANTS,
reutilizando el mismo pipeline de Tools/simular_builds.py (SIMX_TALENTS ya
existe como override de entorno, ver generar_extractores_go.py).
"""

import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from simular_builds import (
    build_env, run_go_extractor, run_wowsimcli, extract_metrics, load_json, TOOLS_DIR, apl_suffix,
)
from validar_talentos import validate_build, CLASS_ID_TO_GAME_CLASS

GAME_CLASS_TO_CLASS_ID = {v: k for k, v in CLASS_ID_TO_GAME_CLASS.items()}

DATA_DIR = TOOLS_DIR.parent / "Data"
OUT_DIR = DATA_DIR / "talentos"
BUILDS_DIR = TOOLS_DIR / "builds"
MAPEO_DIR = BUILDS_DIR / "_mapeo"


def load_apl_file(spec: str, apl_const_name: str) -> str | None:
    """APL_ROTATION_DEFAULT -> "default" (nombre real del .apl.json), según
    builds/<spec>.json::apl_presets (mismo fichero que usa simular_builds.py
    para el lote de gear, ver su main())."""
    if not apl_const_name:
        return None
    data = load_json(BUILDS_DIR / f"{spec}.json")
    for preset in data["apl_presets"]:
        if preset["const_name"] == apl_const_name:
            return preset["apl_file"]
    return None

# Distribuciones a comparar por spec: (etiqueta, cadena de talentos wowhead
# 3.3.5a). "estandar" es siempre la StandardTalents de wowsims (la misma que
# usan las simulaciones de gear), para que la comparación tenga una build de
# referencia validada.
# Cada cadena se valida con validar_talentos.py contra
# Tools/talentos_referencia/talents_wotlk_335_esES.json (Talent.dbc/
# TalentTab.dbc reales del servidor, no deducidas del código del motor ni de
# una web que no se pudo leer). CLASS_ID por clase en validar_talentos.py.
TALENT_VARIANTS = {
    # estandar = StandardTalents (la misma de las simulaciones de gear): 71
    # puntos, todo talento con impacto en DPS ya al máximo salvo Protector de
    # la manada (2/3). "mas_potp" solo mueve los 2 puntos de Líder de la
    # manada mejorado (maná, sin uso en DPS puro) a completar Protector de la
    # manada (3/3, +2% AP más) y 1 punto a Tenacidad primigenia (utilidad
    # PvP, sin más hueco ofensivo disponible en el árbol).
    "feral_druid": [
        ("estandar", "-503202132322010053120230310511-205503012"),
        ("mas_potp", "-503202132322010053101330310511-205503012"),
    ],
    # Guardián (feral_tank_druid): StandardTalents de wowsims para tanque,
    # ya investigada (Tools/NOTAS_TALENTOS_NIVEL2.md): todos los talentos
    # de fila con impacto en amenaza/supervivencia ya al máximo, sin punto
    # suelto real. Solo la variante estándar por ahora.
    "feral_tank_druid": [
        ("estandar", "-503232132322010353120300313511-20350001"),
    ],
}


def pick_reference_build(spec: str) -> dict:
    """La build de mayor fase con datos ya consolidados en Data/sims/<spec>,
    para no repetir la elección de gear/APL best-in-slot.

    El build_id real (nombre del .json en Data/sims/<spec>/) es el gear_file
    a secas salvo que haya más de un APL para el mismo gear_file, caso en el
    que simular_builds.py lo desambigua con un sufijo (ver su build_id_for /
    apl_suffix). Se prueban ambos formatos en vez de asumir uno solo: asumir
    siempre el sufijo (como hacía antes) fallaba en specs sin colisión de
    APL, p.ej. feral_tank_druid, cuyos ficheros son p1.json...p4.json."""
    mapeo_path = MAPEO_DIR / f"{spec}.json"
    if not mapeo_path.exists():
        raise SystemExit(f"no hay mapeo de builds para {spec}: {mapeo_path}")
    builds = load_json(mapeo_path)["builds"]

    sims_dir = DATA_DIR / "sims" / spec
    available = {p.stem for p in sims_dir.glob("*.json")} if sims_dir.exists() else set()

    candidates = [b for b in builds if b.get("status") == "ok"]
    # prioriza fase más alta (p4 > p3 > ... > preraid)
    def phase_rank(b):
        phase = b.get("phase", "")
        return int(phase[1:]) if phase.startswith("p") and phase[1:].isdigit() else -1

    candidates.sort(key=phase_rank, reverse=True)
    for build in candidates:
        candidate_ids = [build["gear_file"]]
        if build.get("apl"):
            candidate_ids.append(f"{build['gear_file']}_{apl_suffix(build['apl'])}")
        for build_id in candidate_ids:
            if build_id in available:
                build["_build_id"] = build_id
                return build
    raise SystemExit(f"ninguna build de {spec} tiene datos ya consolidados en {sims_dir}")


def simulate_variant(spec: str, build: dict, label: str, talents_string: str,
                      work_dir: pathlib.Path, iterations: int) -> dict:
    out_file = work_dir / f"{spec}_{label}.json"
    apl_file = load_apl_file(spec, build.get("apl"))
    env = build_env(spec, build["gear_file"], apl_file, None, talents_string, out_file, iterations)
    if not run_go_extractor(spec, env):
        return {"label": label, "status": "error", "motivo": "fallo generando RaidSimRequest"}

    result_file = work_dir / f"{spec}_{label}_out.json"
    result = run_wowsimcli(out_file, result_file)
    if result is None:
        return {"label": label, "status": "error", "motivo": "wowsimcli falló o excedió el timeout"}

    metrics = extract_metrics(result)
    return {
        "label": label,
        "status": "ok",
        "talents": talents_string,
        "dps": round(metrics["dps"], 1),
        "hps": round(metrics["hps"], 1),
        "tps": round(metrics["tps"], 1),
        "dtps": round(metrics["dtps"], 1),
    }


def load_existing_results(out_path: pathlib.Path) -> dict:
    """label -> resultado ya guardado, para saltar lo ya simulado si se
    interrumpe el proceso (reinicio del servidor a las 04:00)."""
    if not out_path.exists():
        return {}
    data = load_json(out_path)
    return {v["label"]: v for v in data.get("variants", [])}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--iterations", type=int, default=1000)
    parser.add_argument("--force", action="store_true",
                         help="repite también las variantes que ya tengan resultado guardado")
    args = parser.parse_args()

    variants = TALENT_VARIANTS.get(args.spec)
    if not variants:
        raise SystemExit(f"sin variantes de talentos definidas para {args.spec} (ver TALENT_VARIANTS)")

    from generar_db_addon import SPEC_INFO
    game_class = SPEC_INFO[args.spec][0]
    class_id = GAME_CLASS_TO_CLASS_ID.get(game_class)
    if class_id is None:
        raise SystemExit(f"sin class_id de Talent.dbc para {game_class} (ver CLASS_ID_TO_GAME_CLASS)")

    for label, talents_string in variants:
        ok, info = validate_build(class_id, talents_string)
        if not ok:
            raise SystemExit(f"variante '{label}' inválida contra las DBC reales: {info}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / f"{args.spec}.json"
    existing = {} if args.force else load_existing_results(out_path)

    build = pick_reference_build(args.spec)
    print(f"build de referencia: {build['_build_id']} (gear={build['gear_file']}, apl={build.get('apl')})")

    work_dir = TOOLS_DIR / "wowsimcli-src" / "sim" / __import__("specs_metadata").SPEC_GO_PACKAGES[args.spec]

    results = []
    for label, talents_string in variants:
        prior = existing.get(label)
        if prior and prior.get("status") == "ok" and prior.get("_iterations", 0) >= args.iterations \
                and prior.get("talents") == talents_string:
            print(f"{label}: ya simulado, se salta (--force para repetir)")
            results.append(prior)
            continue

        print(f"simulando {label}...", end=" ", flush=True)
        result = simulate_variant(args.spec, build, label, talents_string, work_dir, args.iterations)
        result["_iterations"] = args.iterations
        print(result.get("status"), result.get("motivo", ""))
        results.append(result)
        # guarda tras cada variante: si el proceso se corta a medias (p.ej.
        # el reinicio de las 04:00), lo ya hecho no se pierde
        out_path.write_text(json.dumps({
            "spec": args.spec,
            "reference_build": build["_build_id"],
            "iterations": args.iterations,
            "variants": results,
        }, indent=2, ensure_ascii=False), encoding="utf-8")

    out_path.write_text(json.dumps({
        "spec": args.spec,
        "reference_build": build["_build_id"],
        "iterations": args.iterations,
        "variants": results,
    }, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"guardado en {out_path}")


if __name__ == "__main__":
    main()
