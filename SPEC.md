# Land Property Registry ("Terrenos") — Product & Technical Specification

| | |
|---|---|
| **Status** | Draft v0.6 |
| **Date** | 2026-10-25 |
| **Platform** | Android (Flutter) |
| **Region** | Mainland Portugal only |
| **Languages** | Português (Portugal) and English, switchable in the app |
| **Licence** | Open source, MIT (§5.3) |
| **Working name** | *Terrenos*; package `pt.terrenos.app` (placeholder) |

### Decisions

v0.1 assumed a cloud backend. The owner has since decided:

| # | Decision |
|---|---|
| D1 | **Fully offline. There is no server.** Each phone stores its own data. The only network use is downloading map imagery, and that is optional. |
| D2 | **No database.** There is no backend database and no local SQL database either. Data is stored as plain JSON files on the phone (§8). |
| D3 | **Phones sync directly with each other**, either in person (Bluetooth/Wi-Fi, no internet needed) or by passing an encrypted sync file through any channel (§9). |
| D4 | **Focused on Portugal.** Portuguese property fields, official coordinate system PT-TM06, DGT orthophotos, and administrative boundaries from CAOP. |
| D5 | **No accounts, no admins, no verification workflow.** |
| D6 | **Free and non-commercial.** No ads, no analytics, no tracking. |
| D7 | **Mainland Portugal only.** Azores and Madeira are out of scope. |
| D8 | **Open source under the MIT licence.** |
| D9 | **Every group member can edit.** There are no read-only members. |
| D10 | **No NIF or other personal identifiers are stored.** |
| D11 | **No BUPi-specific export format.** The standard exports (§3.8) are enough. |
| D12 | **The coordinates of every vertex can be recorded and edited**, both in the field (GPS at the boundary marker) and away from it (typed, pasted, imported, or placed on the map). A boundary can be planned at home and confirmed on site, or the other way round (§3.4). |
| D13 | **DGT orthophotos are the imagery source** (§6.1). |
| D14 | **Only WGS84 and PT-TM06 coordinates.** Older Portuguese systems (Datum 73, Datum Lisboa) are not supported, for input or output. |
| D15 | **Every property has a required identifier name and an optional process number, which is its official ID** (§3.6.1). |
| D16 | **All official references are optional:** process number, artigo matricial, freguesia matricial, descrição predial and secção cadastral (PROP-2, PROP-5 to PROP-8). A property can be saved with none of them. |

---

## 1. Purpose

In rural Portugal many owners don't know exactly where their *prédios* are, especially land that
was inherited and split among relatives. This app lets them record each parcel's boundary on
orthophotos, along with the Portuguese property details (artigo matricial, confrontações, etc.).
A boundary is a list of **vertices**, normally the boundary markers (*marcos*). Each vertex's
coordinates can be captured with GPS while standing on the marker, or entered at home, for
example typed from an old plan or document, or placed on the orthophoto. Families or co-owners
can then share that record directly between their phones, with no internet and no third party
involved.

**The app is not a legal registry.** It is a personal, shareable record. It complements official
processes (Finanças, Conservatória, BUPi) but does not replace them.

### 1.1 Goals

1. A non-technical user can register a property in under 3 minutes, in Portuguese.
2. **Every vertex has explicit coordinates that the user can see, enter and edit.** In the
   field they come from GPS at the marker; away from the field they can be typed (WGS84 or
   PT-TM06), pasted, imported, or placed on the map. A vertex planned at home can later be
   confirmed with GPS on site.
3. **Everything works with no network.** The app never contacts any server except the map
   imagery provider, and only when the user asks to download an area.
4. Two or more phones can keep a shared set of properties in sync, either side by side with no
   internet, or remotely by exchanging a file. Every phone ends up with the same data
   (deterministic merge, §9.5).
5. Areas and perimeters are correct (geodesic), and coordinates can be shown and exported in
   PT-TM06 (EPSG:3763), the system Portuguese technicians use.

### 1.2 Non-goals

- Legal registration, submitting to BUPi, Finanças or the Conservatória, or resolving disputes.
- Any cloud, server, user account or remote backup run by the project.
- Survey-grade accuracy (RTK). The design leaves room for this (§7.4).
- iOS (the phone-to-phone transport depends on Android, §9.3).
- Azores and Madeira (D7).
- Storing NIF or other personal identifiers (D10).
- Export formats tailored to BUPi (D11).
- Older coordinate systems such as Datum 73 or Datum Lisboa (D14).

---

## 2. Users

There are no accounts or roles. Each phone has a **device identity** (§9.1) and a display name
chosen by the user, e.g. "Telemóvel da Maria".

Who can see and edit a property depends only on **groups** (§9.2):

- A property is either **private** (only on this phone) or belongs to **exactly one group**.
- Every member of a group can see and edit all of the group's properties. There are no read-only
  members (D9).

### 2.1 Personas

- **Maria, 68, Trás-os-Montes.** Owns 6 small rustic parcels: olive groves and *mato*. Has an
  Android phone and uses WhatsApp. Has no mobile data on the land. Wants to record the parcels
  so her children know where they are.
- **João, 40, Maria's son in Lisbon.** Inherited part of the land. Visits twice a year and walks
  the boundaries with his mother. Before a visit he types the marker coordinates from a
  PT-TM06 survey plan at home, then confirms each one with GPS on site. Wants the same data on his
  phone, kept up to date.
- **Ana, technician at a local association.** Helps owners record their land. Wants to export a
  Shapefile in PT-TM06 to open in QGIS.

---

## 3. Functional Requirements

Priority: **P0** is required for v1, **P1** should ship in v1, **P2** comes later.

### 3.1 First Run & Settings

| ID | Requirement | Pri |
|---|---|---|
| SET-1 | First launch: choose a language (PT/EN, preselected from the system locale), enter a device display name, then 3 onboarding slides. One slide states clearly that the data stays on this phone and is lost if the phone is lost, unless it is shared with a group or backed up (§3.9) | P0 |
| SET-2 | The language can be switched at any time and takes effect immediately, without a restart. The app also integrates with Android 13+ per-app language settings (`locales_config`) | P0 |
| SET-3 | Units: area in m², ha, or both (default: ha + m²); length in m. | P0 |
| SET-4 | Coordinate display: WGS84 decimal degrees, WGS84 DMS, PT-TM06 (EPSG:3763) | P0 |
| SET-5 | Custom traditional area unit (name + m² per unit), because units such as the *alqueire* vary by region | P2 |
| SET-6 | GPS averaging duration (default 5 s) and accuracy warning threshold (default 15 m) | P1 |
| SET-7 | App lock with the device PIN or biometrics (`local_auth`) | P1 |
| SET-8 | Storage screen: space used by properties, photos and offline maps, with options to delete | P0 |
| SET-9 | About: version, licences, data attributions (DGT, CAOP), privacy statement ("this app collects no data") | P0 |

### 3.2 Map

| ID | Requirement | Pri |
|---|---|---|
| MAP-1 | Full-screen map. Default layer: **DGT orthophotos** (§6.1) | P0 |
| MAP-2 | **Administrative boundaries overlay** (distrito/concelho/freguesia from CAOP) is bundled with the app and works with no download | P0 |
| MAP-3 | The map stays usable before any imagery is downloaded: CAOP boundaries, GPS position, a coordinate grid and the user's properties on a neutral background | P0 |
| MAP-4 | User location (dot + accuracy circle) and a "centre on me" button | P0 |
| MAP-5 | Properties drawn as polygons. Colour is chosen by the user per property, with a default for each group. The name is shown at an interior point | P0 |
| MAP-6 | Tapping a property opens a bottom sheet (identifier name, process number, area, freguesia, group) with Details and Edit actions | P0 |
| MAP-7 | **Download an area for offline use:** the user frames the area, chooses detail level (normal: up to z17, high: up to z19), sees the tile count and estimated size, then downloads. Downloads pause and resume across connection loss and app restarts | P0 |
| MAP-8 | Manage offline areas: list, size, refresh, delete | P0 |
| MAP-9 | Offline search box on the map: the user's properties by name or process number (IDN-6), plus places by freguesia, concelho or distrito name (from CAOP). Accent-insensitive ("sao joao" finds "São João") | P1 |
| MAP-10 | Go to coordinates (WGS84 or PT-TM06) | P1 |
| MAP-11 | Scale bar and compass/north reset | P1 |
| MAP-12 | Measure tool for distance and area, without saving | P2 |
| MAP-13 | Import a user-provided MBTiles imagery file (e.g. one exported from QGIS) as a layer | P2 |
| MAP-14 | Share a downloaded offline area with a nearby phone (§9.3) | P2 |

### 3.3 Boundary Capture

A boundary can be started with any of these methods, and its vertices can be refined with any
other method later. The methods are tools for editing one vertex list (§3.4), not separate kinds
of property.

