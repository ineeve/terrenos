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

/// The area two polygons share (VAL-7). Each polygon is a list of parts,
/// each an outer ring followed by holes; rings are open and either
/// orientation is accepted.
///
/// By Green's theorem the shared region's boundary is made of the pieces of
/// each polygon's edges that lie inside the other, so the area is the sum
/// of those pieces' shoelace terms. An edge piece lying on the other
/// polygon's boundary counts once when both run the same way (identical
/// boundaries) and not at all when they run opposite ways (neighbours that
/// share a border).
double sharedArea(List<List<List<Xy>>> a, List<List<List<Xy>>> b) {
  final edgesA = _orientedEdges(a);
  final edgesB = _orientedEdges(b);
  final twice =
      _insideTerms(edgesA, edgesB, b, countShared: true) +
      _insideTerms(edgesB, edgesA, a, countShared: false);
  return twice > 0 ? twice / 2 : 0;
}

typedef _Edge = ({Xy a, Xy b});

/// Outer rings counter-clockwise and holes clockwise, as Green's theorem
/// needs.
List<_Edge> _orientedEdges(List<List<List<Xy>>> polygon) {
  final edges = <_Edge>[];
  for (final part in polygon) {
    for (var r = 0; r < part.length; r++) {
      final ring = part[r];
      if (ring.length < 3) continue;
      final oriented = (signedArea(ring) > 0) == (r == 0)
          ? ring
          : ring.reversed.toList();
      for (var i = 0; i < oriented.length; i++) {
        edges.add((a: oriented[i], b: oriented[(i + 1) % oriented.length]));
      }
    }
  }
  return edges;
}

/// Twice the signed area contributed by the pieces of [edges] inside
/// [other].
double _insideTerms(
  List<_Edge> edges,
  List<_Edge> otherEdges,
  List<List<List<Xy>>> other, {
  required bool countShared,
}) {
  final otherRings = [for (final part in other) ...part];
  var sum = 0.0;
  for (final edge in edges) {
    final p = edge.a;
    final rx = edge.b.x - p.x;
    final ry = edge.b.y - p.y;
    final length2 = rx * rx + ry * ry;
    if (length2 == 0) continue;

    // Where the other polygon's edges cut this one, as fractions along it.
    final cuts = <double>[0, 1];
    for (final o in otherEdges) {
      if (!_boxesTouch(edge, o)) continue;
      final sx = o.b.x - o.a.x;
      final sy = o.b.y - o.a.y;
      final qx = o.a.x - p.x;
      final qy = o.a.y - p.y;
      final denominator = rx * sy - ry * sx;
      if (denominator.abs() > 1e-12 * length2) {
        final t = (qx * sy - qy * sx) / denominator;
        final u = (qx * ry - qy * rx) / denominator;
        if (t > 0 && t < 1 && u >= 0 && u <= 1) cuts.add(t);
      } else if ((qx * ry - qy * rx).abs() < _epsilon) {
        // Collinear: the other edge's ends split this one.
        for (final end in [o.a, o.b]) {
          final t = ((end.x - p.x) * rx + (end.y - p.y) * ry) / length2;
          if (t > 0 && t < 1) cuts.add(t);
        }
      }
    }
    cuts.sort();

    for (var i = 1; i < cuts.length; i++) {
      final t0 = cuts[i - 1];
      final t1 = cuts[i];
      if (t1 - t0 < 1e-12) continue;
      final mid = (x: p.x + rx * (t0 + t1) / 2, y: p.y + ry * (t0 + t1) / 2);
      final shared = otherEdges
          .where((o) => distanceToSegmentSquared(mid, o.a, o.b) < 1e-12)
          .firstOrNull;
      final bool inside;
      if (shared != null) {
        final sameWay =
            (shared.b.x - shared.a.x) * rx + (shared.b.y - shared.a.y) * ry > 0;
        inside = countShared && sameWay;
      } else {
        inside = containsPoint(otherRings, mid);
      }
      if (!inside) continue;
      final x0 = p.x + rx * t0;
      final y0 = p.y + ry * t0;
      final x1 = p.x + rx * t1;
      final y1 = p.y + ry * t1;
      sum += x0 * y1 - x1 * y0;
    }
  }
  return sum;
}

bool _boxesTouch(_Edge e, _Edge o) =>
    _min(e.a.x, e.b.x) <= _max(o.a.x, o.b.x) + _epsilon &&
    _min(o.a.x, o.b.x) <= _max(e.a.x, e.b.x) + _epsilon &&
    _min(e.a.y, e.b.y) <= _max(o.a.y, o.b.y) + _epsilon &&
    _min(o.a.y, o.b.y) <= _max(e.a.y, e.b.y) + _epsilon;

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
