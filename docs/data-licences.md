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
- **Edition used:** CAOP 2025, Continente (approved 28 January 2026,
  published in Aviso n.º 3502/2026/2, Diário da República, 2.ª série,
  18 February 2026). See ADR 0007.
- **Source file:** `https://geo2.dgterritorio.gov.pt/caop/CAOP_Continente_2025-gpkg.zip`
  (GeoPackage, not committed)
- **Licence (checked 2026-10-25):** Creative Commons Attribution (CC BY),
  as listed for the dataset on dados.gov.pt
  (`carta-administrativa-oficial-de-portugal-caop2025-continente`).
- **What is committed:** only the simplified derivative
  `assets/caop/caop.json`, with its attribution and a description of the
  changes in `assets/caop/README.md`.
- **Attribution shown:** "Limites administrativos: CAOP 2025 © DGT" in
  Settings → Map data.

## OpenStreetMap (place names)

- **Provider:** OpenStreetMap contributors
- **Data used:** nodes tagged `place` = `city`, `town`, `village` or
  `hamlet` with a `name`, in mainland Portugal, extracted through the
  Overpass API on 2026-10-26. See ADR 0010.
- **Licence:** Open Database License (ODbL) 1.0,
  <https://www.openstreetmap.org/copyright>.
- **What is committed:** the derivative database `assets/places/places.json`,
  offered under the ODbL, with its changes described in
  `assets/places/README.md`. The app's MIT licence does not apply to it.
- **Attribution shown:** "© OpenStreetMap" on the map; "Place names ©
  OpenStreetMap contributors, ODbL" in Settings → Map data.
