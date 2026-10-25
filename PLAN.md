# Terrenos — Implementation Plan

| | |
|---|---|
| **Follows** | `SPEC.md` v0.6 (requirement IDs below refer to it) |
| **Date** | 2026-10-25 |
| **Team assumed** | 1 experienced Flutter developer (full time), plus part-time help: a European Portuguese reviewer, 12+ beta testers, 5 usability participants (age 50+) |
| **Duration** | ≈ 19.5 weeks of work + 2 weeks buffer ≈ **21.5 weeks** |

The spec's §14 estimated 17.5 weeks. This plan adds the work the spec's figure left out: up-front
technical spikes, two field tests, a usability test, and store and release work. With those
included, the honest total is about 19.5 weeks, plus a 10 % buffer.

---

## 1. Approach

1. **Tackle the riskiest unknowns first.** The things that could force a redesign are tested in
   week 1–3 spikes (§3), before any feature depends on them: the DGT service, Nearby
   Connections, PT-TM06 accuracy, the CAOP asset size, crypto speed and map performance.
2. **Fix the synced document format on day one, even though sync arrives in M3.** The property
   document (HLC registers, geometry version DAG, vertex IDs, `vertexInfo`) is designed and
   implemented in M0. Every feature then writes sync-ready data from the start, so nothing needs
   migrating later.
3. **Keep the core in pure Dart.** Geometry, coordinate systems, CRDT merging and the sync
   protocol live in `lib/core/` with no Flutter imports. They are tested heavily (≥ 90 %
   coverage, property-based tests for merging).
4. **Build features end to end.** Each task delivers the UI, PT and EN strings, TalkBack labels
   and tests together. A milestone ends with a demo against the spec's acceptance criteria (§12
   of the spec).
5. **Start Play closed testing early.** New personal Play developer accounts need 12+ testers
   for 14 consecutive days before production. Testers are recruited in M2 and closed testing
   starts at the end of M4, so this waiting period overlaps M5–M6 instead of delaying the
   launch.

---

## 2. Week 0: Prerequisites

| # | Item | Owner | Notes |
|---|---|---|---|
| P1 | Install Flutter (stable), pinned with FVM | Dev | Not installed on this machine yet. The Android SDK (`~/Android/Sdk`) and Java (sdkman) are already present |
| P2 | 3 physical Android phones: one on API 24–26, one mid-range on a current Android (Galaxy A15 class, the performance reference), and one from a different brand (e.g. Xiaomi or Motorola) | Owner | Nearby can't be tested on emulators |
| P3 | Create a public GitHub repository | Owner | Push only with the owner's approval. Signing keys never go into the repo (§5.3 of the spec) |
| P4 | Google Play developer account | Owner | Needed to start the internal track in M1 and closed testing in M4 |
| P5 | European Portuguese reviewer | Owner | Reviews strings at the end of M1, M3 and M6 |
| P6 | Field-test parcels: 3 real rural parcels with no mobile signal, ideally with a PT-TM06 survey plan for at least one | Owner | Needed in M2 and M6 |
| P7 | Recruit 12+ beta testers (with Google accounts) | Owner | Start in M2, testing begins at the end of M4 |

---

## 3. Technical Spikes (M0–M3)

Each spike is time-boxed, produces a short decision record in `docs/adr/`, and has a fallback
ready if it fails.