| ID | Requirement | Pri |
|---|---|---|
| REG-1 | **Draw mode:** tap to add vertices; drag to move; tap a midpoint handle to insert; long-press a vertex to delete. The coordinates of the selected or dragged vertex are shown live in the chosen format | P0 |
| REG-2 | **Walk mode, by points:** the user stands at each corner (*marco*) and taps "Add point". The app averages GPS fixes for N seconds and stores the vertex's accuracy (VTX-8) | P0 |
| REG-3 | **Walk mode, continuous:** records a track (every 2 m or 5 s), then simplifies it (Douglas–Peucker, default 1 m tolerance, adjustable) | P1 |
| REG-4 | **Import** GeoJSON, KML/KMZ or GPX (P1), or a Shapefile .zip in PT-TM06 or WGS84 read from the `.prj` (P2). When a file has several features, the user chooses which ones to import | P1 |
| REG-5 | Undo/redo (at least 50 steps) | P0 |
| REG-6 | Live area and perimeter while editing | P0 |
| REG-7 | Snap to vertices of other properties on the phone (within 10 px), so neighbouring parcels share edges exactly | P1 |
| REG-8 | Multi-part properties (MultiPolygon) | P1 |
| REG-9 | Holes (inner rings) | P2 |
| REG-10 | Magnifier loupe while dragging a vertex | P1 |
| REG-11 | **Coordinates mode:** build the boundary by entering vertex coordinates, with no map interaction needed (VTX-3 to VTX-6) | P0 |
| REG-12 | Crash-safe drafts: every change is written to disk, and an unfinished draft is offered for resume on next launch | P0 |
| REG-13 | Walk mode keeps recording with the screen off (foreground service with a notification) | P0 |

### 3.4 Vertices & Coordinates

Each vertex is a record the user can see and edit, not just a point in a drawn shape. The same
vertex table is available in the field and at home, and it doubles as the accessible
alternative to drawing on the map.

**Viewing and general editing**

| ID | Requirement | Pri |
|---|---|---|
| VTX-1 | Each vertex has a stable ID, a label (automatic `V1`, `V2`…, editable, e.g. "Marco Norte"), coordinates, a **source** (`gps`, `typed`, `map`, `import`), GPS capture details when applicable (§7.3), and an optional note and photos | P0 |
| VTX-2 | **Vertex table** in the property detail and in the editor: order, label, coordinates in the chosen format, source, accuracy, and status. Tapping a row selects that vertex on the map and opens its detail sheet | P0 |
| VTX-11 | **Vertex status:** *planned* (source `typed`, `map` or `import`) or *surveyed* (captured or confirmed with GPS on site). Planned vertices are drawn as hollow markers and surveyed ones as filled. Each property shows its progress, e.g. "5/8 vértices levantados" | P0 |
| VTX-14 | Reorder vertices (drag in the table), reverse the direction, choose the starting vertex. The polygon and validation update live | P1 |
| VTX-15 | Copy a vertex's coordinates in any supported format; open a vertex in an external navigation app (`geo:` link) | P1 |

**Away from the field**

| ID | Requirement | Pri |
|---|---|---|
| VTX-3 | **Type coordinates** to add a vertex or change an existing one. Accepted formats: WGS84 decimal degrees, WGS84 degrees-minutes-seconds, PT-TM06 (M/P in metres). The last format used is remembered. Parsing and validation rules are in §7.5 | P0 |
| VTX-4 | **Place on the map:** tap or drag on the orthophoto (draw mode, REG-1) to set a vertex's coordinates, with the coordinates shown live | P0 |
| VTX-5 | **New property from coordinates only:** create a whole property by typing its vertex list, with a live preview of the polygon, area and perimeter. Works without any imagery downloaded | P0 |
| VTX-6 | **Paste a list** of coordinates, one vertex per line, optionally with a label. Separators can be spaces, commas, semicolons or tabs. The CRS is chosen up front. A preview shows each parsed line, with per-line errors | P1 |
| VTX-7 | Import and export a vertex list as **CSV** (`label;x;y;crs;source;accuracy_m;captured_at`), e.g. to exchange with a spreadsheet | P1 |

**In the field**

| ID | Requirement | Pri |
|---|---|---|
| VTX-8 | **Capture a new vertex** at the current position, using GPS averaging (§7.3). It is added after the selected vertex, at the end, or into the nearest edge, as the user chooses | P0 |
| VTX-9 | **Survey an existing vertex:** select a planned vertex, stand on the marker, capture GPS. The app shows how far and in which direction the measured position is from the stored one (e.g. "3,2 m para nordeste") and asks whether to **replace** the coordinates or **keep** them (marking the vertex as checked). The previous coordinates remain in the boundary history | P0 |
| VTX-10 | **Go to vertex:** distance and a direction arrow from the current position to the selected vertex (GPS + compass), with a vibration when the user is within the GPS accuracy radius. Lets users find markers they planned at home | P1 |
| VTX-12 | **Photo of the marker** attached to the vertex, taken in the app and geotagged | P1 |
| VTX-13 | **Offset capture** when the marker can't be reached (stream, wall, dense *mato*): record the GPS position plus distance and bearing to the marker; the app computes the vertex coordinates | P2 |

### 3.5 Geometry Validation

These rules run on save, on import, and on data received from other phones.

| ID | Rule | Behaviour |
|---|---|---|
| VAL-1 | At least 3 distinct vertices per ring | Block save |
| VAL-2 | No self-intersection | Block save, highlight the crossing segments |
| VAL-3 | 1 m² ≤ area ≤ 10 000 ha | Block save |
| VAL-4 | Ring closure and orientation (RFC 7946) | Fix automatically |
| VAL-5 | Duplicate consecutive vertices | Remove automatically |
| VAL-6 | Vertex outside mainland Portugal's bounding box plus a 50 km buffer | Warn, offering to swap lat/lon or M/P when the swap would put the vertex in Portugal (§7.5) |
| VAL-7 | Overlaps another property on this phone (private or any group) | Warn, show the overlap area in m²; allow save |
| VAL-8 | Walk-mode vertex accuracy > threshold, or GPS reported as mocked | Warn; mark the vertex as low-confidence |
| VAL-9 | More than 5 000 vertices | Block save; offer to simplify |

### 3.6 Property Details (Portugal)

| ID | Field (EN / PT) | Type | Req | Notes |
|---|---|---|---|---|
| PROP-1 | **Identifier name** / *Nome identificador* | text 1–80 | ✔ | The name the user knows the property by and the main label everywhere (map, list, exports), e.g. "Olival do Ribeiro". See §3.6.1 |
| PROP-2 | **Process number (official ID)** / *N.º de processo (identificação oficial)* | text ≤ 40 | | The property's official identifier, e.g. the number of its official registration process. Optional; shown next to the name wherever the property is identified. See §3.6.1 |
| PROP-3 | Property type / *Tipo de prédio* | enum | ✔ | rústico, urbano, misto |
| PROP-4 | Land use / *Uso do solo* | enum | ✔ | olive grove, vineyard, orchard, arable, pasture, forest – eucalyptus, forest – pine, forest – cork/holm oak (*montado*), scrubland (*mato*), built-up, mixed, other |
| PROP-5 | Matrix article / *Artigo matricial* | text ≤ 20 | | e.g. "1234" |
| PROP-6 | Matrix parish / *Freguesia matricial* | text | | May differ from today's freguesia because of the 2013 parish merger |
| PROP-7 | Land registry description no. / *N.º descrição predial* | text ≤ 30 | | Conservatória do Registo Predial |
| PROP-8 | Cadastral section / *Secção cadastral* | text ≤ 20 | | Only in municipalities with geometric cadastre |
| PROP-9 | Location / *Localização* | computed + editable | | Distrito, concelho and freguesia are filled automatically from CAOP using the interior point; the user can change them |
| PROP-10 | Place name / *Lugar / sítio* | text ≤ 80 | | Local name, very common in rural deeds |
| PROP-11 | Boundaries with neighbours / *Confrontações* | 4 × text ≤ 120 | | North, South, East (*Nascente*), West (*Poente*), as written in the *caderneta predial* |
| PROP-12 | Owners / *Titulares* | list of {name, share %} | | Free text. **No NIF or other ID numbers** (data minimisation) |
| PROP-13 | Acquisition date | date | | |
| PROP-14 | Notes / *Observações* | text ≤ 2 000 | | |
| PROP-15 | Photos / *Fotografias* | ≤ 30 | | Taken in the app or picked from the gallery; geotagged photos appear as pins |
| PROP-16 | Documents / *Documentos* | PDF/image, ≤ 20, ≤ 20 MB each | | Caderneta predial, deeds, etc. |
| PROP-17 | Area, perimeter, interior point | computed | | Read-only |
| PROP-18 | Colour, tags | | | Display and filtering |

#### 3.6.1 Identifier name and process number

