"""Consolida Data/reliquias/<spec>.json en una tabla Lua por clase."""

import argparse
import json
import math
import pathlib

from rutas_addon import class_data_dir, ensure_class_addon_toc

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
RELIQUIAS_DIR = TOOLS_DIR.parent / "Data" / "reliquias"

SPECS_POR_CLASE = {
    "Druid": ("balance_druid", "feral_druid"),
    "Shaman": ("elemental_shaman", "enhancement_shaman"),
    "Paladin": ("retribution_paladin",),
    "Deathknight": ("deathknight",),
}


def cargar_spec(spec: str) -> dict | None:
    path = RELIQUIAS_DIR / f"{spec}.json"
    if not path.exists():
        print(f"[{spec}] sin {path.relative_to(TOOLS_DIR.parent)}, se omite")
        return None

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"[{spec}] no se pudo leer el resultado ({exc}), se omite")
        return None

    if not isinstance(data, dict) or not isinstance(data.get("reliquias"), dict):
        print(f"[{spec}] resultado sin tabla reliquias válida, se omite")
        return None

    reliquias = {}
    for item_id, result in data["reliquias"].items():
        try:
            numeric_id = int(item_id)
            delta_pct = float(result["delta_pct"])
        except (TypeError, ValueError, KeyError):
            print(f"[{spec}] reliquia {item_id!r} sin id o delta_pct válido, se omite")
            continue
        if numeric_id <= 0 or not math.isfinite(delta_pct):
            print(f"[{spec}] reliquia {item_id!r} sin id o delta_pct válido, se omite")
            continue
        reliquias[numeric_id] = delta_pct

    if not reliquias:
        print(f"[{spec}] sin resultados de reliquias, se omite")
        return None
    return reliquias


def render_class_lua(class_name: str, specs: dict[str, dict[int, float]]) -> str:
    lines = [
        "-- Archivo generado automáticamente por Tools/generar_db_reliquias.py.",
        "-- Comparación de reliquias por especialización.",
        f"SimulateX_Reliquias_{class_name} = {{",
    ]
    for spec in sorted(specs):
        lines.append(f'  ["{spec}"] = {{')
        for item_id in sorted(specs[spec]):
            lines.append(f"    [{item_id}] = {specs[spec][item_id]:.2f},")
        lines.append("  },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clase", choices=tuple(SPECS_POR_CLASE),
                        help="Solo esta clase (por defecto: Druid, Shaman, Paladin y Deathknight).")
    args = parser.parse_args()

    classes = (args.clase,) if args.clase else tuple(SPECS_POR_CLASE)
    for class_name in classes:
        specs = {}
        for spec in SPECS_POR_CLASE[class_name]:
            results = cargar_spec(spec)
            if results is not None:
                specs[spec] = results

        if not specs:
            print(f"{class_name}: sin datos de reliquias; no se genera archivo")
            continue

        out_dir = class_data_dir(class_name)
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / f"SimulateX_Reliquias_{class_name}.lua"
        out_path.write_text(render_class_lua(class_name, specs), encoding="utf-8")
        ensure_class_addon_toc(class_name)
        item_count = sum(len(items) for items in specs.values())
        print(f"{class_name}: {len(specs)} spec(s), {item_count} reliquia(s) -> {out_path}")


if __name__ == "__main__":
    main()