| # | Spike | When | Box | Exit criteria | Fallback |
|---|---|---|---|---|---|
| S1 | **DGT orthophoto service:** find the current mainland series, WMS/WMTS URL, layer, supported CRS and tile format; record the licence and attribution in `docs/data-licences.md` | M0 | 1 d | `flutter_map` shows DGT imagery over a known parcel at z19; download speed with 4 parallel requests is measured | Only EPSG:3763 offered → run the map in that projection with `Proj4Crs` (spec §6.1) |
| S2 | **Nearby Connections:** check whether the `nearby_connections` plugin works on current Android; exchange 1 MB of bytes and a 50 MB file between 2 phones in airplane mode (Bluetooth on) | M0 | 1.5 d | Connects on all 3 phones; ≥ 2 MB/s for the file; runtime permissions work on API 24, 31 and 33+ | Write our own Kotlin platform channel (~300 lines) |
| S3 | **CAOP asset:** simplify the latest mainland CAOP; measure size and point-in-polygon lookup speed | M1 | 1 d | ≤ 8 MB asset; lookup < 5 ms; freguesia borders still look right at z14 | Coarser simplification for the overlay plus a finer copy for lookups only |
| S4 | **PT-TM06 accuracy:** `proj4dart` against PROJ for 50 reference points across the mainland | M0 | 0.5 d | ≤ 1 cm difference in both directions | Implement the Transverse Mercator formulas directly (Karney series) |
| S5 | **Crypto speed in Dart:** Argon2id and AES-GCM on the oldest phone | M3 | 0.5 d | Argon2id ≈ 1 s with sensible parameters; AES-GCM ≥ 20 MB/s, fast enough for a 200 MB backup | PBKDF2-HMAC-SHA256 (600k iterations); native crypto through a platform channel |
| S6 | **Map performance:** 500 polygons / 50 000 vertices in `flutter_map` on the reference phone | M1 | 1 d | 60 fps while panning | Simplify polygons by zoom level, cull by bounding box, cache polygon layers |

---

## 4. Milestones & Tasks

Estimates are in working days (d) for one developer. "Refs" are spec requirement IDs or sections.

### M0 — Foundations (weeks 1–3, 15 d)

