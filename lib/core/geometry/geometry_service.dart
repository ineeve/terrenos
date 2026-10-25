/// Measurements and checks on property boundaries (SPEC.md §3.5, §7.2).
library;

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/geometry/planar.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';

/// Area, perimeter, interior point and bounding box of a boundary.
typedef Measurements = ({
  double areaSquareMetres,
  double perimeterMetres,
  LonLat interiorPoint,
  ({double minLon, double minLat, double maxLon, double maxLat}) bounds,
});

/// Two segments that cross, identified by the vertex ids at their ends.
typedef Crossing = ({(String, String) first, (String, String) second});

abstract final class GeometryService {
  /// Geodesic measurements of [parts]. Each part's first ring is its outer
  /// boundary and any further rings are holes.
  static Measurements measure(BoundaryParts parts) {
    final points = _allPoints(parts);
    if (points.length < 3) {
      throw ArgumentError('A boundary needs at least 3 vertices');
    }
    final plane = LocalPlane.around(points);
    final projected = _project(parts, plane);

    var area = 0.0;
    var perimeter = 0.0;
    for (var p = 0; p < parts.length; p++) {
      for (var r = 0; r < parts[p].length; r++) {
        final ringArea = signedArea(projected[p][r]).abs();
        area += r == 0 ? ringArea : -ringArea;
        perimeter += ringLength(parts[p][r]);
      }
    }

    var minLon = double.infinity;
    var minLat = double.infinity;
    var maxLon = double.negativeInfinity;
    var maxLat = double.negativeInfinity;
    for (final p in points) {
      minLon = min(minLon, p.lon);
      minLat = min(minLat, p.lat);
      maxLon = max(maxLon, p.lon);
      maxLat = max(maxLat, p.lat);
    }

    return (
      areaSquareMetres: area,
      perimeterMetres: perimeter,
      interiorPoint: plane.unproject(_interiorPoint(projected)),
      bounds: (minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat),
    );
  }

  /// Geodesic length of a closed ring.
  static double ringLength(List<Vertex> ring) {
    var length = 0.0;
    for (var i = 0; i < ring.length; i++) {
      length += inverse(
        _lonLat(ring[i]),
        _lonLat(ring[(i + 1) % ring.length]),
      ).distanceMetres;
    }
    return length;
  }

  /// Every pair of segments that touch or cross, other than neighbours in
  /// the same ring (VAL-2). Rings of different parts are checked against
  /// each other too: parts of one property must not overlap.
  static List<Crossing> crossings(BoundaryParts parts) {
    final points = _allPoints(parts);
    if (points.length < 3) return const [];
    final plane = LocalPlane.around(points);
    final projected = _project(parts, plane);

    final segments = <_Segment>[];
    for (var p = 0; p < parts.length; p++) {
      for (var r = 0; r < parts[p].length; r++) {
        final ring = parts[p][r];
        final xy = projected[p][r];
        for (var i = 0; i < ring.length; i++) {
          final j = (i + 1) % ring.length;
          segments.add(
            _Segment(
              ringKey: '$p/$r',
              index: i,
              ringLength: ring.length,
              ids: (ring[i].id, ring[j].id),
              a: xy[i],
              b: xy[j],
            ),
          );
        }
      }
    }

    final found = <Crossing>[];
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      for (var j = i + 1; j < segments.length; j++) {
        final t = segments[j];
        if (s.isNeighbourOf(t) || !s.boxOverlaps(t)) continue;
        if (segmentsIntersect(s.a, s.b, t.a, t.b)) {
          found.add((first: s.ids, second: t.ids));
        }
      }
    }
    return found;
  }

  /// Removes consecutive vertices at the same position (VAL-5), keeping
  /// the first of each run so its id, label and photos survive.
  static BoundaryParts withoutDuplicates(BoundaryParts parts) => [
    for (final part in parts) [for (final ring in part) _dedupeRing(ring)],
  ];

  static List<Vertex> _dedupeRing(List<Vertex> ring) {
    final out = <Vertex>[];
    for (final v in ring) {
      if (out.isEmpty || !_samePosition(out.last, v)) out.add(v);
    }
    // Rings are stored open, so a last vertex equal to the first is a
    // duplicate too.
    while (out.length > 1 && _samePosition(out.last, out.first)) {
      out.removeLast();
    }
    return out;
  }

  /// Whether the outer ring runs counter-clockwise, the orientation
  /// RFC 7946 requires for exported outer rings (VAL-4).
  static bool isCounterClockwise(List<Vertex> ring) {
    if (ring.length < 3) return true;
    final plane = LocalPlane.around(ring.map(_lonLat));
    return signedArea([for (final v in ring) plane.project(_lonLat(v))]) > 0;
  }

  /// Douglas–Peucker simplification of a ring, with [toleranceMetres]
  /// measured on the local plane (REG-3, VAL-9). The first vertex is always
  /// kept; ids of kept vertices are unchanged.
  static List<Vertex> simplifyRing(List<Vertex> ring, double toleranceMetres) {
    if (ring.length <= 3) return ring;
    final plane = LocalPlane.around(ring.map(_lonLat));
    final xy = [for (final v in ring) plane.project(_lonLat(v))];
    final keep = List.filled(ring.length + 1, false)
      ..[0] = true
      ..[ring.length] = true;
    final closed = [...xy, xy.first];
    final toleranceSq = toleranceMetres * toleranceMetres;

    final stack = <(int, int)>[(0, ring.length)];
    while (stack.isNotEmpty) {
      final (first, last) = stack.removeLast();
      var maxDistance = 0.0;
      var index = -1;
      for (var i = first + 1; i < last; i++) {
        final d = distanceToSegmentSquared(
          closed[i],
          closed[first],
          closed[last],
        );
        if (d > maxDistance) {
          maxDistance = d;
          index = i;
        }
      }
      if (index != -1 && maxDistance > toleranceSq) {
        keep[index] = true;
        stack
          ..add((first, index))
          ..add((index, last));
      }
    }
    final kept = [
      for (var i = 0; i < ring.length; i++)
        if (keep[i]) ring[i],
    ];
    // A ring can't collapse below a triangle.
    return kept.length >= 3 ? kept : ring;
  }
}

