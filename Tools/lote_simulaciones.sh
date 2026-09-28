#!/usr/bin/env bash
# Cola de simulaciones en segundo plano. Se puede relanzar tal cual tras un
# reinicio: simular_builds.py salta las builds que ya tienen resultado.
# Uso: Tools/lote_simulaciones.sh [spec ...]   (sin specs: la cola del plan)
# Variables: SIMX_PARALELO (2), SIMX_ITERACIONES (1000), SIMX_LOG_DIR (Data/logs)
set -u
cd "$(dirname "$0")"
source ~/.simx_env
export SIMX_DBC_DIR=/home/stark/Servers/acore-playerbots/data/dbc
export LOG_DIR=${SIMX_LOG_DIR:-$(pwd)/../Data/logs}
export ITERACIONES=${SIMX_ITERACIONES:-1000}
PARALELO=${SIMX_PARALELO:-2}
mkdir -p "$LOG_DIR"

if [ $# -gt 0 ]; then
    SPECS=("$@")
else
    # Guardián primero (prioridad del usuario), luego el orden del paso 7.3
    SPECS=(feral_tank_druid
           holy_paladin protection_paladin retribution_paladin
           healing_priest smite_priest shadow_priest
           elemental_shaman enhancement_shaman restoration_shaman
           hunter mage rogue warlock
           warrior protection_warrior deathknight tank_deathknight
           feral_druid balance_druid)
fi

simular_spec() {
    local spec=$1 iteraciones=$ITERACIONES kind
    # dos procesos con la misma spec se pisarían los ficheros de salida
    if pgrep -f "[p]ython3 simular_builds.py --spec $spec( |\$)" > /dev/null; then
        echo "$(date '+%d/%m %H:%M') $spec ya se está simulando fuera del lote, se salta"
        return
    fi
    python3 generar_extractores_go.py --spec "$spec" > /dev/null
    kind=$(python3 -c "from extraer_ep_stats import extract_ep_config as e; print(e('$spec')['kind'])" 2>/dev/null)
    # sanadores con pesos preset: wowsims no los simula, solo hace falta la build base
    [ "$kind" = "preset" ] && iteraciones=100
    python3 simular_builds.py --spec "$spec" --iterations "$iteraciones" > "$LOG_DIR/sim_$spec.log" 2>&1
    echo "$(date '+%d/%m %H:%M') $spec terminado (código $?)"
}
export -f simular_spec

printf '%s\n' "${SPECS[@]}" | xargs -P "$PARALELO" -I{} bash -c 'simular_spec "$1"' _ {}
echo "$(date '+%d/%m %H:%M') lote terminado"
