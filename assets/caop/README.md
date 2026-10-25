# CAOP 2025 (simplified)

`caop.json` is derived from the **Carta Administrativa Oficial de Portugal,
CAOP 2025 (Continente)** by the Direção-Geral do Território (DGT), licensed
under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Source: DGT OGC API (`ogcapi.dgterritorio.gov.pt`, collections `freguesias`,
`municipios`, `distritos`); dataset page:
<https://dados.gov.pt/datasets/carta-administrativa-oficial-de-portugal-caop2025-continente>.

Changes: boundaries simplified (5 m for freguesias, 30 m for municípios,
150 m for distritos), attributes reduced to names and codes, coordinates
rounded to 1e-5° and delta-encoded. Regenerate with
`python3 tool/caop/build_caop.py`. Not an official representation of the
boundaries.