class _Segment {
  new({
    required this.ringKey,
    required this.index,
    required this.ringLength,
    required this.ids,
    required this.a,
    required this.b,
  }) : minX = min(a.x, b.x),
       maxX = max(a.x, b.x),
       minY = min(a.y, b.y),
       maxY = max(a.y, b.y);

  final String ringKey;
  final int index;
  final int ringLength;
  final (String, String) ids;
  final Xy a;
  final Xy b;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  /// Neighbouring segments share a vertex by construction.
  bool isNeighbourOf(_Segment other) {
    if (other.ringKey != ringKey) return false;
    final diff = (index - other.index).abs();
    return diff == 1 || diff == ringLength - 1;
  }

  bool boxOverlaps(_Segment o) =>
      minX <= o.maxX + 1e-3 &&
      o.minX <= maxX + 1e-3 &&
      minY <= o.maxY + 1e-3 &&
      o.minY <= maxY + 1e-3;
}

LonLat _lonLat(Vertex v) => (lon: v.lon, lat: v.lat);

List<LonLat> _allPoints(BoundaryParts parts) => [
  for (final part in parts)
    for (final ring in part)
      for (final v in ring) _lonLat(v),
];

List<List<List<Xy>>> _project(BoundaryParts parts, LocalPlane plane) => [
  for (final part in parts)
    [
      for (final ring in part)
        [for (final v in ring) plane.project(_lonLat(v))],
    ],
];

bool _samePosition(Vertex a, Vertex b) => a.lon == b.lon && a.lat == b.lat;

/// Pole of inaccessibility (Mapbox's polylabel): the interior point furthest
/// from any edge, so labels and the CAOP lookup always fall inside the
/// parcel, even for L-shaped or multi-part properties. Precision: 0.5 m.
Xy _interiorPoint(List<List<List<Xy>>> parts) {
  // The largest part gets the label.
  final part = parts.reduce(
    (a, b) => signedArea(a.first).abs() >= signedArea(b.first).abs() ? a : b,
  );
  final outer = part.first;
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final p in outer) {
    minX = min(minX, p.x);
    minY = min(minY, p.y);
    maxX = max(maxX, p.x);
    maxY = max(maxY, p.y);
  }
  final width = maxX - minX;
  final height = maxY - minY;
  final cellSize = min(width, height);
  if (cellSize == 0) return (x: minX, y: minY);

  double signedDistance(Xy p) {
    var minDistSq = double.infinity;
    for (final ring in part) {
      for (var i = 0; i < ring.length; i++) {
        minDistSq = min(
          minDistSq,
          distanceToSegmentSquared(p, ring[i], ring[(i + 1) % ring.length]),
        );
      }
    }
    return (containsPoint(part, p) ? 1 : -1) * sqrt(minDistSq);
  }

  _Cell cell(double x, double y, double h) {
    final d = signedDistance((x: x, y: y));
    return _Cell(x, y, h, d, d + h * sqrt2);
  }

  final queue = PriorityQueue<_Cell>((a, b) => b.max.compareTo(a.max));
  var h = cellSize / 2;
  for (var x = minX; x < maxX; x += cellSize) {
    for (var y = minY; y < maxY; y += cellSize) {
      queue.add(cell(x + h, y + h, h));
    }
  }

  // Start from the area centroid, which is often already a good answer.
  var best = cell(minX + width / 2, minY + height / 2, 0);
  final centroid = _centroid(outer);
  final centroidCell = cell(centroid.x, centroid.y, 0);
  if (centroidCell.d > best.d) best = centroidCell;

  const precision = 0.5;
  while (queue.isNotEmpty) {
    final c = queue.removeFirst();
    if (c.d > best.d) best = c;
    if (c.max - best.d <= precision) continue;
    h = c.h / 2;
    queue
      ..add(cell(c.x - h, c.y - h, h))
      ..add(cell(c.x + h, c.y - h, h))
      ..add(cell(c.x - h, c.y + h, h))
      ..add(cell(c.x + h, c.y + h, h));
  }
  return (x: best.x, y: best.y);
}

class _Cell {
  new(this.x, this.y, this.h, this.d, this.max);

  final double x;
  final double y;

  /// Half the cell size.
  final double h;

  /// Distance from the centre to the polygon edge (negative outside).
  final double d;

  /// Best possible distance within the cell.
  final double max;
}

Xy _centroid(List<Xy> ring) {
  var area = 0.0;
  var x = 0.0;
  var y = 0.0;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i];
    final b = ring[j];
    final f = a.x * b.y - b.x * a.y;
    x += (a.x + b.x) * f;
    y += (a.y + b.y) * f;
    area += f * 3;
  }
  return area == 0 ? ring.first : (x: x / area, y: y / area);
}
