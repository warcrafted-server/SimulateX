"""Extractor de datos de objetos para SimulateX.

Consulta la instancia AoWoW de https://db.warcrafted.com (export XML nativo,
`?item=<id>&xml`) y vuelca los datos crudos a Data/items/<id>.xml (carpeta
ignorada por git) para su posterior procesado.

No se ejecuta como parte del addon; es una herramienta local de desarrollo.
"""

import argparse
import pathlib
import time
import urllib.request

BASE_URL = "https://db.warcrafted.com/"
DATA_DIR = pathlib.Path(__file__).resolve().parent.parent / "Data" / "items"
USER_AGENT = "SimulateX-Extractor/0.1 (+https://github.com/warcrafted-server/SimulateX)"


def fetch_item_xml(item_id: int) -> bytes:
    url = f"{BASE_URL}?item={item_id}&xml"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=15) as response:
        return response.read()


def save_item_xml(item_id: int, data: bytes) -> pathlib.Path:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    path = DATA_DIR / f"{item_id}.xml"
    path.write_bytes(data)
    return path


def main() -> None:
    import json

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--item-id", type=int, action="append", dest="item_ids",
                         help="ID de objeto a extraer (repetible: --item-id 1 --item-id 2)")
    parser.add_argument("--ids-file", type=pathlib.Path,
                         help="Fichero JSON con una lista de IDs a extraer")
    parser.add_argument("--delay", type=float, default=0.5,
                         help="Segundos de espera entre peticiones (por defecto 0.5)")
    parser.add_argument("--skip-existing", action="store_true",
                         help="No volver a descargar IDs que ya tengan fichero en Data/items/")
    args = parser.parse_args()

    item_ids = list(args.item_ids or [])
    if args.ids_file:
        item_ids.extend(json.loads(args.ids_file.read_text(encoding="utf-8")))
    if not item_ids:
        parser.error("hay que indicar --item-id o --ids-file")

    if args.skip_existing:
        item_ids = [i for i in item_ids if not (DATA_DIR / f"{i}.xml").exists()]

    for index, item_id in enumerate(item_ids):
        data = fetch_item_xml(item_id)
        path = save_item_xml(item_id, data)
        print(f"[{item_id}] guardado en {path} ({index + 1}/{len(item_ids)})")
        if index < len(item_ids) - 1:
            time.sleep(args.delay)


if __name__ == "__main__":
    main()
