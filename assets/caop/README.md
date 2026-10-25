# CAOP 2025 — administrative boundaries of mainland Portugal

`caop.json` is derived from the **Carta Administrativa Oficial de Portugal
(CAOP) 2025, Continente**, published by the Direção-Geral do Território
(DGT) under the Creative Commons Attribution licence (CC BY), as listed on
[dados.gov.pt](https://dados.gov.pt/datasets/carta-administrativa-oficial-de-portugal-caop2025-continente).

**Attribution:** "Limites administrativos: CAOP 2025 © DGT" (shown in the
app's Settings → Map data).

## Changes from the original

- Only the boundary lines (`cont_trocos`) and the names and codes of
  distritos, concelhos and freguesias are kept.
- Lines are simplified with Douglas–Peucker at a 10 m tolerance, reprojected
  from PT-TM06 (EPSG:3763) to WGS84, and rounded to 0.00001° (about 1 m).
- The result is **not an official boundary** and must not be used as one.

## Rebuilding

Download and unzip
<https://geo2.dgterritorio.gov.pt/caop/CAOP_Continente_2025-gpkg.zip>
(not committed), then run:

```sh
dart run tool/build_caop.dart Continente_CAOP2025.gpkg
```

The tool also rewrites `test_fixtures/caop_reference.json`. On Linux it needs
the system SQLite library (`libsqlite3.so.0`, installed on Ubuntu by
default).

## Format

JSON, version 1; read by `lib/core/caop/admin_boundaries.dart`.

| Key | Content |
|---|---|
| `edition` | CAOP year |
| `distritos`, `concelhos` | `[code, name]` |
| `freguesias` | `[DICOFRE code, official name, simplified name, [west, south, east, north], [arc indices]]` |
| `arcs` | `[level, x0, y0, dx1, dy1, …]`: a boundary line in 0.00001° units, delta-encoded. Level 0 is the coast, the border with Spain or estuary waters; 1 a distrito border; 2 a concelho border; 3 a freguesia border |

Every line is stored once and shared by the two freguesias on either side,
so neighbouring freguesias have no gaps or overlaps after simplification.
