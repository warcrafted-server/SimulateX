"""Modelo de topes (golpe, pericia, penetración de armadura) de una build, para
que el addon corrija la puntuación según lo que le falta al jugador para el
tope, no según el preset de wowsims (que suele ir ya topado).

Todo sale de wowsims, sin cifras propias:
- Estadísticas del preset: core.ComputeStats (Tools/go/simx_stats), total y
  sin cada pieza, para saber cuánto aporta cada hueco con gemas y encantamiento.
- Topes: tablas de ataque de sim/core/target.go contra un jefe de nivel 83
  (fallo melee 8 %, hechizo 17 %, esquiva 6,5 %, parada 14 %), constantes de
  rating de base_stats_auto_gen.go y constants.go, y el +3 % de golpe de
  hechizo de Miseria / Fuego feérico mejorado de debuffs.go.
- Peso por debajo del tope: StatWeights de wowsims con el preset desplazado
  por debajo del tope (SIMX_SW_BONUS_STATS), porque en un preset topado
  wowsims da peso 0 a esa estadística.
"""

import json
import pathlib
import subprocess

from simular_builds import build_env, run_go_stat_weights, load_json, WOWSIMS_SRC

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
GO_SOURCE = TOOLS_DIR / "go" / "simx_stats" / "main.go"
GO_BINARY = TOOLS_DIR / "simx_stats"

MELEE_HIT_PER_PCT = 32.789989
SPELL_HIT_PER_PCT = 26.231993
EXPERTISE_PER_QUARTER_PCT = 8.197496
ARP_PER_PCT = 13.99

STAT_INDEX = {"meleeHit": 12, "spellHit": 7, "expertise": 16, "arp": 15}
STAT_PROTO_NAME = {"meleeHit": "StatMeleeHit", "spellHit": "StatSpellHit",
                   "expertise": "StatExpertise", "arp": "StatArmorPenetration"}

SPELL_SPECS = {"balance_druid", "shadow_priest", "smite_priest", "elemental_shaman", "mage", "warlock"}
HYBRID_SPELL_SPECS = {"enhancement_shaman"}  # melee con hechizos que también pueden fallar
NO_EXPERTISE_SPECS = {"hunter"}  # la pericia no afecta a los ataques a distancia

# wowsims pesa con ±20 de rating (statweight.go::defaultStatMod): si el preset
# está a menos de eso del tope, el lado alto sale recortado y el peso, bajo
SW_STAT_MOD = 20.0
BELOW_CAP_MARGIN = 2 * SW_STAT_MOD


def ensure_binary() -> None:
    """Compila simx_stats dentro del árbol de wowsims si falta o está viejo."""
    if GO_BINARY.exists() and GO_BINARY.stat().st_mtime >= GO_SOURCE.stat().st_mtime:
        return
    target_dir = WOWSIMS_SRC / "cmd" / "simx_stats"
    target_dir.mkdir(parents=True, exist_ok=True)
    (target_dir / "main.go").write_text(GO_SOURCE.read_text(encoding="utf-8"), encoding="utf-8")
    subprocess.run(["go", "build", "-tags", "with_db", "-o", str(GO_BINARY), "./cmd/simx_stats"],
                   cwd=WOWSIMS_SRC, check=True, capture_output=True)


def preset_stats(request_path: pathlib.Path) -> dict | None:
    ensure_binary()
    result = subprocess.run([str(GO_BINARY), str(request_path)], capture_output=True, text=True, timeout=300)
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def is_dual_wield(request: dict, items_by_id: dict) -> bool:
    items = request["raid"]["parties"][0]["players"][0]["equipment"]["items"]
    offhand = items[15] if len(items) > 15 else {}
    item = items_by_id.get(str(offhand.get("id", 0)), {})
    return item.get("class") == 2


def spell_hit_debuff(request: dict) -> float:
    debuffs = request["raid"].get("debuffs", {})
    if debuffs.get("misery") or debuffs.get("faerieFire") == "TristateEffectImproved":
        return 3 * SPELL_HIT_PER_PCT
    return 0.0