| ID | Requirement | Pri |
|---|---|---|
| IDN-1 | The **identifier name** is required. It is trimmed, can't be empty or whitespace only, and is limited to 80 characters. Any Unicode letters are allowed (accents, `º`, etc.) | P0 |
| IDN-2 | A name already used by another property on this phone triggers a **warning** ("Já existe um terreno com este nome"), not a block, because two phones can legitimately create the same name before syncing. The list shows the process number or freguesia to tell such properties apart | P0 |
| IDN-3 | The **process number** is optional. It is stored **exactly as typed** (after trimming), because official numbers can contain letters, `/`, `-`, `.` and leading zeros. Allowed characters: letters, digits, space, `/ - . _`. It is always a text field, never a number | P0 |
| IDN-4 | **Duplicate process numbers:** two properties with the same official ID almost always mean a mistake or a duplicate. When saving, if another property on this phone has the same normalised number (case-insensitive, with spaces, `-`, `.`, `/` and `_` removed), the app warns and offers to open that property. Duplicates that arrive through sync are listed in the sync summary (GRP-6) and marked in the list | P0 |
| IDN-5 | **Display:** the name is the title everywhere. The process number appears as a subtitle (`N.º proc. 2023/001234`) in the list, map bottom sheet, property detail header, conflict screens and PDF. When there is none, nothing is shown (no "—" placeholder) | P0 |
| IDN-6 | **Search:** the property list has a search box matching the name (accent- and case-insensitive) or the process number (normalised, also by partial match), with results while typing | P0 |
| IDN-7 | **Copy** the process number with a long-press, for pasting into official websites or messages | P1 |
| IDN-8 | Both fields can be edited at any time, and both sync as ordinary fields (last writer wins, §9.5.2) | P0 |
| IDN-9 | **Exports** carry both fields: GeoJSON `name` and `processNumber`; KML `<name>` and `ExtendedData`; Shapefile DBF `NAME` and `PROC_NUM` (DBF field names are limited to 10 characters); CSV and PDF headers. Exported file names use the name, and the process number when present (`Olival do Ribeiro (2023-001234).kml`, with characters that aren't valid in file names replaced) | P0 |
| IDN-10 | Importing (REG-4) uses a file's name and process number fields when present (GeoJSON `name`/`processNumber`, KML `<name>`, Shapefile `NAME`/`PROC_NUM`). When there is no name, it uses "Terreno importado 1, 2…", and the user is asked to review the names before saving | P1 |

### 3.7 Property Management

| ID | Requirement | Pri |
|---|---|---|
| MGT-1 | List with search (IDN-6), sort (name, process number, area, freguesia, last change) and filters (group, type, land use, concelho/freguesia, tag, has/has no process number) | P0 |
| MGT-2 | Total area, overall and per filter | P1 |
| MGT-3 | Delete. Deleted items go to a recycle bin (*Reciclagem*) for 30 days and can be restored. In a group, a deletion also applies on the other members' phones after they sync | P0 |
| MGT-4 | Boundary history: every boundary version is kept, can be viewed on the map, and can be restored (§9.5.3) | P1 |
| MGT-5 | Move a property between private and a group, or between groups (§9.5.5) | P0 |
| MGT-6 | Navigate to a property: open an external maps app with the interior point as destination | P1 |
| MGT-7 | Copy coordinates (WGS84 / PT-TM06) of the interior point (for vertices see VTX-15) | P1 |
| MGT-8 | Filter the list by survey progress ("has planned vertices"), to plan the next field visit | P1 |

### 3.8 Export & Import (one-way, not sync)

| ID | Requirement | Pri |
|---|---|---|
| EXP-1 | Export one, some or all properties as **GeoJSON** (WGS84) or **KML** (opens in Google Earth) through the Android share sheet or to a user-chosen folder | P0 |
| EXP-2 | Export as a **Shapefile .zip in PT-TM06 (EPSG:3763)** with attributes in the DBF (UTF-8 with a `.cpg` file) | P1 |
| EXP-3 | **PDF report** (PT or EN): map snapshot over the orthophoto with vertex labels, details table, area, **vertex table** (label, PT-TM06 M/P, WGS84 lat/lon, source, status, GPS accuracy, capture date), data attribution, and a "not a legal document" disclaimer | P1 |
| EXP-5 | Exports include the vertex details: in GeoJSON as a `vertices` array in the feature properties; in KML and Shapefile as an extra point layer of labelled vertices with their attributes | P1 |
| EXP-4 | Importing a GeoJSON/KML/Shapefile creates **new private properties** (§3.3 REG-4). It never merges with existing ones; merging is what sync is for | P1 |

### 3.9 Backup & Phone Migration

The data exists only on the phone, so backup is the user's responsibility. The app makes it easy:

| ID | Requirement | Pri |
|---|---|---|
| BAK-1 | **Full backup file:** all properties (private and group), group memberships and keys, settings, and optionally photos and documents. Encrypted with a user-chosen password (§9.7) and saved through the Android file picker (SD card, USB, or a cloud folder of the user's choice) | P0 |
| BAK-2 | Restore from a backup file. It merges with existing data using the sync merge rules, so restoring never overwrites newer data | P0 |
| BAK-3 | Reminder when there are private properties and no backup in the last 30 days. Dismissible, can be turned off | P1 |
| BAK-4 | Android backup rules: **exclude cloud backup** (no data goes to Google Drive automatically) and **allow device-to-device transfer** (cable or Wi-Fi migration to a new phone). Group keys live in the Keystore and don't survive a transfer, so the user re-joins groups or restores a backup file (shown in the UI) | P0 |

### 3.10 Groups & Sync

The requirements are summarised here; the design is in §9.

| ID | Requirement | Pri |
|---|---|---|
| GRP-1 | Create a group (name, colour) | P0 |
| GRP-2 | Invite to a group by showing a **QR code**, which another phone scans to join. Warning on screen: "Anyone who scans this code can see and change all properties in this group." | P0 |
| GRP-3 | Members list: the device names seen in the group and when this phone last synced with each | P0 |
| GRP-4 | **Sync nearby:** two phones side by side, no internet needed (Bluetooth/Wi-Fi via Nearby Connections). One tap on each phone, then confirm the 4-digit code shown on both | P0 |
| GRP-5 | **Sync by file:** create an encrypted sync file for a group and send it by WhatsApp, email, USB, etc. The recipient opens it in the app (share intent or "Import sync file") and it merges | P0 |
| GRP-6 | Sync summary afterwards: properties received, updated and deleted, plus any boundary conflicts to review | P0 |
| GRP-7 | Boundary conflict review screen: shows both versions over the orthophoto; the user picks one (or edits a merged one) | P0 |
| GRP-8 | Leave a group: the user chooses to keep local private copies of its properties or delete them | P0 |
| GRP-9 | Option to include or exclude photos and documents in a sync (per sync and as a default), to keep sync files small | P1 |
| GRP-10 | Remove a member (rotate the group key, §9.6) | P2 |
| GRP-11 | Warn when the other phone's clock is more than 24 h different from this one | P1 |

---

## 4. Screens & Navigation

```
Splash ─▶ (first run) Language ─▶ Device name ─▶ Onboarding ─▶ Location primer
                                                                     │
                 ┌───────────────────────────────────────────────────┘
                 ▼
     ┌──────── Home (bottom navigation) ─────────────┐
     │  Mapa  │  Terrenos  │  Grupos  │  Definições  │
     └───┬────┴─────┬──────┴────┬─────┴──────────────┘
         │          │           │
         │          │           ├─ Create group
         │          │           ├─ Join group (scan QR)
         │          │           └─ Group detail ─┬─ Invite (show QR)
         │          │                            ├─ Sync nearby ─▶ Discover ─▶ Confirm code ─▶ Progress ─▶ Summary
         │          │                            ├─ Send sync file / Import sync file
         │          │                            ├─ Members
         │          │                            └─ Conflicts ─▶ Conflict review
         │          │
         │          └─ Property detail ─┬─ Edit details
         │                              ├─ Edit boundary
         │                              ├─ Vertices (table) ─┬─ Vertex detail ─┬─ Edit coordinates
         │                              │                    │                 ├─ Survey with GPS
         │                              │                    │                 ├─ Go to vertex
         │                              │                    │                 └─ Marker photos
         │                              │                    ├─ Add vertex (type / map / GPS)
         │                              │                    └─ Paste list / Import CSV / Export CSV
         │                              ├─ Boundary history
         │                              ├─ Photos / Documents
         │                              └─ Export / Move to group / Delete
         │
         ├─ FAB "+ Novo terreno" ─▶ Method (Draw / Walk / Coordinates / Import) ─▶ Boundary editor
         │                              ─▶ Validation ─▶ Details form ─▶ Saved
         └─ Offline areas ─▶ Frame area ─▶ Estimate ─▶ Download progress
```

### 4.1 Key screen notes

- **Boundary editor:** full-screen map; a top bar with live area/perimeter; a bottom toolbar with
  Undo, Redo, Delete vertex and Finish. In walk mode there is a ≥ 72 dp "Adicionar ponto" button,
  a GPS accuracy indicator (green < 5 m, amber 5–15 m, red > 15 m, plus the number shown so colour
  is not the only cue), and a progress ring while averaging. A toggle switches between the map
  and the vertex table without leaving the editor.
- **Vertex table:** one row per vertex: label, coordinates, a source icon (GPS, keyboard, map,
  file), and a hollow or filled marker for planned/surveyed. Shows "5/8 levantados" at the top.
  In the field, a sticky "Levantar próximo vértice" button selects the next planned vertex and
  opens Go to vertex.
- **Coordinate entry form (VTX-3):** a format selector (Graus decimais · GMS · PT-TM06), then
  **two separate fields** (Latitude/Longitude, or M/P), never a single free-text field. The
  numeric keyboard is used, with a **± button** because many Android number keyboards have no
  minus key. A live preview pin moves on a small map as the user types. Validation errors appear
  inline (§7.5).
- **Survey a vertex (VTX-9):** a large map centred on the vertex, the GPS accuracy indicator and
  averaging ring, and then a result card: "Medido a 3,2 m para nordeste da posição guardada ·
  precisão ±4 m", with the buttons [Substituir] [Manter] [Repetir].
- **Details form:** the first two fields are **Nome identificador** (required) and **N.º de
  processo** (optional, with the hint "Identificação oficial do terreno"). Type and Land use are
  the only other required fields. The other official references (artigo matricial, freguesia
  matricial, descrição predial, secção cadastral) are optional, in the collapsed *Registo*
  section. Location fields are filled in automatically. Portuguese fields come first; optional sections (*Registo*, *Confrontações*,
  *Titulares*) are collapsed by default.
- **Sync nearby:** both phones show the other's device name and the same 4-digit code. Each user
  taps "Confirmar". During sync a progress bar shows "Terrenos 12/40 · Fotografias 3/25".
  Cancelling is safe at any point, because each property is applied atomically (§8.3).

### 4.2 UX principles

- Material 3 with large text defaults (many users are older). Touch targets ≥ 48 dp, and ≥ 56 dp
  for primary map actions. A high-contrast polygon style for use in sunlight.
- European Portuguese terminology throughout ("telemóvel", "ecrã", "transferir"), never Brazilian
  Portuguese. A native PT-PT speaker reviews all strings.
- Plain language, no jargon in the main flows ("Partilhar com a família", not "Sincronizar
  grupo CRDT").
- Every destructive action can be undone (snackbar) or needs confirmation.

---

## 5. Architecture

```
┌──────────────────────────── Flutter app ─────────────────────────────┐
│ Presentation: widgets, go_router                                      │
│ State: Riverpod                                                       │
│ Domain (pure Dart): entities, GeometryService, CRS (PT-TM06),         │
│                     CRDT merge, HLC, validation                       │
│ Data:                                                                 │
│   PropertyStore ── JSON files (atomic writes) + in-memory index       │
│   BlobStore ────── content-addressed photo/document files             │
│   TileStore ────── offline map tiles as files                         │
│   KeyStore ─────── group keys in Android Keystore (secure storage)    │
│ Sync:                                                                 │
│   SyncEngine (transport-agnostic protocol, §9.4)                      │
│   ├─ NearbyTransport (Nearby Connections, platform channel)           │
│   └─ FileTransport (encrypted sync files)                             │
└───────────────────────────────────────────────────────────────────────┘
        │ (optional, only when downloading imagery)
        ▼
   DGT orthophoto service (WMS/WMTS)
```

Folders are organised by feature (`lib/features/<feature>/{data,domain,presentation}`), with shared
code in `lib/core/`. The domain layer and the sync engine are pure Dart with no Flutter
dependency, so they can be fully unit-tested.

### 5.1 Tech stack

| Concern | Choice | Notes |
|---|---|---|
| Framework | Flutter stable, Dart 3 | |
| Map | `flutter_map` + `latlong2` | Supports WMS/WMTS, custom tile providers and polygon editing |
| Offline tiles | **In-house file-based tile cache** (`tiles/<layer>/<z>/<x>/<y>.jpg`) plus a `TileProvider` that checks files first | No database (D2). `flutter_map_tile_caching` is also ruled out: it stores tiles in a database and is GPL-licensed, which doesn't fit an MIT app |
| Location | `geolocator` | Streams, accuracy, `isMocked`, foreground service |
| Compass | `flutter_compass` | Direction arrow in Go to vertex (VTX-10) |
| Geometry | `turf` (turf_dart) + in-house `GeometryService` | Geodesic area/length, simplification, intersections, polylabel |
| Projections | `proj4dart` | WGS84 ⇄ PT-TM06 (EPSG:3763) |
| State | `flutter_riverpod` (+ generator) | |
| Routing | `go_router` | |
| Models | Hand-written immutable classes for synced documents | Exact JSON shape matters for hashing ([ADR 0001](docs/adr/0001-hand-written-document-models.md)) |
| Storage | `path_provider`, `dart:io` | JSON files (§8) |
| Secrets | `flutter_secure_storage` | Group keys in Keystore-backed storage |
| Crypto | `cryptography` | AES-256-GCM, HKDF, HMAC-SHA256, Argon2id, SHA-256 |
| P2P | Google **Nearby Connections** API through a thin Kotlin platform channel, or the `nearby_connections` plugin if it is maintained and current at project start | Requires Google Play Services (§13) |
| QR | `qr_flutter` (show) and `mobile_scanner` (scan) | |
| Files | `file_picker`, `share_plus`, `archive` (ZIP/KMZ), `xml` (KML/GPX), and an incoming share intent handler | |
| PDF | `pdf` + `printing` | |
| Media | `image_picker`, `native_exif` | |
| i18n | `flutter_localizations`, `intl`, ARB files `app_pt.arb` and `app_en.arb` | |
| App lock | `local_auth` | |
| IDs | `uuid` (v7) | |

**No analytics, crash reporting or remote-config SDKs.** Crashes are written to a local log
file. The user can choose to share it through the share sheet from the About screen.

### 5.2 Android configuration

- `minSdk` 24, `targetSdk`/`compileSdk` set to what Google Play currently requires.
- Permissions, each requested in context when first needed:
  - Location: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`.
  - Walk mode: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS` (API 33+).
  - Nearby sync: `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT` (API 31+);
    `NEARBY_WIFI_DEVICES` (API 33+); `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`; and, on API ≤ 30,
    the legacy `BLUETOOTH`/`BLUETOOTH_ADMIN` permissions plus fine location.
  - QR scanning: `CAMERA`.
  - Imagery download only: `INTERNET`, `ACCESS_NETWORK_STATE`.
  - **No background location, no storage permissions** (the Storage Access Framework and photo
    picker are used instead).
- `android:dataExtractionRules`: cloud backup excluded, device transfer included (BAK-4).
- Intent filter for opening sync and backup files shared from other apps. Received files are
  identified by their **magic bytes** (§9.7), not by file extension, because WhatsApp and email
  content URIs often drop the extension.
- R8 on; release as an App Bundle (AAB) with Play App Signing.
- Flavours: `dev` and `prod`, with different app IDs so both can be installed side by side for
  sync testing. A `foss` flavour without Google Play Services is planned (§5.3).

### 5.3 Open source & distribution

- **Licence: MIT** (D8). It is permissive, so anyone can reuse the code, including in other
  projects. It is also compatible with the proprietary Google Play Services Nearby library used
  in the `prod` flavour.
- **No copyleft dependencies** (GPL, AGPL, LGPL): they would force the distributed app under
  their terms. Allowed: MIT, BSD, Apache-2.0, Zlib, MPL-2.0 (file-level copyleft only, so
  acceptable when unmodified). CI enforces this with a licence scan of `pubspec.lock` and the
  Android dependencies, and a new licence needs an explicit allow-list change in review.
- **Data licences are separate from the code licence.** DGT orthophotos and CAOP are DGT open
  data with attribution requirements (each dataset version's licence is recorded in
  `docs/data-licences.md`). The attribution requirements apply to the app's About screen, the
  map and PDF exports. Neither dataset's files are committed to the repository, apart from the derived and
  simplified CAOP asset, which carries its attribution in `assets/caop/README.md`.
- **Public repository** with `LICENSE`, a `README` in PT and EN, `CONTRIBUTING.md`, a code of
  conduct, issue templates (bug report, translation, feature request) and a `SECURITY.md`
  describing how to report vulnerabilities privately.
- **No secrets in the repository.** The app needs no API keys (DGT imagery needs none). The
  release keystore and Play upload key are kept outside the repo and provided to CI only as
  encrypted secrets. A `.gitignore` covers `key.properties`, `*.jks` and `*.keystore`, and CI
  runs secret scanning (e.g. gitleaks) on every push.
- **Reproducible and checkable builds:** dependencies pinned in `pubspec.lock`, Flutter version
  pinned (FVM or `.flutter-version`), release builds made in CI from tagged commits.
- **Distribution:**
  - Google Play (`prod` flavour). Free, no in-app purchases.
  - Signed APKs attached to GitHub Releases.
  - **F-Droid** (P2): F-Droid doesn't accept Google Play Services, so a `foss` flavour leaves out
    Nearby Connections and syncs only by file. The Nearby code sits behind the `SyncTransport`
    interface and a flavour-specific registration, so this costs little.
- **Translations:** the ARB files are the source. Other contributors may later add languages,
  but v1 ships PT-PT and EN only.

---

## 6. Map Data

### 6.1 Imagery: DGT orthophotos

- Source: the most recent **Ortofotomapas** of mainland Portugal from the Direção-Geral do
  Território (DGT): 25–50 cm pixels, served over OGC WMS/WMTS. The service URL, layer name and
  supported tiling CRS are pinned down in a **technical spike at the start of M1**. Preferred:
  WMTS or WMS in EPSG:3857 (the `flutter_map` default). If the service offers only PT-TM06
  (EPSG:3763), the map runs in EPSG:3763 using `flutter_map`'s custom CRS support (`Proj4Crs`),
  and the tile cache and offline-area tile maths use that grid instead.
- Use is approved (D13). The licence terms of the exact series used are recorded in
  `docs/data-licences.md` (DGT's open orthophoto series are published under CC BY 4.0).
  Attribution "© DGT" is shown on the map and in PDF
  exports.
- Being a good citizen of a public service: at most 4 concurrent requests, an identifiable
  `User-Agent` (`Terrenos/<version> (+contact)`), exponential backoff on errors, and a limit of
  50 000 tiles per offline area.
- Typical size: 1 km² down to z19 ≈ 400 tiles (≈ 290 at z19 plus lower zooms) ≈ 10–15 MB. Most smallholdings fit easily.
- Fallback: if DGT can't be used, any CC BY or public-domain imagery service, configured in one
  place (`core/map/layers.dart`).

### 6.2 Administrative boundaries: CAOP (bundled)

- **CAOP** (Carta Administrativa Oficial de Portugal, DGT, latest edition) for mainland Portugal
  (*Continente*): distritos, concelhos, freguesias.
- Prepared at build time with a script (`tool/build_caop.dart` or mapshaper): reprojected to
  WGS84, simplified (~10 m tolerance), and stored as a compact GeoJSON asset with a precomputed
  bounding-box index. Budget: ≤ 8 MB in the APK.
- Used for: the map overlay, filling in location fields automatically (point-in-polygon on the
  property's interior point), and offline place search.
- Attribution in About, with the CAOP edition year.

---

## 7. Geometry, Coordinates & GPS

### 7.1 Storage

- CRS **WGS84 (EPSG:4326)**, `[lon, lat]` per RFC 7946, 7 decimal places (~1 cm).
- A boundary is stored as **parts → rings → vertex objects** (a MultiPolygon in which each
  position is a vertex record with an ID, §9.5.1). Rings are stored open; closure is implicit.
  GeoJSON, KML and Shapefile geometry are derived from this when exporting.
- **The typed value is kept exactly.** When a vertex is typed in PT-TM06 or DMS, the original
  input is stored next to the converted WGS84 value (`input: {crs, x, y}`). It is shown back
  unchanged whenever the display format matches, so "M -41 234,56" never turns into "-41 234,55"
  through rounding. If the vertex is later moved by other means, `input` is cleared.
- Area, perimeter, interior point and bounding box are computed on load and cached in memory.
  They are never stored in synced documents, so they can't drift.

### 7.2 Computations

- **Area/perimeter:** geodesic on the WGS84 ellipsoid. A test checks them against reference
  values from PROJ/GeographicLib to within 0.05 %.
- **PT-TM06:** EPSG:3763 (ETRS89 / Portugal TM06) through `proj4dart`. Tested against reference
  points converted with PROJ (≤ 1 cm difference). ETRS89 and WGS84 are treated as identical,
  which is well below phone GPS accuracy.
- **Interior point:** polylabel, so the label and the CAOP lookup always land inside the parcel.
- Unit conversion happens only in the presentation layer.

### 7.3 GPS vertex capture (walk mode, VTX-8, VTX-9)

- Stream at highest accuracy, 1 Hz. Per vertex: collect fixes for N seconds, drop fixes with
  accuracy above twice the median, then take the accuracy-weighted mean.
- Stored with the vertex as `gps`: `acc` (estimated horizontal accuracy, m), `n` (fixes used),
  `at` (capture time), `mocked`, and `dev` (ID of the device that captured it).
- **Survey of an existing vertex (VTX-9):** the app computes the geodesic distance and bearing
  from the stored position to the measured one. If the distance is within the measured accuracy,
  the default suggestion is *Keep* (confirm only), otherwise *Replace*. Either way the vertex
  becomes *surveyed* and gets the `gps` record.
- Warn when the battery is below 15 % before starting.
- Onboarding sets expectations: phone GPS is typically accurate to 3–10 m. Draw mode over the
  orthophoto can be more precise when the parcel's limits are visible. That is why vertices from
  any source can be mixed and refined later.

### 7.4 Extensibility

`LocationSource` is an interface, so an external Bluetooth GNSS receiver (NMEA) can be added later.

### 7.5 Coordinate input and validation (VTX-3, VTX-6, VTX-7)

**Formats accepted**

| Format | Example | Notes |
|---|---|---|
| WGS84 decimal degrees | Lat `41.1583500`, Lon `-8.6285000` | Up to 7 decimals stored; more are rounded |
| WGS84 DMS | `41°09'30.06"N`, `8°37'42.60"W` | Accepts `°`/`º`, `'`/`’`/`′`, `"`/`”`/`″`, spaces in place of symbols, hemisphere letters before or after the value, and **`O` (Oeste) as well as `W`**. Seconds to 0.01″ |
| PT-TM06 (EPSG:3763) | M `-41234.56`, P `164321.78` | Metres to 0.01 m. Labelled **M** (easting) and **P** (northing), as on Portuguese plans; the help text also shows X/Y |

**Parsing rules**

- Both `,` and `.` are accepted as the decimal separator in a single-value field. Thousands
  separators (spaces, or `.` in PT style when unambiguous) are ignored.
- In pasted lists (VTX-6), the field separator is detected per paste: tab, `;`, or whitespace.
  If decimals use `,`, a comma can't also be the field separator. Such a line is shown as
  ambiguous and the user is asked to choose.
- An optional first column with a non-numeric value is read as the vertex label.

**Validation (inline, as the user types)**

| Check | Behaviour |
|---|---|
| Value out of range (lat ∉ [-90, 90], lon ∉ [-180, 180], minutes/seconds ≥ 60) | Error; can't save |
| Outside mainland Portugal (bbox lat 36.9–42.2, lon -9.6 to -6.1, plus a 50 km buffer; for PT-TM06 the same box converted) | Warning (VAL-6) |
| Positive longitude in DD entered where the result would be in Spain or the sea, and the negative value would be in Portugal | Suggest "Did you mean −8.628500 (Oeste)?". Mainland Portugal lies entirely west of Greenwich, so this is a common slip |
| Lat/lon or M/P apparently swapped | Suggest swapping |
| Vertex identical to the previous or next vertex | Warning (it would be removed, VAL-5) |
| New vertex makes the boundary self-intersect | Highlight it, offer the nearest valid insertion point (VAL-2) |

---

## 8. Local Storage (no database)

### 8.1 Layout

All data lives in the app's private directory (`getApplicationSupportDirectory()`):

```
<app>/
├── device.json                 # deviceId, display name, HLC state
├── settings.json
├── groups/<groupId>.json       # group document (CRDT, §9.5.4); key is in KeyStore, not here
├── properties/<propertyId>.json  # property document (CRDT, §9.5)
├── drafts/<draftId>.json       # in-progress boundary edits
├── blobs/<sha256>              # photos/documents, content-addressed
├── thumbs/<sha256>.jpg         # 512 px thumbnails
├── tiles/<layer>/<z>/<x>/<y>.jpg
├── tiles/areas.json            # offline area definitions
├── quarantine/                 # files that failed to parse (never silently deleted)
└── logs/crash.log
```

### 8.2 Loading

- On start, all `properties/*.json` and `groups/*.json` files are read into memory and the
  derived values are computed. Budget: 1 000 properties load in < 1 s on the reference device,
  parsed in a background isolate.
- The UI reads from the in-memory index (Riverpod providers). Viewport queries use the cached
  bounding boxes.

### 8.3 Writing

- **Atomic writes:** write `<file>.tmp`, flush, rename over the target. Each property file is
  written independently, so a crash or cancelled sync can never leave a half-written property.
- The previous version is kept as `<file>.bak` until the next successful write. If a parse fails
  on load, the app tries `.bak`, moves the bad file to `quarantine/`, and tells the user.
- Every document has a `schema` version. Migrations happen on read; the file is written back in
  the new schema on its next save.
- Blobs are immutable: written once, named by their SHA-256. Unreferenced blobs are
  garbage-collected 30 days after the last reference disappears.

---

## 9. Phone-to-Phone Sync

### 9.1 Device identity

- On first run, the app generates a random 128-bit **deviceId**, stored in `device.json`.
  "Telemóvel da Maria" is only a label for display.
- Each device keeps a **Hybrid Logical Clock (HLC)**. Timestamps look like
  `<epochMillis:13>:<counter:4>:<deviceId>` and sort correctly as plain strings. The HLC is
  persisted on every change. When a remote timestamp is received, the local HLC advances past it,
  so the next local edit always wins over anything already seen. This works even if a phone's
  clock is wrong.

### 9.2 Groups

- A group is `{groupId (UUID), groupKey (32 random bytes)}` plus a synced group document (name,
  colour, members, removals).
- **Having the key is membership.** No server issues it; it is passed on by QR code (GRP-2):

  ```
  terrenos://join?v=1&g=<groupId>&n=<url-encoded name>&k=<base64url key>
  ```

- Subkeys are derived with HKDF-SHA256: `encKey` (sync files) and `authKey` (nearby handshake).
- A property belongs to at most one group (`groupId` field, or `null` = private).

### 9.3 Transports

| Transport | When | How |
|---|---|---|
| **Nearby** (P0) | Phones in the same place, no internet needed | Google Nearby Connections with the `P2P_POINT_TO_POINT` strategy (Bluetooth for discovery, Wi-Fi Direct/hotspot for bulk transfer). Built-in UKEY2 encryption; the users compare the 4-digit authentication code. Typical rate is several MB/s |
| **Sync file** (P0) | Phones far apart | An encrypted file (§9.7) sent through any channel the user already uses (WhatsApp, email, USB cable, Bluetooth file share) |

Both transports run the same sync protocol (§9.4) over a `SyncTransport` interface. Tests use an
in-memory loopback transport.

### 9.4 Protocol

**Nearby session (interactive, both directions):**

1. **Hello:** both sides exchange `{protocol: 1, appVersion, deviceId, deviceName, nonce (16 B)}`.
   A side with a newer protocol uses the older one if it can; otherwise it shows "Update the app
   on the other phone".
2. **Group matching (without revealing which groups each phone belongs to):** each side sends,
   for every group it holds, `HMAC(authKey_g, nonce_A ‖ nonce_B ‖ role)`. Each side computes the
   same for its own groups. A match means a shared group. Unmatched groups are never named.
3. For each shared group, both sides exchange the **group document** and an **index**:
   `[{propertyId, docHash}]` for every property in the group, including tombstones. `docHash` is
   the SHA-256 of the canonical JSON (sorted keys, no whitespace).
4. Each side requests the documents whose hash differs or that it doesn't have, and sends the
   ones requested. Each received document is **merged** (§9.5), validated (§3.5), and written
   atomically. Because the merge is deterministic, both sides end with identical documents.
5. **Blobs:** each side lists the referenced blob hashes it is missing. Thumbnails are always
   sent; originals only if GRP-9 allows. The peer sends them as Nearby file payloads. Each blob
   is checked against its SHA-256 before it is stored.
6. **Done:** both record `lastSync[peerDeviceId]` and show the summary (GRP-6).

**Sync file (one direction, full state):** contains the group document, **all** property
documents of the group (including tombstones) and, optionally, blobs. The receiver runs steps 4–6
locally. Sending everything (no deltas) is deliberate: the sender can't know what the recipient
already has, and property documents are small (typically < 50 KB each).

Importing the same sync file twice changes nothing (it is idempotent). Importing an older sync
file never overwrites newer data.

### 9.5 Data model & merge rules (CRDT)

Each synced document is a state-based CRDT. Merging is commutative, associative and idempotent,
so **any order of syncs between any set of phones ends in the same state.**

#### 9.5.1 Property document

```jsonc
{
  "schema": 1,
  "id": "01929f3a-7c1e-7b2a-9d4e-3f5a6b7c8d9e",       // UUIDv7, never changes
  "createdBy": "d-7f3a91c2…",
  "createdAt": "1729852920000:0000:d-7f3a91c2…",
  "group":   { "v": "g-5b2e…", "t": "<hlc>" },        // null = private
  "deleted": { "v": false,     "t": "<hlc>" },
  "fields": {                                          // one LWW register per field
    "name":           { "v": "Olival do Ribeiro", "t": "<hlc>" },
    "processNumber":  { "v": "2023/001234",       "t": "<hlc>" },   // null when not set
    "type":           { "v": "rustico",           "t": "<hlc>" },
    "landUse":        { "v": "olive_grove",       "t": "<hlc>" },
    "matrixArticle":  { "v": "1234",              "t": "<hlc>" },
    "confrontations": { "v": { "n": "Caminho público", "s": "José Silva", "e": "Ribeiro", "w": "Herdeiros de A. Costa" }, "t": "<hlc>" },
    "owners":         { "v": [ { "name": "Maria Fernandes", "share": 100 } ], "t": "<hlc>" }
    // … every field from §3.6
  },
  "geometry": {                                        // grow-only version DAG, see 9.5.3
    "versions": {
      "<sha256 of canonical JSON of {parts, parents, t}>": {
        "parents": [ "<sha256>" ],                     // [] for the first version
        "t": "<hlc>",
        // parts → rings → vertices; rings are open (closure implicit)
        "parts": [ [ [
          { "id": "a1f3", "lon": -8.6291000, "lat": 41.1579000, "src": "gps",
            "gps": { "acc": 3.8, "n": 5, "at": "2026-10-25T10:12:44Z", "mocked": false, "dev": "d-7f3a…" } },
          { "id": "b7c2", "lon": -8.6280000, "lat": 41.1579000, "src": "typed",
            "input": { "crs": "EPSG:3763", "x": -41234.56, "y": 164321.78 } },
          { "id": "c9d0", "lon": -8.6280000, "lat": 41.1588000, "src": "map" },
          { "id": "e4a8", "lon": -8.6291000, "lat": 41.1588000, "src": "import" }
        ] ] ]
      }
    }
  },
  "vertexInfo": {                                      // LWW map keyed by vertex id; descriptive only
    "a1f3": { "v": { "label": "Marco Norte", "note": "Pedra com cruz gravada",
                     "photos": [ "<attId>" ] }, "t": "<hlc>" }
  },
  "attachments": {                                     // LWW map keyed by attachment id
    "<attId>": { "v": { "kind": "photo", "sha256": "…", "mime": "image/jpeg", "size": 2310044,
                        "caption": "Marco Norte", "lat": 41.1583, "lon": -8.6285 },
                 "t": "<hlc>" }                       // v = null means removed
  }
}
```

- **Vertex IDs** are random 4–8 hex characters, unique within the property. They stay the same
  when a vertex is moved, re-surveyed or reordered, so labels, notes and photos stay attached.
  A deleted vertex's ID is never reused.
- **Coordinates, source and GPS record are part of the geometry version**, because they define
  the boundary. **Label, note and photos are in `vertexInfo`**, a separate LWW map, so renaming a
  marker on one phone while someone else re-surveys it on another doesn't cause a boundary
  conflict.
- **Status is derived, not stored:** a vertex with a `gps` record is *surveyed*; otherwise it is
  *planned*.

#### 9.5.2 Registers (all fields, `group`, `deleted`, `vertexInfo`, attachments)

**Last-writer-wins by HLC.** HLC values never tie, because they include the deviceId. Edits to
attributes are merged silently, field by field: if Maria changes the name and João changes the
notes, both edits are kept.

#### 9.5.3 Geometry: version DAG with conflict detection

Boundaries are the most valuable data, so they are **never silently overwritten**:

- Every saved boundary adds a version whose `parents` list the version(s) it was edited from.
- Merging is the **union** of the versions (a grow-only set keyed by hash).
- **Heads** are versions that no other version lists as a parent.
  - One head: that is the current boundary.
  - Two or more heads: the boundary was edited concurrently on different phones, so there is a
    **conflict**. The app shows the head with the highest HLC as current, marks the property
    with ⚠ and lists it in the group's Conflicts screen (GRP-7).
- **Resolving** creates a new version whose `parents` are all current heads. This removes the
  conflict on every phone once they sync.
- Restoring an old version (MGT-4) creates a new version with that geometry and the current head
  as parent.
- The conflict review screen also compares **vertex by vertex**, matching by vertex ID: it lists
  vertices that moved (with the distance between versions), were added, or were removed. The
  user can build the resolved boundary by choosing per vertex. A typical case: Maria re-surveyed
  V3 in the field while João corrected V5 by typing coordinates at home; the user takes both
  changes.
- Growth: about 10–20 KB per version for a typical parcel. Pruning is out of scope for v1.
  Fine-grained edits (moving a single vertex) are grouped: an editing session creates one
  version when the user taps Save, not one per change.

#### 9.5.4 Group document

```jsonc
{
  "schema": 1,
  "id": "g-5b2e…",
  "name":   { "v": "Família Fernandes", "t": "<hlc>" },
  "colour": { "v": "#2E7D32",           "t": "<hlc>" },
  "members": {                                         // LWW map, deviceId → info
    "d-7f3a…": { "v": { "name": "Telemóvel da Maria", "joinedAt": "<hlc>" }, "t": "<hlc>" }
  },
  "removedProperties": {                               // properties moved out of the group
    "<propertyId>": "<hlc>"
  }
}
```

#### 9.5.5 Moving and deleting

- **Delete:** sets `deleted = true`. The document becomes a **tombstone**. After 30 days the
  geometry versions and attachments are stripped locally, but the tombstone (`id`, `group`,
  `deleted`) is **kept permanently** (< 200 bytes), so an old copy on another phone can't bring
  the property back. Restoring sets `deleted = false` with a newer HLC.
- **Move from group A to group B or private:** sets the `group` register and adds
  `removedProperties[id] = hlc` to group A's document. When A's members sync with each other, a
  phone holding an older copy with `group = A` sees the newer removal and deletes its local copy
  (with a note in the sync summary). The property then syncs only within B. A property moved
  back later gets a newer `group` timestamp, which wins over the removal.

#### 9.5.6 Clock safety

The HLC copes with wrong phone clocks. In addition, if a peer's physical clock differs from the
local clock by more than 24 h, both users see a warning (GRP-11), because LWW decisions between
edits made before the sync may not match what users expect.

### 9.6 Security model & limits

- **The group key is a shared secret.** Anyone holding it can read and modify the group's data.
  The QR code must only be shown in person; the UI says so, and screenshots of the invite screen
  are blocked (`FLAG_SECURE`).
- Nearby: transport encryption by Nearby (UKEY2) plus mutual proof of the group key (§9.4, step 2).
  The 4-digit code comparison protects against a nearby attacker in the middle of the
  connection.
- Sync files: authenticated encryption with the group key (§9.7). Tampered files, or files for a
  group this phone isn't in, are rejected with a clear message.
- **Limits, stated in the app and in this spec:** once data has been shared, it can't be taken
  back from another phone. "Remove member" (GRP-10, P2) rotates the group key and hands the new
  key to the remaining members at their next sync, so the removed phone stops receiving updates,
  but it keeps what it already had.
- Data at rest is protected by Android's file-based encryption and the app sandbox, plus the
  optional app lock (SET-7). Files are not encrypted separately in v1.

### 9.7 Sync and backup file format

```
Offset  Size  Field
0       8     magic        "TRNSYNC1" (sync file) | "TRNBKUP1" (backup file)
8       2     format version (u16, big-endian)
10      16    groupId (sync file) | Argon2id salt (backup file)
26      12    base nonce
38      26    reserved (zeros)
64      …     payload: ZIP, encrypted with chunked AES-256-GCM
              (1 MiB segments; nonce = base nonce XOR segment index; the final segment is flagged;
               the header is the AAD of every segment)
```

- Sync file key: `encKey` of the group. Backup file key: Argon2id(password, salt), with
  parameters tuned so key derivation takes about 1 s on the reference device. The parameters are
  stored in the backup manifest.
- ZIP contents:
  `manifest.json` (protocol, created time, sender device, counts, whether blobs are included),
  `group.json` (sync file) or `groups/` and `keys.json` (backup only, inside the encryption),
  `properties/<id>.json`, `blobs/<sha256>`.
- Suggested file name: `Terrenos-<group name>-<yyyy-mm-dd>.trn`. Receivers detect the format by
  its magic bytes.
- Size guidance: properties only, typically < 2 MB. With photos and documents, the size is shown
  before sending (GRP-9).

---

## 10. Non-Functional Requirements

| Area | Requirement |
|---|---|
| **Offline** | Every feature works with networking disabled, except downloading imagery. The app makes **no network calls** apart from imagery requests the user starts (checked in CI by a test that the HTTP client is used only by `TileDownloader`) |
| **Privacy** | No data collection. The Play Data Safety form declares "no data collected or shared". No third-party SDKs that phone home. Photo EXIF data other than GPS and time is removed when a photo is attached. No NIF or ID numbers are stored. The GDPR position is that the user controls all processing on their own phone, and the project is not a data controller |
| **Performance** | Cold start < 2.5 s; 60 fps map with 500 properties / 50 000 vertices; save < 200 ms; Nearby sync of 100 properties without blobs < 15 s after connecting |
| **Battery** | 1 h of walk mode uses ≤ 15 % battery (reference device: Galaxy A15-class) |
| **Size** | AAB download < 35 MB including CAOP |
| **Reliability** | No data loss on process death during editing or sync. Crash-free sessions ≥ 99.5 % (measured in beta through user-shared logs) |
| **Accessibility** | TalkBack labels everywhere; the vertex table and coordinate entry (§3.4) make every boundary operation possible without drawing; 200 % text scale without clipping; colour is never the only signal |
| **Localisation** | PT-PT and EN at 100 % (CI fails on missing ARB keys); number formats follow the locale (`1 234,5 m²` in PT vs `1,234.5 m²` in EN); dates `dd/MM/yyyy` in PT |
| **Licensing** | MIT; no copyleft dependencies (CI licence scan, §5.3); DGT/CAOP attributions are displayed |

---

## 11. Testing Strategy

| Layer | Tooling | Must cover |
|---|---|---|
| Unit — geometry | `flutter_test` | Geodesic area/perimeter against reference polygons; PT-TM06 round-trips against PROJ fixtures; self-intersection; simplification; polylabel; CAOP point-in-polygon for a set of known freguesias |
| Unit — coordinates | `flutter_test` + fixture table | Parser for every format and variant in §7.5 (DMS symbol variants, `O`/`W`, decimal comma or point, thousands separators); range errors; the sign and swap suggestions; pasted lists with each separator plus ambiguous lines; CSV round-trip; typed PT-TM06 values shown back exactly (`input` preserved); survey distance/bearing against GeographicLib |
| Unit — identifiers | `flutter_test` | Name trimming and limits; process number kept exactly as typed (leading zeros, `/`, letters); normalisation for duplicate checks and search; duplicate warnings on save and after sync; export field mapping and file-name sanitising |
| Unit — vertices | `flutter_test` | Vertex IDs stable across move/reorder/re-survey; insertion into the nearest edge; status derivation; `vertexInfo` edits never create geometry versions; vertex-level conflict diff |
| Unit — CRDT | `flutter_test` + **property-based tests** (`glados`) | For random edit sequences on 3–5 simulated devices with random sync orders and partitions, all devices **converge to byte-identical documents**. Plus merge commutativity, associativity and idempotence; tombstones never resurrected; move-between-groups; geometry heads/conflicts; clock skew of ±1 year |
| Unit — protocol | Loopback transport | Full session; cancellation at every step leaves consistent files; protocol version negotiation; group matching doesn't leak unmatched groups; corrupted or wrong-hash blobs rejected |
| Unit — crypto & files | | Sync and backup file round-trip; truncated, tampered or reordered segments rejected; wrong group or password gives a clear error; magic-byte detection |
| Unit — storage | Temp dirs | Atomic write under simulated crash; `.bak` recovery; quarantine; schema migration |
| Widget | `flutter_test` | Editor (add/move/insert/delete, undo/redo), forms, empty states, **both locales** |
| Golden | `alchemist` | Key screens in PT and EN, light/dark, 200 % text |
| Integration | `integration_test` + `patrol` | Draw → save → export; type a property from PT-TM06 coordinates → survey each vertex with a mocked location → export PDF; walk mode with mocked location; join group by QR (injected scan result); sync file round-trip between two app instances (`dev` + `prod` flavours on one device) |
| Device lab (manual, every release) | 3 physical phones from different brands and Android versions (incl. API 24 and the latest) | Nearby sync in airplane mode with Bluetooth on; sync files sent via WhatsApp and email; interrupted transfers; conflicting edits on all 3 phones |
| Field test | Checklist | Walk 3 real parcels in a rural area with no mobile signal; compare with a known reference (e.g. a cadastral or survey plan); target median vertex error ≤ 5 m. For one parcel, type its vertices from the plan at home first, then use Go to vertex and Survey on site |

Coverage target: ≥ 90 % for `core/sync` and `core/geometry`, ≥ 80 % overall.

CI (GitHub Actions): format, `flutter analyze` (`very_good_analysis`), tests, ARB completeness
check, the "no network outside TileDownloader" test, the dependency licence scan, secret
scanning, and a `dev` APK on each PR. Signed AAB to the
Play internal track on tag.

---

## 12. Acceptance Criteria (v1)

1. In PT, a first-time user registers a 4-vertex property in < 3 min. In a usability test, at
   least 4 of 5 non-technical participants (age 50+) do this without help.
2. With airplane mode on from install onwards (and CAOP only, no imagery), the user can create,
   edit, walk, delete, restore and export properties. A network monitor shows **zero** requests.
3. Two phones with no SIM and no Wi-Fi network join a group by QR and sync 50 properties with 100
   photos (~3 MB each) in < 3 min after connecting.
4. Three phones make concurrent attribute and boundary edits, then sync in arbitrary pairs and
   orders. Afterwards all phones have identical documents (hash compare); every concurrent
   boundary edit shows up as a conflict; nothing is silently lost.
5. A sync file sent via WhatsApp merges correctly. Modifying one byte makes it fail with a clear
   message. A file for another group is rejected without showing anything about its contents.
6. A deleted property doesn't come back after syncing with a phone that still holds an older copy.
7. Switching PT ⇄ EN updates every screen immediately; no untranslated strings.
8. PT-TM06 coordinates in the Shapefile export and the PDF match PROJ to within 1 cm; the Shapefile
   opens in QGIS with the correct CRS and readable accented attributes.
9. Killing the app during editing or during a sync loses at most the vertex being edited, and no
   synced data.
10. A full backup restored onto a freshly installed app recovers all properties, groups and
    settings.
11. The Play pre-launch report has no warnings above "minor"; the Data Safety form says "no data
    collected".
12. **At home, with no imagery and no GPS fix,** a user creates a 6-vertex property by typing
    PT-TM06 coordinates copied from a plan. The vertex table shows the typed values exactly, and
    the computed area matches the plan's area to within 0.1 %.
13. **In the field,** the user opens that property, uses Go to vertex to reach each planned
    vertex, and surveys it. The app reports the offset from the typed position, the progress
    reaches "6/6 levantados", and the history keeps the typed coordinates.
14. A vertex renamed on one phone while it is re-surveyed on another ends with both the new name
    and the new coordinates after syncing, and no conflict is raised.
15. Every vertex operation (add, edit coordinates, delete, reorder, survey) can be completed with
    TalkBack, using only the vertex table.
16. A property saved with process number `0012/2023-A` shows it unchanged in the list, detail,
    PDF and every export format, and it can be found by searching `00122023a`. Saving a second
    property with `0012 / 2023-a` warns about the duplicate.

---

## 13. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **Data loss when a phone is lost or broken** (there is no server) | High | Onboarding warning; groups act as natural replicas; encrypted backup file; backup reminder (BAK-3) |
| Nearby Connections needs Google Play Services, so Huawei phones and de-Googled ROMs can't sync nearby | Medium | Sync files work everywhere; the Nearby option is hidden or explained when GMS is missing |
| Flutter Nearby plugin unmaintained | Medium | Own thin Kotlin platform channel (~300 lines) behind the `SyncTransport` interface |
| DGT service: URL changes, downtime, tiling CRS | Medium | M1 technical spike; layer configuration in one place; tiles already downloaded keep working; the app stays usable with CAOP alone |
| Group key leaks (a photo of the QR code is forwarded) | Medium | In-person invite guidance, `FLAG_SECURE`, key rotation (P2); limits clearly communicated |
| Users treat the app as a legal registry | Legal | Disclaimers in onboarding and in every PDF |
| Wrong phone clocks cause surprising last-writer-wins outcomes | Low | HLC, skew warning, boundaries protected by conflict detection instead of LWW |
| Large sync files with photos are hard to send by WhatsApp or email | Low | Photos are opt-in per sync; thumbnails only by default in files |
| Polygon editing is fiddly on small screens | Medium | Loupe, snapping, undo, vertex table with typed coordinates, usability test in M1 |
| Typing errors in coordinates (sign, swapped axes, wrong format) | Medium | Separate fields per axis, live preview pin, sign and swap suggestions, outside-Portugal warning (§7.5) |
| Users type coordinates from old plans in Datum 73 / Datum Lisboa, which are not supported (D14), as if they were PT-TM06 | Medium | Help text in the entry form saying only PT-TM06 and WGS84 are accepted, and how to recognise a PT-TM06 plan ("PT-TM06/ETRS89" in the legend); the outside-Portugal warning and the live preview pin show when a point lands far from the expected place |

---

## 14. Milestones

| # | Milestone | Scope | Est. |
|---|---|---|---|
| M0 | Foundations | Public repo + licence + contributor files, scaffold, flavours, CI (incl. licence and secret scans), theme, PT/EN localisation, JSON file store, HLC, device identity | 2 wk |
| M1 | Map, draw & coordinates | DGT layer + tile cache, CAOP asset + overlay + lookup, vertex model, draw editor, **vertex table, coordinate entry and parsing (DD/DMS/PT-TM06)**, validation, details form with PT fields, list/detail | 4 wk |
| M2 | Field capture | Walk mode (points, track, foreground service), **survey existing vertex, go to vertex**, marker photos, offline area download | 2.5 wk |
| M3 | Sync core | Property/group CRDTs, merge, geometry DAG, groups, QR join, encrypted sync files, conflict UI | 3 wk |
| M4 | Nearby | Nearby transport, handshake, blob transfer, sync UX, device lab | 2 wk |
| M5 | Export & backup | GeoJSON, KML, Shapefile (PT-TM06) with vertex layer, PDF with vertex table, vertex CSV and pasted lists; encrypted backup/restore; import | 2 wk |
| M6 | Hardening & release | Accessibility, performance, PT-PT language review, field test, Play listing (both languages), closed testing (Play requires 12+ testers for 14 days on new personal developer accounts) | 2 wk |

Total ≈ 17.5 weeks of feature work for one experienced Flutter developer. The detailed plan in
`PLAN.md` adds technical spikes, field and usability tests and release work: ≈ 19.5 weeks plus
2 weeks of buffer.

---

## 15. Open Questions

None at the moment. All questions up to v0.6 are resolved (D1–D16).

**Technical checks** (not decisions) that remain, scheduled in the milestones:

- DGT orthophoto service URL, layer name and tiling CRS (M1 spike, §6.1).
- Current maintenance status of the Nearby Connections Flutter plugin, or a decision to write
  our own platform channel (M4, §5.1).
- Latest CAOP edition and its asset size after simplification (M1, §6.2).

---

## Appendix A — Glossary (EN / PT-PT)

| English | Português | Notes |
|---|---|---|
| Property / parcel | Prédio / terreno | UI uses "terreno"; "prédio" in legal fields |
| Rustic / urban / mixed property | Prédio rústico / urbano / misto | |
| Boundary | Limite / estrema | |
| Boundary marker | Marco | Walk mode "Adicionar ponto no marco" |
| Vertex | Vértice | Table header "Vértices" |
| Planned vertex | Vértice previsto | Not yet confirmed on site |
| Surveyed vertex | Vértice levantado | Captured or confirmed with GPS |
| Survey (a vertex) | Levantar | "Levantar vértice com GPS" |
| Go to vertex | Ir até ao vértice | |
| Decimal degrees / DMS | Graus decimais / GMS (graus, minutos, segundos) | |
| Easting / Northing (PT-TM06) | M / P | |
| Abutting properties | Confrontações | North / South / Nascente (E) / Poente (W) |
| Identifier name | Nome identificador | Required |
| Process number (official ID) | N.º de processo (identificação oficial) | Optional |
| Matrix article | Artigo matricial | Finanças (tax office) |
| Land registry description | Descrição predial | Conservatória do Registo Predial |
| Owner(s) | Titular(es) | |
| Parish / municipality / district | Freguesia / concelho / distrito | From CAOP |
| Place name | Lugar / sítio | |
| Scrubland | Mato | |
| Orthophoto | Ortofotomapa | |
| Group | Grupo | e.g. "Família Fernandes" |
| Sync | Sincronizar | |
| Sync nearby | Sincronizar com telemóvel próximo | |
| Sync file | Ficheiro de sincronização | |
| Backup | Cópia de segurança | |
| Recycle bin | Reciclagem | |
| Draft | Rascunho | |
| Conflict | Conflito | "Dois limites diferentes — escolha um" |

## Appendix B — Project Layout

```
terrenos/
├── LICENSE                          # MIT
├── README.md / README.pt.md
├── CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md
├── .github/                         # CI workflows, issue templates
├── android/                         # incl. Kotlin Nearby platform channel (prod flavour only)
├── assets/caop/                     # simplified CAOP GeoJSON + index
├── lib/
│   ├── main.dart                    # one entry point; flavours in Gradle (ADR 0002)
│   ├── app.dart
│   ├── l10n/                        # app_pt.arb, app_en.arb
│   ├── core/
│   │   ├── geometry/                # GeometryService, validation, units
│   │   ├── crs/                     # PT-TM06 conversions, coordinate parsing/formatting
│   │   ├── location/                # LocationSource, GPS averaging
│   │   ├── storage/                 # PropertyStore, BlobStore, atomic file IO
│   │   ├── map/                     # layers, TileStore, TileDownloader
│   │   ├── crdt/                    # HLC, registers, geometry DAG, merge
│   │   ├── sync/                    # SyncEngine, protocol, transports
│   │   ├── crypto/                  # keys, sync and backup file format
│   │   └── theme/
│   └── features/
│       ├── onboarding/
│       ├── map/
│       ├── editor/                  # draw, walk, coordinates, import
│       ├── vertices/                # vertex table, entry form, paste/CSV, survey, go-to
│       ├── properties/              # list, detail, form, history, recycle bin
│       ├── groups/                  # create, join, invite, members, conflicts
│       ├── sync/                    # nearby, file send/import, summary
│       ├── offline_areas/
│       ├── export/                  # GeoJSON, KML, Shapefile, PDF
│       ├── backup/
│       └── settings/
├── docs/data-licences.md            # DGT orthophoto and CAOP licence terms + attribution
├── tool/build_caop.dart             # CAOP → simplified asset
├── test/                            # unit, widget, golden, property-based
├── integration_test/
└── test_fixtures/                   # KML/GeoJSON/GPX/SHP samples, PROJ reference points, CRDT scenarios
```
