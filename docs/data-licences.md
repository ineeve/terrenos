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
