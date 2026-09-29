"""Extrae Map.dbc y AreaTable.dbc del cliente esES a Data/dbc_cliente/, para
los nombres de zona e instancia de la lista de la compra. Las DBC del
servidor solo traen el texto en inglés; las del cliente llevan el esES en
su hueco de idioma.

Uso: extraer_dbc_cliente.py <carpeta del cliente WoW>. Requiere mpyq
(pip install mpyq). Solo lee los MPQ.
"""

import pathlib
import sys

import mpyq

OUT_DIR = pathlib.Path(__file__).resolve().parent.parent / "Data" / "dbc_cliente"
LOCALE = "esES"
FILES = ("Map.dbc", "AreaTable.dbc")
# El parche más reciente manda
ARCHIVES = (f"patch-{LOCALE}-3.MPQ", f"patch-{LOCALE}-2.MPQ", f"patch-{LOCALE}.MPQ", f"locale-{LOCALE}.MPQ")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    locale_dir = pathlib.Path(sys.argv[1]) / "Data" / LOCALE
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    pending = set(FILES)
    for archive_name in ARCHIVES:
        path = locale_dir / archive_name
        if not path.exists() or not pending:
            continue
        archive = mpyq.MPQArchive(str(path), listfile=True)
        for name in sorted(pending):
            data = archive.read_file(f"DBFilesClient\\{name}")
            if data:
                (OUT_DIR / name).write_bytes(data)
                pending.discard(name)
                print(f"{name} <- {archive_name}")
    if pending:
        raise SystemExit(f"No encontrados en {locale_dir}: {', '.join(sorted(pending))}")


if __name__ == "__main__":
    main()
