/// Distances and bearings on the WGS84 ellipsoid (SPEC.md §7.2, VTX-9).
library;

import 'dart:math';

/// A point as longitude/latitude in degrees, `[lon, lat]` order as in
/// GeoJSON.
typedef LonLat = ({double lon, double lat});

const _a = 6378137.0;
const double _f = 1 / 298.257223563;
const double _b = (1 - _f) * _a;

/// Result of [inverse]: geodesic distance and initial bearing.
typedef Geodesic = ({double distanceMetres, double bearingDegrees});

/// Vincenty's inverse formula. Accurate to well under a millimetre for the
/// distances in this app; it only fails to converge for nearly antipodal
/// points, which can't occur within Portugal.
Geodesic inverse(LonLat from, LonLat to) {
  final l = _rad(to.lon - from.lon);
  final u1 = atan((1 - _f) * tan(_rad(from.lat)));
  final u2 = atan((1 - _f) * tan(_rad(to.lat)));
  final sinU1 = sin(u1);
  final cosU1 = cos(u1);
  final sinU2 = sin(u2);
  final cosU2 = cos(u2);

  var lambda = l;
  double sinSigma;
  double cosSigma;
  double sigma;
  double cosSqAlpha;
  double cos2SigmaM;
  double sinLambda;
  double cosLambda;
  var iterations = 0;
  while (true) {
    sinLambda = sin(lambda);
    cosLambda = cos(lambda);
    sinSigma = sqrt(
      pow(cosU2 * sinLambda, 2) +
          pow(cosU1 * sinU2 - sinU1 * cosU2 * cosLambda, 2),
    );
    if (sinSigma == 0) return (distanceMetres: 0, bearingDegrees: 0);
    cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
    sigma = atan2(sinSigma, cosSigma);
    final sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma;
    cosSqAlpha = 1 - sinAlpha * sinAlpha;
    cos2SigmaM = cosSqAlpha == 0
        ? 0
        : cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha;
    final c = _f / 16 * cosSqAlpha * (4 + _f * (4 - 3 * cosSqAlpha));
    final previous = lambda;
    lambda =
        l +
        (1 - c) *
            _f *
            sinAlpha *
            (sigma +
                c *
                    sinSigma *
                    (cos2SigmaM +
                        c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)));
    if ((lambda - previous).abs() < 1e-12) break;
    if (++iterations > 200) {
      throw StateError('Vincenty did not converge');
    }
  }

  final uSq = cosSqAlpha * (_a * _a - _b * _b) / (_b * _b);
  final bigA =
      1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)));
  final bigB = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)));
  final deltaSigma =
      bigB *
      sinSigma *
      (cos2SigmaM +
          bigB /
              4 *
              (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) -
                  bigB /
                      6 *
                      cos2SigmaM *
                      (-3 + 4 * sinSigma * sinSigma) *
                      (-3 + 4 * cos2SigmaM * cos2SigmaM)));
  final distance = _b * bigA * (sigma - deltaSigma);
  final bearing = atan2(
    cosU2 * sinLambda,
    cosU1 * sinU2 - sinU1 * cosU2 * cosLambda,
  );
  return (
    distanceMetres: distance,
    bearingDegrees: (_deg(bearing) + 360) % 360,
  );
}

/// One of 8 compass directions for a bearing, e.g. for "3,2 m para
/// nordeste" (VTX-9).
enum CompassDirection {
  north,
  northEast,
  east,
  southEast,
  south,
  southWest,
  west,
  northWest;

  static CompassDirection fromBearing(double degrees) =>
      values[((degrees % 360) / 45).round() % 8];
}

double _rad(double degrees) => degrees * pi / 180;
double _deg(double radians) => radians * 180 / pi;
