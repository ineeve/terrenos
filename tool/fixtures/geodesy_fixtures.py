"""Generates test_fixtures/geodesy_reference.json with PROJ/GeographicLib.

Reference values for lib/core/geometry tests (SPEC.md §7.2: geodesic area and
perimeter within 0.05 %). Run with pyproj installed:

    python3 tool/fixtures/geodesy_fixtures.py
"""
import json
import pathlib

import pyproj

geod = pyproj.Geod(ellps="WGS84")

# Open rings of [lon, lat]; parts → rings (outer first).
polygons = {
    "porto_square": [[[[-8.6291, 41.1579], [-8.6280, 41.1579], [-8.6280, 41.1588], [-8.6291, 41.1588]]]],
    "alentejo_irregular": [[[[-7.9101, 38.5702], [-7.9052, 38.5698], [-7.9031, 38.5731],
                             [-7.9069, 38.5755], [-7.9108, 38.5737], [-7.9112, 38.5719]]]],
    "minho_thin_strip": [[[[-8.4210, 41.8000], [-8.4150, 41.8004], [-8.4150, 41.8005], [-8.4210, 41.8001]]]],
    "tras_os_montes_large": [[[[-7.20, 41.45], [-7.08, 41.45], [-7.08, 41.54], [-7.20, 41.54]]]],
    "algarve_two_parts": [
        [[[-8.0010, 37.1000], [-7.9990, 37.1000], [-7.9990, 37.1015], [-8.0010, 37.1015]]],
        [[[-7.9980, 37.1000], [-7.9965, 37.1000], [-7.9965, 37.1012]]],
    ],
    "clockwise_ring": [[[[-8.0, 40.0], [-8.0, 40.001], [-7.999, 40.001], [-7.999, 40.0]]]],
}


def ring_area_perimeter(ring):
    lons = [p[0] for p in ring]
    lats = [p[1] for p in ring]
    area, perimeter = geod.polygon_area_perimeter(lons, lats)
    return abs(area), perimeter


out = {"generator": f"PROJ {pyproj.proj_version_str}, pyproj {pyproj.__version__}", "polygons": [], "distances": []}
for name, parts in polygons.items():
    area = 0.0
    perimeter = 0.0
    for part in parts:
        for i, ring in enumerate(part):
            a, p = ring_area_perimeter(ring)
            area += a if i == 0 else -a
            perimeter += p
    out["polygons"].append({"name": name, "parts": parts, "area_m2": area, "perimeter_m": perimeter})

pairs = [
    ("porto_short", (-8.6291, 41.1579), (-8.6280, 41.1588)),
    ("one_metre_north", (-8.0, 40.0), (-8.0, 40.0 + 1 / 111034.6)),
    ("across_portugal", (-9.50, 36.95), (-6.19, 42.15)),
    ("due_west", (-7.0, 39.0), (-7.01, 39.0)),
]
for name, (lon1, lat1), (lon2, lat2) in pairs:
    az12, _, dist = geod.inv(lon1, lat1, lon2, lat2)
    out["distances"].append({"name": name, "from": [lon1, lat1], "to": [lon2, lat2],
                             "distance_m": dist, "initial_bearing_deg": az12 % 360})

path = pathlib.Path(__file__).resolve().parents[2] / "test_fixtures" / "geodesy_reference.json"
path.write_text(json.dumps(out, indent=1) + "\n")
print(f"wrote {path}")