| # | Task | Refs | Est. |
|---|---|---|---|
| T0.1 | Repo bootstrap: `flutter create --org pt.terrenos --project-name terrenos --platforms android`; MIT `LICENSE`, `README.md` + `README.pt.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue templates; `.gitignore` covering `key.properties`, `*.jks`, `*.keystore` | §5.3 | 1 |
| T0.2 | Flavours `dev` / `prod` / `foss` (stub); app IDs; release signing read from CI secrets only | §5.2 | 1 |
| T0.3 | CI on GitHub Actions: format, `flutter analyze` (`very_good_analysis`), tests + coverage gates, ARB completeness, dependency licence allow-list scan, gitleaks, `dev` APK artifact | §11, §5.3 | 1.5 |
| T0.4 | App skeleton: feature folders, Riverpod, go_router, Material 3 theme (large text, high-contrast polygon style), bottom navigation shells (Mapa / Terrenos / Grupos / Definições) | §4, §5 | 1.5 |
| T0.5 | Localisation: `app_pt.arb` / `app_en.arb`, runtime language switch, `locales_config` for Android 13+, number, area and date formatting helpers | SET-2, §10 | 1 |
| T0.6 | **CRDT primitives:** persisted HLC, LWW register, LWW map, canonical JSON, SHA-256 hashing, plus property-based tests | §9.1, §9.5.2 | 2 |
| T0.7 | **Property and group document schema v1**, complete (fields incl. `processNumber`, geometry version DAG with vertex objects, `vertexInfo`, attachments, tombstone), freezed models, serialisation, migration hook | §9.5.1, §9.5.4 | 1.5 |
| T0.8 | **File store:** atomic writes, `.bak` recovery, quarantine, loading in a background isolate, in-memory index with Riverpod providers | §8 | 1.5 |
| T0.9 | Device identity and first run: language → device name → onboarding (including the data-loss warning) → location explanation | SET-1, §9.1 | 1 |
| S1, S2, S4 | Spikes | §3 | 3 |

**Exit / demo:** the app installs and runs first-time setup in PT and EN; the empty map shell
shows DGT imagery (S1); CI is green; spike decisions recorded in `docs/adr/`.

### M1 — Map, draw & coordinates (weeks 4–7.5, 21.5 d)

| # | Task | Refs | Est. |
|---|---|---|---|
| T1.1 | CAOP pipeline: `tool/build_caop.dart`, simplified asset, index, `assets/caop/README.md` attribution (includes S3) | §6.2 | 2 |
| T1.2 | Map screen: DGT layer, CAOP overlay, location dot + accuracy circle, centre-on-me, scale bar, compass, attribution (includes S6) | MAP-1–4, MAP-11 | 2 |
| T1.3 | GeometryService: geodesic area and perimeter, polylabel, self-intersection, orientation, simplification, overlap area; tested against reference fixtures | §7.2, §3.5 | 2.5 |
| T1.4 | Coordinate module: PT-TM06 conversion; parse and format decimal degrees, DMS and PT-TM06 with every §7.5 variant; range checks, sign and swap suggestions; typed input preserved exactly | §7.1, §7.5 | 2.5 |
| T1.5 | Vertex operations: add, insert at the nearest edge, move, delete, reorder, reverse; stable IDs; status (planned/surveyed); one geometry version per save | VTX-1, VTX-11, VTX-14 | 1.5 |
| T1.6 | Boundary editor (draw mode): vertex and midpoint handles, loupe, undo/redo, live area and perimeter, snapping, crash-safe drafts | REG-1, 5, 6, 7, 10, 12 | 3 |
| T1.7 | **Vertex table and coordinate entry form** (two fields, ± button, preview pin, inline validation); create a property from coordinates only | VTX-2–5, REG-11 | 3 |
| T1.8 | Validation pipeline and UI | VAL-1–9 | 1 |
| T1.9 | Details form: identifier name and process number rules (trimming, exact storage, duplicate warnings), the Portuguese reference fields (all optional), automatic location from CAOP | §3.6, IDN-1–5, IDN-8, D16 | 1.5 |
| T1.10 | Property list (search, sort, filters), property detail, map bottom sheet, delete with recycle bin | MGT-1, MGT-3, MAP-6, IDN-5–7 | 2 |
| T1.11 | Usability check with paper or screen prototypes, 3 participants | §12 AC1 | 0.5 |

**Exit / demo:**
- Spec acceptance criteria **AC7** (PT ⇄ EN switch), **AC12** (property typed at home from
  PT-TM06), **AC15** (vertex operations with TalkBack) and **AC16** (process number handling).
- First build on the Play **internal** track.
- First European Portuguese review of the strings.

### M2 — Field capture (weeks 7.5–10.5, 15.5 d)

| # | Task | Refs | Est. |
|---|---|---|---|
| T2.1 | `LocationSource`, GPS averaging, mock-location detection; foreground service with notification; location and notification permissions | §7.3, REG-13 | 2.5 |
| T2.2 | Walk mode by points: large "Adicionar ponto" button, accuracy indicator, averaging ring, choice of where to insert | REG-2, VTX-8 | 2 |
| T2.3 | Survey an existing vertex: distance and bearing, Keep / Replace / Repeat, previous coordinates kept in history | VTX-9 | 1.5 |
| T2.4 | Go to vertex: compass arrow, distance, vibration on arrival, "next planned vertex" button | VTX-10 | 1.5 |
| T2.5 | Continuous walk mode: track recording and simplification | REG-3 | 1 |
| T2.6 | BlobStore: content-addressed files, thumbnails, EXIF stripping; photos and documents for properties and markers | PROP-15, PROP-16, VTX-12 | 2 |
| T2.7 | TileStore + file-first tile provider; offline area download (frame the area, size estimate, max 8 parallel requests, resumable) and management | MAP-7, MAP-8, §6.1 | 4 |
| T2.8 | **Field test #1:** one parcel planned at home, then surveyed on site; one walked from scratch | §11 | 1 |

**Exit / demo:** **AC13** (go to vertex and survey on site), **AC2** (airplane mode, zero
network requests, apart from the imagery download). Start recruiting beta testers.

### M3 — Sync core (weeks 10.5–13.5, 15.5 d)

| # | Task | Refs | Est. |
|---|---|---|---|
| T3.1 | **Property merge:** registers, union of geometry versions, heads, tombstones, `vertexInfo`, attachments; convergence tests with 3–5 simulated devices and random sync orders | §9.5 | 3 |
| T3.2 | Groups: create; key generation in Keystore; HKDF subkeys; QR invite (screenshots blocked); scan to join; members list; leave | GRP-1–3, GRP-8, §9.2 | 2.5 |
| T3.3 | Moving properties between groups (`removedProperties`), keeping tombstones, purging content after 30 days | MGT-5, §9.5.5 | 1.5 |
| T3.4 | SyncEngine: protocol steps over `SyncTransport`; loopback transport; tests for cancelling at every step | §9.4 | 2.5 |
| T3.5 | **Sync file:** header and magic bytes, chunked AES-256-GCM, ZIP contents, share-intent receiving, "Import sync file" (includes S5) | GRP-5, §9.7 | 2.5 |
| T3.6 | Sync summary; conflict review with vertex-by-vertex comparison and resolution; flagging duplicate process numbers after sync | GRP-6, GRP-7, IDN-4 | 2.5 |
| T3.7 | Boundary history screen and restore; clock-difference warning | MGT-4, GRP-11 | 1 |

**Exit / demo:** **AC4** (3 phones converge), **AC5** (sync file through WhatsApp, a modified
byte is rejected), **AC6** (deleted properties stay deleted), **AC14** (rename and re-survey at
the same time without a conflict). Second European Portuguese review.

### M4 — Nearby sync (weeks 13.5–15.5, 9.5 d)

| # | Task | Refs | Est. |
|---|---|---|---|
| T4.1 | Nearby transport (plugin or own channel, per S2): advertise, discover, connect, show the auth code; Bluetooth and Wi-Fi permissions for each API level | §9.3, §5.2 | 3 |
| T4.2 | Handshake with HMAC group matching; protocol messages over Nearby; blobs sent as file payloads with hash checks | §9.4 | 2 |
| T4.3 | Sync nearby screens: discovery list, code confirmation, progress, cancel, summary; include or exclude photos; explanation when Google Play Services is missing | GRP-4, GRP-9 | 2 |
| T4.4 | **Device lab round** on the 3 phones: airplane mode, interruptions, performance target | §11 | 2 |
| T4.5 | `foss` flavour without Nearby: check it builds; file sync only | §5.3 | 0.5 |

**Exit / demo:** **AC3** (50 properties + 100 photos in < 3 min). **Start Play closed testing**
(12+ testers, 14 consecutive days).

### M5 — Export, import & backup (weeks 15.5–17.5, 10 d)

| # | Task | Refs | Est. |
|---|---|---|---|
| T5.1 | Export and import GeoJSON and KML/KMZ (including the vertex layer, name and process number); GPX import; review imported names | EXP-1, EXP-4, EXP-5, REG-4, IDN-9, IDN-10 | 2.5 |
| T5.2 | Shapefile writer in PT-TM06 (`.shp/.shx/.dbf/.prj/.cpg`), polygon and vertex layers; checked in QGIS | EXP-2 | 2 |
| T5.3 | PDF report in PT and EN: map snapshot with vertex labels, details, vertex table, attribution, disclaimer | EXP-3 | 2 |
| T5.4 | Vertex CSV import and export; pasting coordinate lists with a preview and per-line errors | VTX-6, VTX-7 | 1.5 |
| T5.5 | Encrypted backup and restore (Argon2id), backup reminder, Android backup rules (no cloud, device transfer allowed) | BAK-1–4 | 2 |

**Exit / demo:** **AC8** (Shapefile and PDF match PROJ, open correctly in QGIS), **AC10**
(backup restored onto a fresh install).

### M6 — Hardening & release (weeks 17.5–19.5, 10 d)

| # | Task | Refs | Est. |
|---|---|---|---|
| T6.1 | Accessibility pass: TalkBack on every flow, 200 % text, golden tests in PT and EN | §10 | 2 |
| T6.2 | Performance and battery: cold start, 500 properties at 60 fps, 1 h of walk mode | §10 | 2 |
| T6.3 | Final European Portuguese review and fixes | §4.2 | 1 |
| T6.4 | **Field test #2** on all 3 parcels + **usability test** with 5 participants aged 50+ | §11, AC1 | 2 |
| T6.5 | Play release: store listing in PT and EN, screenshots, Data Safety ("no data collected"), privacy policy as a static page (GitHub Pages), content rating; GitHub Release with signed APKs | §5.3, AC11 | 1.5 |
| T6.6 | Fix issues found in closed testing | — | 1.5 |

**Exit:** all 16 acceptance criteria pass; apply for production access once the 14-day closed
test is complete; v1.0.0 tagged.

### Buffer (weeks 19.5–21.5)

The buffer is two weeks (10 %), kept at the end and not spread across milestones. The
milestones most likely to need it are M1 (editor UX) and M4 (differences in Nearby behaviour
between phone makers).

---

## 5. Timeline

```
Week        1    3    5    7    9   11   13   15   17   19   21
M0 Found.   ███████████████
M1 Map/Coord               ██████████████████████
M2 Field                                         ███████████████
M3 Sync core                                                    ███████████████
M4 Nearby                                                                      ██████████
M5 Export/Backup                                                                         ██████████
M6 Release                                                                                         ██████████
Buffer                                                                                                       ██████████
Spikes      S1 S2 S4       S3 S6                                S5
Play        ·········internal track from end of M1·········      closed test (≥14 d) ▶ production
Field/UX                          UX₀            F1                                    F2 + UX
PT review                         R1                            R2                     R3
```

Critical path: **M0 document schema → M1 vertex model and editor → M3 merge → M4 Nearby → closed
test (14 days) → production.**

---

## 6. If the Schedule Slips: Scope Tiers

Cut from the bottom tier up. Cutting a Tier C item that an acceptance criterion depends on means
updating that criterion in the spec.

| Tier | Contents | Rule |
|---|---|---|
| **A — never cut** | Every P0: map + offline areas, draw/walk/coordinates editing, vertex table and coordinate entry, GPS survey of a vertex, validation, details incl. name and process number, file storage, groups, sync file, Nearby sync, conflicts, GeoJSON/KML export, backup, PT/EN | Required for v1 |
| **B — cut late** | Go to vertex (VTX-10), Shapefile (EXP-2), PDF (EXP-3), paste and CSV (VTX-6/7), import (REG-4), boundary history (MGT-4), map search (MAP-9) | Move to v1.1 only if the buffer is used up |
| **C — cut first** | Continuous walk mode (REG-3), snapping (REG-7), multi-part properties (REG-8), app lock (SET-7), backup reminder (BAK-3), clock warning (GRP-11), marker photos (VTX-12) | Move to v1.1 |
| **Already v1.1+ (P2)** | Holes (REG-9), offset capture (VTX-13), measuring tool, MBTiles import, sharing offline areas, custom units, removing members, F-Droid publication | Not scheduled |

---

## 7. Working Agreements

**Definition of Done (every task):**
- The code is merged by pull request with CI green: format, analyze, tests, coverage gates, ARB
  completeness, licence scan, secret scan.
- Unit tests are included for logic, and widget tests for new screens.
- All new strings exist in **both** `app_pt.arb` and `app_en.arb`, and every control has a
  TalkBack label.
- The app makes no new network calls outside `TileDownloader` (enforced by a CI test).
- Any change to the document schema includes a migration and a fixture test.
- Decisions are recorded in `docs/adr/`, and the spec is updated if a requirement changed.

**Workflow:**
- GitHub flow: short-lived branches, one PR per task, and conventional commit messages.
- A tag for each milestone (`v0.1.0` = M1 … `v1.0.0` = M6). Each tag builds a signed AAB in CI
  and uploads it to the Play internal track.
- **Nothing is pushed or published without the owner's approval. No credentials in git:**
  keystores and Play service-account JSON live only in CI secrets.

**Quality gates per milestone:** the demo against the listed acceptance criteria, a device lab
run on the 3 phones (from M3 onwards), and the coverage targets (≥ 90 % for `core/sync` and
`core/geometry`, ≥ 80 % overall).

---

## 8. Risks to the Plan

| Risk | Signal | Response |
|---|---|---|
| Spike S1 or S2 fails | Exit criteria not met by the end of M0 | Switch to the fallback in §3; M1 or M4 may grow by up to 3 days, taken from the buffer |
| Editor UX takes longer than estimated | The M1 usability check (UX₀) finds major problems | Spend the buffer on M1 first; move REG-7 and REG-10 to Tier C if needed |
| Nearby behaves differently across phone brands | Failures in the M4 device lab | Ship with sync files as the reliable path and Nearby labelled "beta" if needed |
| Not enough beta testers | Fewer than 12 by the end of M3 | Recruit through local associations or family; this blocks the move to production |
| One developer, so absence stops the work | — | The buffer covers about 2 weeks; ADRs and the spec keep the context so someone else can continue |

---

## 9. First Week

1. Owner: confirm the repository name and visibility and create it on GitHub (P3); order or
   collect the test phones (P2).
2. Dev: install Flutter via FVM (P1) and do T0.1–T0.2. The first push happens only after the
   owner approves.
3. Dev: run spikes **S1** (DGT), **S4** (PT-TM06) and **S2** (Nearby) and write the ADRs.
4. Dev: T0.6–T0.8. The document schema and file store come before any UI, because everything
   else is built on them.
5. Owner: register the Play developer account (P4) and start looking for the PT-PT reviewer (P5)
   and the field-test parcels (P6).
