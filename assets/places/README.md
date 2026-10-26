# Place names: OpenStreetMap

`places.json` holds the cities, towns, villages and hamlets of mainland
Portugal, extracted from **OpenStreetMap** on 2026-10-26.

**Licence:** Open Database License (ODbL) 1.0. This file is a derivative
database and is available under the same licence:
<https://opendatacommons.org/licenses/odbl/1-0/>. The app's MIT licence does
not apply to it.

**Attribution:** "© OpenStreetMap contributors"
(<https://www.openstreetmap.org/copyright>), shown on the map and in the
app's Settings → Map data.

## Changes from the original

- Only nodes tagged `place` = `city`, `town`, `village` or `hamlet` with a
  `name` are kept, and only the name, kind and position.
- Places outside the mainland CAOP freguesias are dropped; each place gets
  the DICOFRE code of the freguesia it is in (from CAOP 2025, © DGT).
- Positions are rounded to 0.00001° (about 1 m). A name repeated within one
  freguesia is kept once.

## Rebuilding

See the header of `tool/build_places.dart` for the Overpass query, then run:

```sh
dart run tool/build_places.dart osm-places.json
```

## Format

JSON, version 1; read by `lib/core/places/places.dart`.

| Key | Content |
|---|---|
| `osmTimestamp` | When the OSM data was extracted |
| `places` | `[name, kind, x, y, freguesia]`: kind 0 city, 1 town, 2 village, 3 hamlet; longitude and latitude in 0.00001°; DICOFRE code. Sorted by kind, then by OSM `population` |
