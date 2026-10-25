/// Fixes the validator offers for a boundary (SPEC.md §3.5): swapping
/// coordinates typed the wrong way round (VAL-6), simplifying a boundary
/// with too many vertices (VAL-9), and orienting rings for export (VAL-4).
library;

import 'package:terrenos/core/crs/coordinates.dart';
import 'package:terrenos/core/crs/pt_tm06.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';

/// Swaps latitude and longitude of vertices [ids], or M and P when they
/// were typed in PT-TM06, keeping the typed values exactly (VAL-6).
BoundaryParts swapCoordinates(BoundaryParts parts, Set<String> ids) => [
  for (final part in parts)
    [
      for (final ring in part)
        [
          for (final v in ring)
            if (ids.contains(v.id)) _swapped(v) else v,
        ],
    ],
];

Vertex _swapped(Vertex v) {
  final input = v.input;
  if (input != null && input.crs == PtTm06.epsg) {
    // M and P swapped: the typed values move to the other field.
    final position = PtTm06.toLatLon(input.y, input.x);
    return Vertex(
      id: v.id,
      lon: roundDegrees(position.lon),
      lat: roundDegrees(position.lat),
      source: v.source,
      input: CoordinateInput(crs: input.crs, x: input.y, y: input.x),
      gps: v.gps,
    );
  }
  return Vertex(
    id: v.id,
    lon: v.lat,
    lat: v.lon,
    source: v.source,
    input: input == null
        ? null
        : CoordinateInput(crs: input.crs, x: input.y, y: input.x),
    gps: v.gps,
  );
}

/// The boundary simplified just enough to have at most [maxVertices]
/// (VAL-9). The tolerance starts at 10 cm and doubles until it fits, so the
/// shape changes as little as possible. Kept vertices keep their ids.
({BoundaryParts parts, double toleranceMetres}) simplifyToFit(
  BoundaryParts parts, {
  int maxVertices = TooManyVertices.max,
}) {
  if (_count(parts) <= maxVertices) return (parts: parts, toleranceMetres: 0);
  for (var tolerance = 0.1; ; tolerance *= 2) {
    final simplified = [
      for (final part in parts)
        [
          for (final ring in part)
            GeometryService.simplifyRing(ring, tolerance),
        ],
    ];
    // Rings never drop below a triangle, so give up past 1 km.
    if (_count(simplified) <= maxVertices || tolerance >= 1000) {
      return (parts: simplified, toleranceMetres: tolerance);
    }
  }
}

int _count(BoundaryParts parts) => parts.fold(
  0,
  (sum, part) => sum + part.fold(0, (s, ring) => s + ring.length),
);

/// Rings oriented as RFC 7946 requires: outer rings counter-clockwise,
/// holes clockwise (VAL-4). Stored boundaries keep the order the user gave
/// the vertices, because labels like V2 follow it; exports apply this, and
/// close each ring by repeating its first position (ADR 0009).
BoundaryParts orientedForExport(BoundaryParts parts) => [
  for (final part in parts)
    [
      for (final (r, ring) in part.indexed)
        if (ring.length < 3 ||
            GeometryService.isCounterClockwise(ring) == (r == 0))
          ring
        else
          ring.reversed.toList(),
    ],
];

/// A GPS vertex that is imprecise or came from a mock location (VAL-8).
bool isLowConfidence(
  Vertex v, {
  double thresholdMetres = GeometryValidator.defaultAccuracyThresholdMetres,
}) {
  final gps = v.gps;
  return gps != null && (gps.mocked || gps.accuracyMetres > thresholdMetres);
}
