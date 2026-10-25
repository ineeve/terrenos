/// WGS84 ⇄ PT-TM06 (EPSG:3763, ETRS89 / Portugal TM06) — SPEC.md §7.2.
///
/// ETRS89 and WGS84 differ by well under a metre in Portugal, far below
/// phone GPS accuracy, so they are treated as the same datum; this is a pure
/// map projection. Accuracy against PROJ is checked by spike S4 (ADR 0005).
library;

import 'package:proj4dart/proj4dart.dart' as proj4;

/// Easting (M) and northing (P) in metres, as on Portuguese plans.
typedef PtTm06Point = ({double m, double p});

typedef LatLon = ({double lat, double lon});

abstract final class PtTm06 {
  static const epsg = 'EPSG:3763';

  /// From the EPSG registry; no datum shift (see the library comment).
  static const projString =
      '+proj=tmerc +lat_0=39.6682583333333 +lon_0=-8.13310833333333 '
      '+k=1 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs';

  static final proj4.Projection _ptTm06 =
      proj4.Projection.get(epsg) ?? proj4.Projection.add(epsg, projString);

  static PtTm06Point fromLatLon(double lat, double lon) {
    final point = proj4.Projection.WGS84.transform(
      _ptTm06,
      proj4.Point(x: lon, y: lat),
    );
    return (m: point.x, p: point.y);
  }

  static LatLon toLatLon(double m, double p) {
    final point = _ptTm06.transform(
      proj4.Projection.WGS84,
      proj4.Point(x: m, y: p),
    );
    return (lat: point.y, lon: point.x);
  }
}
