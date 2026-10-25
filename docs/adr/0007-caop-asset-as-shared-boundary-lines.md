# 0007 — CAOP asset as shared boundary lines (spike S3)

- **Status:** accepted (M1, T1.1 and spike S3, 2026-10-25)
- **Refines:** SPEC.md §6.2, PLAN.md S3

## Findings

- The latest edition is **CAOP 2025** (Continente), a 112 MB zipped
  GeoPackage in PT-TM06 with 3 049 freguesias, 278 concelhos and 18
  distritos. It is listed on dados.gov.pt under CC BY.
- Besides polygons, it has a `cont_trocos` layer: 9 899 boundary lines, each
  stored once with the area code on its left and right (97 estuary waters,
  98 Spain, 99 the sea). 1.7 million points in total.
- Simplifying those lines once each keeps neighbouring freguesias exactly
  aligned, which simplifying each polygon separately would not. Results at
  20 000 random points, compared with the unsimplified lines (measured on
  pc12, a Ryzen 7 5700G desktop):

| Tolerance | Points | Asset | Compressed | Lookups that differ | Lookup |
|---|---|---|---|---|---|
| **10 m** | 263 k | **2.46 MB** | 0.96 MB | 12, all ≤ 3.4 m from a border | 15 µs |
| 5 m | 377 k | 3.18 MB | 1.22 MB | 6, ≤ 1.6 m | 15 µs |
| 2 m | 592 k | 4.48 MB | 1.66 MB | 3, ≤ 0.5 m | 14 µs |
| 1 m | 796 k | 5.66 MB | 2.04 MB | 3, ≤ 0.5 m | 17 µs |

- Parsing the 10 m asset takes 20–40 ms on the same machine.

## Decision

- `tool/build_caop.dart` builds `assets/caop/caop.json` from the GeoPackage:
  Douglas–Peucker at **10 m** on each boundary line in PT-TM06 metres,
  reprojection to WGS84 with the app's own PT-TM06 code, coordinates rounded
  to 0.00001° and delta-encoded.
- The asset is a compact JSON of shared lines ("arcs", as in TopoJSON), not
  GeoJSON polygons as SPEC.md §6.2 suggested. Each freguesia lists its arcs
  and a bounding box; each arc records the highest level it separates
  (coast or border, distrito, concelho, freguesia), so the map overlay can
  draw each border once and choose by zoom.
- Lookup scans the bounding boxes and runs even-odd ray casting over the
  freguesia's arcs (`AdminBoundaries.locate`). No ring assembly or spatial
  index is needed at 15 µs per point.
- The tool checks its own output against the unsimplified lines and writes
  150 reference points, at least 100 m from any border, to
  `test_fixtures/caop_reference.json`; CI checks the asset against them.
- `sqlite3` 2.x is a dev dependency for the tool only; it uses the system
  SQLite library. 3.x was avoided because it builds SQLite through native
  build hooks, which every test build would then run.

## Consequences

- The S3 targets are met: ≤ 8 MB (2.46 MB), lookup < 5 ms (15 µs on a
  desktop; even 100× slower on a phone would pass).
- At 10 m, borders are within about one pixel at z14 but can be off by up
  to 10 m (about 30 px) at z18–z19. The overlay task (T1.2) should check
  this on a phone; 5 m or 2 m cost under 2 MB more if needed. The visual
  check at z14 from the spike's exit criteria hasn't been done on a device.
- A new CAOP edition means downloading the new GeoPackage, running the tool
  and updating `caopEdition`.
