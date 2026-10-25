/// A local equal-area plane for geometry on parcel-sized polygons.
///
/// Area, interior points and intersection tests are computed after
/// projecting to a Lambert azimuthal equal-area plane on the WGS84 ellipsoid,
/// centred on the geometry. The projection preserves area exactly, so the
/// planar shoelace area equals the ellipsoidal area up to the tiny difference
/// between straight and geodesic edges (checked against GeographicLib).
library;

import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:terrenos/core/geometry/geodesy.dart';

/// A point on the local plane, in metres.
typedef Xy = ({double x, double y});

class LocalPlane {
  new(this.centre)
    : _plane = proj4.Projection.parse(
        '+proj=laea +lat_0=${centre.lat} +lon_0=${centre.lon} '
        '+x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs',
      );

  /// A plane centred on the middle of the bounding box of [points].
  factory around(Iterable<LonLat> points) {
    var minLon = double.infinity;
    var maxLon = double.negativeInfinity;
    var minLat = double.infinity;
    var maxLat = double.negativeInfinity;
    for (final p in points) {
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
    }
    if (minLon.isInfinite) {
      throw ArgumentError('LocalPlane.around needs at least one point');
    }
    return LocalPlane((lon: (minLon + maxLon) / 2, lat: (minLat + maxLat) / 2));
  }

  final LonLat centre;
  final proj4.Projection _plane;

  Xy project(LonLat p) {
    final out = proj4.Projection.WGS84.transform(
      _plane,
      proj4.Point(x: p.lon, y: p.lat),
    );
    return (x: out.x, y: out.y);
  }

  LonLat unproject(Xy p) {
    // proj4dart 3.0.0 throws within ~0.6 mm of the centre of an oblique
    // LAEA plane (a null `phi0` in its inverse), so answer that case
    // directly; 1 mm is far below the stored precision.
    if (p.x.abs() < 1e-3 && p.y.abs() < 1e-3) return centre;
    final out = _plane.transform(
      proj4.Projection.WGS84,
      proj4.Point(x: p.x, y: p.y),
    );
    return (lon: out.x, lat: out.y);
  }
}

/// Signed shoelace area of an open ring: positive when counter-clockwise.
double signedArea(List<Xy> ring) {
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum / 2;
}

/// Whether segments ab and cd share any point, including touching ends
/// and collinear overlaps.
bool segmentsIntersect(Xy a, Xy b, Xy c, Xy d) {
  final o1 = _orientation(a, b, c);
  final o2 = _orientation(a, b, d);
  final o3 = _orientation(c, d, a);
  final o4 = _orientation(c, d, b);
  if (o1 != o2 && o3 != o4) return true;
  if (o1 == 0 && _onSegment(a, c, b)) return true;
  if (o2 == 0 && _onSegment(a, d, b)) return true;
  if (o3 == 0 && _onSegment(c, a, d)) return true;
  if (o4 == 0 && _onSegment(c, b, d)) return true;
  return false;
}

/// Squared distance from [p] to segment ab.
double distanceToSegmentSquared(Xy p, Xy a, Xy b) {
  var x = a.x;
  var y = a.y;
  final dx = b.x - x;
  final dy = b.y - y;
  if (dx != 0 || dy != 0) {
    final t = ((p.x - x) * dx + (p.y - y) * dy) / (dx * dx + dy * dy);
    if (t > 1) {
      x = b.x;
      y = b.y;
    } else if (t > 0) {
      x += dx * t;
      y += dy * t;
    }
  }
  final ex = p.x - x;
  final ey = p.y - y;
  return ex * ex + ey * ey;
}

/// Even-odd point-in-polygon over all rings of all parts.
bool containsPoint(List<List<Xy>> rings, Xy p) {
  var inside = false;
  for (final ring in rings) {
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      if ((a.y > p.y) != (b.y > p.y) &&
          p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
  }
  return inside;
}

/// Collinearity tolerance in square metres: 1 mm × 1 m.
const _epsilon = 1e-3;

int _orientation(Xy p, Xy q, Xy r) {
  final value = (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
  if (value.abs() < _epsilon) return 0;
  return value > 0 ? 1 : 2;
}

bool _onSegment(Xy p, Xy q, Xy r) =>
    q.x <= _max(p.x, r.x) + _epsilon &&
    q.x >= _min(p.x, r.x) - _epsilon &&
    q.y <= _max(p.y, r.y) + _epsilon &&
    q.y >= _min(p.y, r.y) - _epsilon;

double _max(double a, double b) => a > b ? a : b;
double _min(double a, double b) => a < b ? a : b;
