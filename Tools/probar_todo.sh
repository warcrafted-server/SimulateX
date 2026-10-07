#!/usr/bin/env bash
set -u

if [[ -z "${PYTHON+x}" ]]; then
    if [[ -x "$HOME/.cache/simulatex-venv/bin/python" ]]; then
        PYTHON="$HOME/.cache/simulatex-venv/bin/python"
    else
        PYTHON=python3
    fi
fi

if ! "$PYTHON" -c "import luaparser, lupa" >/dev/null 2>&1; then
    printf 'Faltan las dependencias luaparser y lupa. Crea el entorno con:\n'
    printf '  python3 -m venv ~/.cache/simulatex-venv && ~/.cache/simulatex-venv/bin/pip install luaparser lupa\n'
    printf 'Y vuelve a ejecutar con: PYTHON=~/.cache/simulatex-venv/bin/python Tools/probar_todo.sh\n'
    exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$TMP_DIR"' EXIT

fallos=0
pruebas=0

ejecutar() {
    local nombre="$1"
    shift
    pruebas=$((pruebas + 1))
    if (cd "$ROOT" && nice -n 19 "$@") >"$TMP_DIR/salida" 2>&1; then
        printf 'OK    %s\n' "$nombre"
    else
        local codigo=$?
        printf 'FALLA %s (código %s)\n' "$nombre" "$codigo"
        cat "$TMP_DIR/salida"
        fallos=$((fallos + 1))
    fi
}

ejecutar "Sintaxis Lua (luaparser / lupa)" "$PYTHON" - <<'PY'
from pathlib import Path
from lupa import LuaRuntime
from luaparser import ast

addon = Path("Addon")
runtime = LuaRuntime()
for path in sorted(addon.rglob("*.lua")):
    source = path.read_text(encoding="utf-8")
    if path.stat().st_size > 2 * 1024 * 1024 and "Data" in path.parts:
        runtime.execute("assert(load(...))", source)
    else:
        ast.parse(source)
PY

clases=(Warrior Paladin Hunter Rogue Priest Deathknight Shaman Mage Warlock Druid)
facciones=(Horde Alliance)
for i in "${!clases[@]}"; do
    clase="${clases[$i]}"
    faccion="${facciones[$((i % 2))]}"
    ejecutar "Mejoras $clase nivel 80 $faccion" "$PYTHON" Tools/probar_mejoras_lupa.py "$clase" 80 "$faccion"
    if [[ "$clase" != "Deathknight" ]]; then
        otra_faccion="${facciones[$(((i + 1) % 2))]}"
        ejecutar "Mejoras $clase nivel 45 $otra_faccion" "$PYTHON" Tools/probar_mejoras_lupa.py "$clase" 45 "$otra_faccion"
    fi
done

ejecutar "Encantamientos recomendados" "$PYTHON" Tools/probar_encantamientos_lupa.py
ejecutar "Mejoras en las bolsas" "$PYTHON" Tools/probar_bolsas_lupa.py
ejecutar "Recetas de profesión recordadas" "$PYTHON" Tools/probar_recetas_lupa.py
ejecutar "Porcentaje contra hueco vacío" "$PYTHON" Tools/probar_hueco_libre_lupa.py

printf '\nResumen: %d pruebas, %d fallidas.\n' "$pruebas" "$fallos"
if (( fallos > 0 )); then
    exit 1
fi
