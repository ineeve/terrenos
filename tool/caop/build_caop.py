"""Builds assets/caop/caop.json from DGT's CAOP (SPEC.md §6.2, PLAN.md T1.1).

Downloads the official administrative boundaries of mainland Portugal from
DGT's OGC API, simplifies them and writes a compact asset for offline use:

- freguesias (for filling in location fields and place search), simplified
  at 5 m so a parcel's interior point almost always falls in the right one;
- municípios and distritos (map overlay only), simplified more coarsely.

Coordinates are WGS84 degrees × 1e5 (≈ 1 m), delta-encoded per ring.

Run (needs pyproj and shapely):

    python3 tool/caop/build_caop.py
"""
import json
import pathlib
import sys
import time
import urllib.request

import pyproj
from shapely.geometry import MultiPolygon, Polygon, shape
from shapely.ops import transform

API = "https://ogcapi.dgterritorio.gov.pt/collections/{}/items?f=json&limit={}&offset={}"
EDITION = "CAOP2025"
SCALE = 1e5
TOLERANCE_M = {"freguesias": 5.0, "municipios": 30.0, "distritos": 150.0}

to_metres = pyproj.Transformer.from_crs("EPSG:4326", "EPSG:3763", always_xy=True).transform
to_degrees = pyproj.Transformer.from_crs("EPSG:3763", "EPSG:4326", always_xy=True).transform


def fetch(collection, page=100):
    offset = 0
    while True:
        url = API.format(collection, page, offset)
        for attempt in range(5):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "Terrenos CAOP build (+https://github.com/ineeve/terrenos)"})
                with urllib.request.urlopen(req, timeout=300) as r:
                    data = json.load(r)
                break
            except Exception as e:  # noqa: BLE001 - retry any network error
                print(f"  retry {attempt + 1} for offset {offset}: {e}", file=sys.stderr)
                time.sleep(5 * (attempt + 1))
        else:
            raise SystemExit(f"giving up on {url}")
        features = data["features"]
        yield from features
        print(f"  {collection}: {offset + len(features)} / {data.get('numberMatched')}", file=sys.stderr)
        if len(features) < page:
            return
        offset += page


def encode_ring(coords):
    out = []
    px = py = 0
    for x, y in coords[:-1]:  # rings are stored open
        qx, qy = round(x * SCALE), round(y * SCALE)
        out += [qx - px, qy - py]
        px, py = qx, qy
    return out


def encode(geom, tolerance):
    simplified = transform(to_degrees, transform(to_metres, geom).simplify(tolerance, preserve_topology=True))
    polygons = simplified.geoms if isinstance(simplified, MultiPolygon) else [simplified]
    parts = []
    for poly in polygons:
        if not isinstance(poly, Polygon) or poly.is_empty:
            continue
        rings = [encode_ring(list(poly.exterior.coords))]
        rings += [encode_ring(list(r.coords)) for r in poly.interiors]
        if len(rings[0]) >= 6:
            parts.append(rings)
    minx, miny, maxx, maxy = simplified.bounds
    bbox = [round(minx * SCALE), round(miny * SCALE), round(maxx * SCALE), round(maxy * SCALE)]
    return parts, bbox


def build(collection, props):
    out = []
    for f in fetch(collection):
        parts, bbox = encode(shape(f["geometry"]), TOLERANCE_M[collection])
        entry = {k: f["properties"][v] for k, v in props.items()}
        entry["b"] = bbox
        entry["p"] = parts
        out.append(entry)
    return out


def main():
    root = pathlib.Path(__file__).resolve().parents[2]
    asset = {
        "edition": EDITION,
        "source": "Direção-Geral do Território, Carta Administrativa Oficial de Portugal (Continente), via ogcapi.dgterritorio.gov.pt",
        "scale": SCALE,
        "freguesias": build("freguesias", {"c": "dtmnfr", "f": "freguesia", "m": "municipio", "d": "distrito_ilha"}),
        "municipios": build("municipios", {"n": "municipio", "d": "distrito_ilha"}),
        "distritos": build("distritos", {"n": "distrito"}),
    }
    path = root / "assets" / "caop" / "caop.json"
    path.write_text(json.dumps(asset, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {path} ({path.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
