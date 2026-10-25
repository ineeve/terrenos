# 0005 — PT-TM06 conversions with proj4dart (spike S4)

- **Status:** accepted (M0, spike S4, 2026-10-25)
- **Refines:** SPEC.md §7.2, PLAN.md S4

## Findings

`proj4dart` 3.0.0 (MIT) with the EPSG:3763 definition was compared with PROJ
9.8.1 on 50 points: a 7 × 7 grid over mainland Portugal (36.95–42.15° N,
9.50–6.19° W) plus Porto. The reference values are in
`test_fixtures/pttm06_reference.csv` and are checked by
`test/core/crs/pt_tm06_test.dart` on every CI run.

| Direction | Worst error |
|---|---|
| WGS84 → PT-TM06 | 0.105 mm |
| PT-TM06 → WGS84 | 0.105 mm |

The target was ≤ 1 cm.

## Decision

Use `proj4dart` for PT-TM06 (`lib/core/crs/pt_tm06.dart`). The fallback of
writing the Transverse Mercator series by hand isn't needed.

ETRS89 and WGS84 are treated as the same datum (no shift), as SPEC.md §7.2
allows: the difference in Portugal is well below phone GPS accuracy.
