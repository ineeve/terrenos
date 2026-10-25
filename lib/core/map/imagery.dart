/// Map imagery sources (SPEC.md §6.1, ADR 0004).
///
/// All imagery configuration lives here, so a new DGT series only needs a
/// change in this file.
library;

/// Identifies requests to DGT (SPEC.md §6.1: an identifying User-Agent).
const imageryUserAgent = 'Terrenos (+https://github.com/ineeve/terrenos)';

/// Attribution required for DGT data (docs/data-licences.md).
const dgtAttribution = 'Ortofotos © DGT';

enum ImagerySource {
  /// Default: the whole mainland at 25 cm.
  ortos2025(
    year: 2025,
    baseUrl: 'https://cartografia.dgterritorio.gov.pt/wms/ortos2025?',
    layer: 'Ortos2025-RGB',
  ),

  /// Previous imagery, useful when vegetation hides a boundary in 2025.
  ortos2018(
    year: 2018,
    baseUrl: 'https://cartografia.dgterritorio.gov.pt/wms/ortos2018?',
    layer: 'Ortos2018-RGB',
  );

  new({required this.year, required this.baseUrl, required this.layer});

  final int year;

  /// WMS 1.3.0 endpoint; ends with `?` because parameters are appended.
  final String baseUrl;
  final String layer;

  /// The imagery is 25 cm per pixel, ≈ zoom 19 at Portugal's latitude.
  static const maxNativeZoom = 19;
}
