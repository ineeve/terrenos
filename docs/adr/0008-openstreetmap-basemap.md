# 0008 — OpenStreetMap as the low-detail basemap

- **Status:** accepted (M1, 2026-10-25; decided by the project owner)
- **Refines:** SPEC.md §6.1, D13; follows ADR 0004's update

## Context

DGT's orthophotos are only served from zoom 14 (1:50 000). Further out the
map had only a plain background with CAOP boundaries, which made it hard to
find a place before zooming in.

## Decision

- Below and at zoom 14, the map shows **OpenStreetMap's standard tiles**
  (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`). From zoom 14 the DGT
  orthophotos are drawn on top; OSM is never requested above zoom 14.
- We follow the [OSMF tile usage policy](https://operations.osmfoundation.org/policies/tiles/):
  - an identifying User-Agent with a contact URL
    (`Terrenos (+https://github.com/ineeve/terrenos)`);
  - visible attribution, "© OpenStreetMap contributors", which opens the
    copyright page when tapped;
  - HTTP caching honoured (flutter_map's built-in cache, with a 7-day
    fallback), no no-cache headers;
  - **no bulk or offline download of OSM tiles.** Offline areas (MAP-7)
    download DGT imagery only.
- The attribution shows only the sources on screen: OSM up to zoom 14, DGT
  from zoom 14.

## Consequences

- The app now contacts two map tile services; neither receives any user
  data beyond normal tile requests (IP address, tile coordinates).
- The policy asks that the tile URL be configurable without an app update.
  With no server, changing it needs an app release; it lives in one place
  (`OsmBasemap` in `lib/core/map/imagery.dart`).
- Offline, low zoom levels show tiles from the HTTP cache if previously
  viewed, otherwise the plain background with CAOP boundaries.
