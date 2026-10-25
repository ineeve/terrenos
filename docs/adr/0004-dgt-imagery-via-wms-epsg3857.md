# 0004 — DGT orthophotos via WMS in EPSG:3857 (spike S1)

- **Status:** accepted (M0, spike S1, 2026-10-25)
- **Refines:** SPEC.md §6.1, PLAN.md S1

## Findings

| Series | Coverage | WMTS | WMS (EPSG:3857) |
|---|---|---|---|
| **Ortos 2025** (25 cm) | Whole mainland | not found (`/ortos2025/service` → 404) | `https://cartografia.dgterritorio.gov.pt/wms/ortos2025`, layer `Ortos2025-RGB` |
| Ortos 2021 (25 cm) | Northern half only | PT-TM06 grid only | `…/wms/ortos2021`, layer `Ortos2021-RGB` |
| Ortos 2018 (25 cm) | Whole mainland | PT-TM06 grid only | `…/wms/ortos2018`, layer `Ortos2018-RGB` |

- The WMTS services publish only the `PTTM_06` tile grid (EPSG:3763).
- The WMS services (1.3.0) accept EPSG:3857, 4326, 4258 and 3763, return JPEG,
  PNG and `image/vnd.jpeg-png`, and allow up to 4096 × 4096 px.
- Capabilities state *Fees: no conditions apply* and *AccessConstraints: None*.
- Measured with 256 px tiles in Mirandela (north) and Évora (Alentejo):
  0.2–0.4 s per request; ≈ 10 KB per z19 JPEG tile and ≈ 20 KB per z17 tile.
  A z19 pixel is ≈ 0.23 m at 41° N, matching the 25 cm imagery.
- Outside its coverage, Ortos 2021 returns a blank JPEG (667 B) or, with
  `TRANSPARENT=TRUE`, a transparent PNG (116–334 B).

## Decision

- The default imagery layer is **Ortos 2025, WMS GetMap in EPSG:3857, JPEG,
  256 px tiles, zoom up to 19**. The map keeps `flutter_map`'s default CRS;
  the `Proj4Crs` fallback in the spec isn't needed.
- Ortos 2018 is offered as an optional "previous imagery" layer, useful when a
  boundary is hidden by vegetation in the newer flight. Ortos 2021 is left out
  because it covers only the north.
- Requests follow SPEC.md §6.1: at most 4 in parallel, an identifying
  `User-Agent`, backoff on errors, 50 000 tiles per offline area.
- Attribution: "Ortofotos © DGT" on the map, in About and in PDF exports. The
  terms are recorded in `docs/data-licences.md`.

## Consequences

- Offline areas are about **5 MB per km²** down to z19 (≈ 290 z19 tiles ×
  10 KB plus lower zooms), less than the spec's earlier 10–15 MB estimate.
- If DGT publishes a newer series, only the layer configuration changes.