def relevant_stats(spec: str, role: str) -> list:
    if role == "healer":
        return []
    if spec in SPELL_SPECS:
        return ["spellHit"]
    stats = ["meleeHit", "arp"]
    if spec not in NO_EXPERTISE_SPECS:
        stats.append("expertise")
    if spec in HYBRID_SPELL_SPECS:
        stats.append("spellHit")
    return stats


def cap_rating(stat: str, role: str, dual_wield: bool, debuff: float) -> float:
    if stat == "meleeHit":
        # doble empuñadura: los golpes blancos fallan un 8 + 19 % (target.go / DW)
        return (27 if dual_wield else 8) * MELEE_HIT_PER_PCT
    if stat == "spellHit":
        return 17 * SPELL_HIT_PER_PCT - debuff
    if stat == "expertise":
        # tanque de frente: también parada (14 %); DPS por detrás: solo esquiva (6,5 %)
        return (14 if role == "tank" else 6.5) * 4 * EXPERTISE_PER_QUARTER_PCT
    return 100 * ARP_PER_PCT


def below_cap_weights(spec: str, build: dict, talents_string: str, work_dir: pathlib.Path,
                      shifts: dict, metric: str) -> dict | None:
    """Peso bruto (métrica del rol) de cada stat con el preset desplazado."""
    out_file = work_dir / f"{build['gear_file']}_sw_caps.json"
    env = build_env(spec, build["gear_file"], build.get("apl_file"), None, talents_string, out_file)
    env["SIMX_SW_OUT_FILE"] = str(out_file)
    env["SIMX_SW_ITERATIONS"] = "5000"
    env["SIMX_SW_STATS"] = ",".join(STAT_PROTO_NAME[s] for s in shifts)
    env["SIMX_SW_BONUS_STATS"] = ",".join(f"{STAT_INDEX[s]}={round(v, 2)}" for s, v in shifts.items())
    if not run_go_stat_weights(spec, env) or not out_file.exists():
        return None
    raw = load_json(out_file)[metric]["weights"]["stats"]
    out_file.unlink(missing_ok=True)
    return {s: raw[STAT_INDEX[s]] for s in shifts}


def build_caps(spec: str, role: str, metric: str, request_path: pathlib.Path, build: dict,
               talents_string: str, work_dir: pathlib.Path, weights_index: dict, items_by_id: dict) -> dict | None:
    """Bloque "caps" de la build para el addon, o None si no aplica/falla."""
    stats_to_model = relevant_stats(spec, role)
    if not stats_to_model:
        return None
    stats = preset_stats(request_path)
    if stats is None:
        return None
    request = load_json(request_path)
    dual_wield = is_dual_wield(request, items_by_id)
    debuff = spell_hit_debuff(request)

    caps = {}
    shifts = {}
    for stat in stats_to_model:
        idx = STAT_INDEX[stat]
        final = stats["final"][idx]
        cap = cap_rating(stat, role, dual_wield, debuff)
        slots = {slot: round(final - without[idx], 1)
                 for slot, without in enumerate(stats["withoutSlot"]) if final - without[idx] > 0.05}
        caps[stat] = {
            "cap": round(cap, 1),
            "preset": round(final, 1),
            "nonGear": round(final - stats["gear"][idx], 1),
            # presetWeight: el que ya va dentro de build.weights (lineal);
            # weight: el valor real por punto mientras no se llega al tope
            "presetWeight": round(weights_index.get(idx, 0.0), 4),
            "weight": round(weights_index.get(idx, 0.0), 4),
            "slots": slots,
        }
        if stat == "spellHit" and debuff:
            caps[stat]["debuff"] = round(debuff, 1)
        if final > cap - BELOW_CAP_MARGIN:
            shifts[stat] = (cap - BELOW_CAP_MARGIN) - final

    if shifts:
        below = below_cap_weights(spec, build, talents_string, work_dir, shifts, metric)
        if below is None:
            return None
        for stat, weight in below.items():
            caps[stat]["weight"] = round(weight, 4)

    return {stat: block for stat, block in caps.items() if block["weight"] > 0}
