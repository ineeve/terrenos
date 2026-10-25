# 0006 — Bundled CAOP 2025 asset (spike S3)

- **Status:** accepted (M1, spike S3, 2026-10-25)
- **Refines:** SPEC.md §6.2, PLAN.md T1.1 / S3

## Findings

- DGT publishes CAOP 2025 (Continente) through its OGC API with GeoJSON
  output: 3 049 freguesias, 278 municípios, 18 distritos. Licence CC BY 4.0
  (dados.gov.pt).
- The full-resolution data is large (≈ 130 KB per freguesia as GeoJSON).
- `tool/caop/build_caop.py` (Python with pyproj and shapely, instead of the
  planned Dart tool, because shapely's simplification is robust and the
  script runs only when CAOP is updated) simplifies in PT-TM06 metres and
  writes delta-encoded integer coordinates (1e-5°).

| | Result | Budget |
|---|---|---|
| Asset size | 6.3 MB (2.4 MB compressed in the APK) | ≤ 8 MB |
| Parse (desktop, release-like JIT) | ≈ 0.2 s, in a background isolate | — |
| Lookup of a point | ≈ 64 µs | < 5 ms |
| Known places (Porto, Lisboa, Évora, Faro, Mirandela, Viseu) | all correct | — |

## Decision

- Bundle the simplified asset; parse it with `compute` at first use.
- Freguesias are simplified independently, so neighbours can leave gaps of a
  few metres. `Caop.locate` falls back to the nearest freguesia within 25 m.
  The location is editable anyway (PROP-9).
- Automatic locations are marked `auto: true` and refreshed when the
  boundary is edited; a location the user sets is never overwritten.

## Consequences

- Updating to a new CAOP edition means re-running the script and checking
  `test/core/caop/caop_asset_test.dart`.
