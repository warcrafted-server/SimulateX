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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--item-id", type=int, action="append", dest="item_ids", required=True,
                         help="ID de objeto a extraer (repetible: --item-id 1 --item-id 2)")
    parser.add_argument("--delay", type=float, default=0.5,
                         help="Segundos de espera entre peticiones (por defecto 0.5)")
    args = parser.parse_args()

    for index, item_id in enumerate(args.item_ids):
        data = fetch_item_xml(item_id)
        path = save_item_xml(item_id, data)
        print(f"[{item_id}] guardado en {path}")
        if index < len(args.item_ids) - 1:
            time.sleep(args.delay)


if __name__ == "__main__":
    main()
