"""Genera la matriz de builds de referencia PvE para SimulateX.

Parsea los ficheros `ui/<spec>/presets.ts` del código fuente de wowsims/wotlk
(clonado en Tools/wowsimcli-src/, no versionado) para extraer, sin transcripción
manual, cada preset de gearset por fase de contenido junto con sus talentos y
rotación (APL) asociados. Escribe el resultado en Tools/builds/<spec>.json,
que sí se versiona: es la definición de qué se simula, no un dato extraído.

Los ficheros presets.ts son TypeScript, pero con una estructura muy regular
(generada por los propios mantenedores del proyecto de forma consistente), por
lo que se parsean con expresiones regulares en vez de un parser TS completo.
"""

import json
import pathlib
import re

WOWSIMS_SRC = pathlib.Path(__file__).resolve().parent / "wowsimcli-src"
UI_DIR = WOWSIMS_SRC / "ui"
OUT_DIR = pathlib.Path(__file__).resolve().parent / "builds"

GEAR_IMPORT_RE = re.compile(
    r"import\s+(\w+)\s+from\s+'\./gear_sets/([\w.]+)\.gear\.json'"
)
GEAR_PRESET_RE = re.compile(
    r"export const (\w+)\s*=\s*PresetUtils\.makePresetGear\(\s*'([^']*)'\s*,\s*(\w+)"
    r"(?:\s*,\s*\{([^}]*)\})?"
)
APL_IMPORT_RE = re.compile(
    r"import\s+(\w+)\s+from\s+'\./apls/([\w.]+)\.apl\.json'"
)
APL_PRESET_RE = re.compile(
    r"export const (\w+)\s*=\s*PresetUtils\.makePresetAPLRotation\(\s*'([^']*)'\s*,\s*(\w+)"
    r"(?:\s*,\s*\{([^}]*)\})?"
)
TALENTS_BLOCK_RE = re.compile(
    r"export const (\w+)\s*=\s*\{\s*name:\s*'([^']*)'.*?talentsString:\s*'([^']*)'",
    re.DOTALL,
)
TALENT_TREE_RE = re.compile(r"talentTrees?:\s*(\[[^\]]*\]|\d+)")
FACTION_RE = re.compile(r"faction:\s*Faction\.(\w+)")


def parse_talent_trees(options_block):
    if not options_block:
        return []
    match = TALENT_TREE_RE.search(options_block)
    if not match:
        return []
    raw = match.group(1)
    if raw.startswith("["):
        return [int(x) for x in raw.strip("[]").split(",") if x.strip() != ""]
    return [int(raw)]


def parse_faction(options_block):
    if not options_block:
        return None
    match = FACTION_RE.search(options_block)
    return match.group(1) if match else None


def parse_presets_file(spec: str, path: pathlib.Path) -> dict:
    text = path.read_text(encoding="utf-8")

    gear_files_by_var = dict(GEAR_IMPORT_RE.findall(text))
    apl_files_by_var = dict(APL_IMPORT_RE.findall(text))

    gear_presets = []
    for const_name, label, var_name, options_block in GEAR_PRESET_RE.findall(text):
        gear_presets.append({
            "const_name": const_name,
            "label": label,
            "gear_file": gear_files_by_var.get(var_name),
            "talent_trees": parse_talent_trees(options_block),
            "faction": parse_faction(options_block),
        })

    apl_presets = []
    for const_name, label, var_name, options_block in APL_PRESET_RE.findall(text):
        apl_presets.append({
            "const_name": const_name,
            "label": label,
            "apl_file": apl_files_by_var.get(var_name),
            "talent_trees": parse_talent_trees(options_block),
        })

    talent_sets = []
    for const_name, label, talents_string in TALENTS_BLOCK_RE.findall(text):
        talent_sets.append({
            "const_name": const_name,
            "label": label,
            "talents_string": talents_string,
        })

    return {
        "spec": spec,
        "gear_presets": gear_presets,
        "apl_presets": apl_presets,
        "talent_sets": talent_sets,
    }


def main() -> None:
    if not UI_DIR.exists():
        raise SystemExit(
            f"No existe {UI_DIR}. Clona wowsims/wotlk en Tools/wowsimcli-src/ primero."
        )

    OUT_DIR.mkdir(exist_ok=True)

    NON_SPEC_DIRS = {"raid", "core"}

    specs_processed = 0
    for presets_file in sorted(UI_DIR.glob("*/presets.ts")):
        spec = presets_file.parent.name
        if spec in NON_SPEC_DIRS:
            continue
        data = parse_presets_file(spec, presets_file)
        out_path = OUT_DIR / f"{spec}.json"
        out_path.write_text(
            json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        print(f"[{spec}] {len(data['gear_presets'])} gearsets, "
              f"{len(data['apl_presets'])} rotaciones, "
              f"{len(data['talent_sets'])} sets de talentos -> {out_path}")
        specs_processed += 1

    print(f"\nTotal specs procesadas: {specs_processed}")


if __name__ == "__main__":
    main()
