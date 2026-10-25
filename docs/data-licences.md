# Data licences and attribution

Terms of the third-party data the app uses. The code licence (MIT) doesn't
apply to these datasets.

## DGT orthophotos (map imagery)

- **Provider:** Direção-Geral do Território (DGT)
- **Series used:** Ortos 2025, Portugal Continental, 25 cm (default); Ortos
  2018, 25 cm (optional previous imagery). See ADR 0004.
- **Service:** WMS 1.3.0, `https://cartografia.dgterritorio.gov.pt/wms/ortos2025`
- **Terms as published in the service capabilities (checked 2026-10-25):**
  `Fees: no conditions apply`, `AccessConstraints: None`. DGT's orthophoto
  page describes the services as *"Acesso gratuito"* and refers to its open
  data guides (`/dados-abertos`).
- **Use approved by the project owner:** SPEC.md D13.
- **Attribution shown:** "Ortofotos © DGT" on the map, in About and in PDF
  exports.

## CAOP (administrative boundaries)

- **Provider:** Direção-Geral do Território (DGT)
- **Dataset:** Carta Administrativa Oficial de Portugal, CAOP 2025
  (Continente): distritos, municípios, freguesias.
- **Licence:** CC BY 4.0, as listed on dados.gov.pt (checked 2026-10-25):
  <https://dados.gov.pt/datasets/carta-administrativa-oficial-de-portugal-caop2025-continente>.
  A third-party mirror lists CC BY-NC 4.0; the official portal's listing
  is what this project relies on.
- **Bundled form:** `assets/caop/caop.json`, simplified and re-encoded by
  `tool/caop/build_caop.py`; see `assets/caop/README.md` and ADR 0006.
- **Attribution shown:** "CAOP 2025 © DGT" in About.

## OpenStreetMap (low-detail basemap)

- **Provider:** OpenStreetMap Foundation standard tile layer.
- **Data licence:** Open Database License (ODbL); attribution
  "© OpenStreetMap contributors" with a link to
  <https://www.openstreetmap.org/copyright>.
- **Use:** only below zoom 14, where DGT has no imagery (ADR 0008), under
  the [tile usage policy](https://operations.osmfoundation.org/policies/tiles/):
  identifying User-Agent, HTTP caching honoured, **no bulk or offline
  download**.
- **Attribution shown:** on the map while OSM tiles are visible (tapping it
  opens the copyright page) and in About.
