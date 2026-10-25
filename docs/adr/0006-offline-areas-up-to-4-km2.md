# 0006 — Offline areas up to 4 km², 8 requests at a time

- **Status:** accepted (M2, T2.7, 2026-10-25)
- **Changes:** SPEC.md MAP-7, §6.1 (was: 50 000 tiles per offline area, at
  most 4 concurrent requests)

## Findings

DGT publishes no request-rate limit: the WMS capabilities say only
`Fees: no conditions apply` and `AccessConstraints: None`, and responses
carry no rate-limit headers. Measured on 2026-10-25 (Sunday evening), 200
fresh z19 tiles per run, one run in Trás-os-Montes and one in Alentejo:

| Parallel requests | Tiles/s | Response time |
|---|---|---|
| 4 | 14–15 | 0.25–0.27 s |
| 6 | 23–24 | 0.24–0.25 s |
| 8 | 29–30 | 0.26 s |
| 10 | 28–34 | 0.29–0.35 s |

Throughput stops improving at about 8, and response times start to rise at
10.

## Decision

- **At most 8 concurrent requests** per download (`TileDownloader`).
- **Offline areas are limited to 4 km²**: at high detail (z10–z19) about
  1 550 tiles and 19 MB in the Algarve to 1 850 tiles and 22 MB in the
  north; at normal detail (z10–z17) under 200 tiles and 4 MB. At 8
  requests a 4 km² area downloads in about a minute. The 50 000-tile limit
  is dropped, because 4 km² is always far below it.
- Areas are framed as a latitude/longitude rectangle (map rotation is off
  while framing). Tiles from z10 up to z17 (normal) or z19 (high detail).
- One area downloads at a time; others wait in a queue.
- A tile is tried 5 times, waiting 1, 2, 4 and 8 s in between. If it still
  fails, the download stops and the area is marked incomplete. Resuming
  skips the tiles already on disk. Incomplete downloads are resumed by the
  user, not automatically when the app starts, so the app never makes
  requests the user didn't start.
- Deleting an area keeps tiles that another area of the same imagery also
  covers.
- The offline maps screen also shows flutter_map's own cache of tiles seen
  while browsing online (`fm_cache`, up to 1 GB, which Android may clear) and
  lets the user clear it.

## Consequences

- Large holdings need several areas. Users can download up to 4 km² at a
  time as often as they want.
- The size estimate uses ≈ 10 KB per z19 tile and ≈ 20 KB at z17 and below
  (ADR 0004); z18 is assumed to be 15 KB, which wasn't measured.
- The measurements were taken at one time of day. Repeat them on a weekday
  before relying on the speed figures.
