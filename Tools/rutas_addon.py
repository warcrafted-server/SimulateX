"""Rutas de salida de los datos por clase (v0.8: sub-addons LoadOnDemand,
Addon/SimulateX_<Clase>/), compartidas por generar_db_addon.py,
generar_db_talentos.py y generar_arbol_talentos.py."""

import pathlib

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
ADDON_ROOT = TOOLS_DIR.parent / "Addon"
VERSION = "0.11.0"

_TOC_TEMPLATE = """## Interface: 30300
## Title: SimulateX (datos de {class_name})
## Notes: Datos de simulación y talentos de esta clase para SimulateX. Se carga solo para tu clase.
## Author: WarCrafted
## Version: {version}
## Dependencies: SimulateX
## LoadOnDemand: 1

{files}
"""


def class_data_dir(class_name: str) -> pathlib.Path:
    """Carpeta Data/ del sub-addon de una clase (Warrior, Paladin, ...)."""
    return ADDON_ROOT / f"SimulateX_{class_name}" / "Data"


def ensure_class_addon_toc(class_name: str) -> None:
    """Regenera el .toc del sub-addon de una clase a partir de los ficheros
    .lua que existan de verdad en su carpeta Data/, en el orden fijo
    Data, Reliquias, Talentos, ArbolTalentos. No falla si falta alguno: cada clase
    solo tiene los datos que ya se hayan consolidado."""
    sub_addon_dir = ADDON_ROOT / f"SimulateX_{class_name}"
    data_dir = class_data_dir(class_name)
    ordered_names = [
        f"SimulateX_Data_{class_name}.lua",
        f"SimulateX_Reliquias_{class_name}.lua",
        f"SimulateX_Talentos_{class_name}.lua",
        f"SimulateX_ArbolTalentos_{class_name}.lua",
    ]
    files = "\n".join(
        f"Data\\{name}" for name in ordered_names if (data_dir / name).exists()
    )
    toc_path = sub_addon_dir / f"SimulateX_{class_name}.toc"
    toc_path.write_text(
        _TOC_TEMPLATE.format(class_name=class_name, version=VERSION, files=files),
        encoding="utf-8",
    )
