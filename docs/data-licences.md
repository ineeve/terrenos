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

To be recorded when the CAOP asset is built (PLAN.md T1.1, spike S3).
