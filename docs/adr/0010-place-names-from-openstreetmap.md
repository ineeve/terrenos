# 0010 — Place names from OpenStreetMap

- **Status:** accepted (M2, 2026-10-26)
- **Refines:** SPEC.md §3.2 (MAP-9, new MAP-15) and §6; adds §6.3

## Context

When zoomed out, the map showed only distrito borders over the
orthophotos, with no names, so there was nothing to tell the user where they
were. There was no search either. The DGT orthophotos have no labels, and
CAOP has the names of areas but not where towns and villages are.

## Options

| Source | Coverage (mainland) | Licence |
|---|---|---|
| CAOP names only | 18 distritos, 278 concelhos, 3 049 freguesias; no towns | CC BY |
| GeoNames | Cities and towns are good; many villages and lugares are missing | CC BY 4.0 |
| **OpenStreetMap** | 146 cities, 572 towns, 3 300 villages, 14 282 hamlets | ODbL 1.0 |

The project owner chose OpenStreetMap, which is the most complete for the
small rural places the app's users know.

## Decision

- `tool/build_places.dart` builds `assets/places/places.json` from an
  Overpass extract of every node tagged `place=city|town|village|hamlet`
  with a `name`, in a box around the mainland. It keeps only places inside a
  CAOP freguesia, which drops Spain and stores each place's DICOFRE code. A
  name repeated in one freguesia is kept once.
- The asset is a JSON list of `[name, kind, x, y, freguesia]`, sorted by
  kind and then by OSM `population`. 18 300 places, 0.77 MB (0.27 MB
  compressed). It is parsed in a background isolate, like CAOP.
- **Labels (MAP-15):** cities at every zoom, towns from z9, villages from
  z11 and hamlets from z13. Places are labelled in the asset's order, and a
  name that would overlap one already placed is left out, so bigger places
  win. At most 120 names at a time. The layer is drawn in screen space, so
  names stay upright on a rotated map. A switch in the layers sheet hides
  them.
- **Search (MAP-9):** a search bar over the map finds the user's properties
  (as in IDN-6) and, offline, distritos, concelhos and freguesias (by short
  or official name) and OSM places. Matches are accent- and
  case-insensitive and ranked exact, then prefix, then word start, then
  anywhere; ties go to the bigger kind of place. Each place shows its
  freguesia and concelho, so the three "Porto"s can be told apart. Choosing
  an area frames its bounding box; choosing a place moves there and drops a
  pin, which is removed by tapping it.

## Consequences

- **ODbL attribution:** "© OpenStreetMap" is shown on the map, and
  "Place names © OpenStreetMap contributors, ODbL" in Settings → Map data.
  The bundled extract is a derivative database, so it stays under the ODbL
  (share-alike); this doesn't affect the app's MIT licence. See
  `docs/data-licences.md`.
- OSM names are community-maintained and not official. They're used only
  to find places, never stored in properties (location fields still come
  from CAOP).
- The asset is rebuilt by hand: download the extract and run the tool after
  any CAOP update.
- Not done here: going to typed coordinates (MAP-10), and labels for
  concelho or freguesia names.
