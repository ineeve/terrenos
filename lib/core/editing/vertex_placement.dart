/// Checks on a vertex before it is added or moved (SPEC.md §7.5, VAL-2,
/// VAL-5), shown while the user types its coordinates.
library;

import 'package:meta/meta.dart';
import 'package:terrenos/core/crs/coordinates.dart';
import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/geometry/planar.dart';
import 'package:terrenos/core/model/vertex.dart';

@immutable
class VertexPlacement {
  const new({
    required this.ring,
    required this.vertexId,
    this.sameAsId,
    this.crossings = const [],
    this.betterAfterId,
  });

  /// The id given to a vertex that doesn't exist yet.
  static const newVertexId = '__new__';

  /// The ring as it would be, with the vertex in place.
  final List<Vertex> ring;
  final String vertexId;

  /// A neighbour at exactly the same position; the vertex would be removed
  /// on save (VAL-5).
  final String? sameAsId;

  /// Edges that would cross because of this vertex (VAL-2).
  final List<Crossing> crossings;

  /// Where a new vertex could go instead without crossing: after this
  /// vertex, on the nearest edge that works.
  final String? betterAfterId;

  bool get crosses => crossings.isNotEmpty;
}

/// Places [position] at the end of [ring], or moves vertex [replacingId]
/// there, and reports what the §7.5 checks find.
VertexPlacement checkPlacement(
  List<Vertex> ring,
  LonLat position, {
  String? replacingId,
}) {
  final id = replacingId ?? VertexPlacement.newVertexId;
  final vertex = Vertex(
    id: id,
    lon: roundDegrees(position.lon),
    lat: roundDegrees(position.lat),
    source: VertexSource.typed,
  );
  final placed = replacingId == null
      ? [...ring, vertex]
      : [
          for (final v in ring)
            if (v.id == replacingId) vertex else v,
        ];
  final index = placed.indexWhere((v) => v.id == id);

  String? sameAsId;
  if (placed.length > 1) {
    for (final neighbour in [
      placed[(index - 1) % placed.length],
      placed[(index + 1) % placed.length],
    ]) {
      if (neighbour.id != id &&
          neighbour.lon == vertex.lon &&
          neighbour.lat == vertex.lat) {
        sameAsId = neighbour.id;
      }
    }
  }

  final crossings = _crossingsAt(placed, id);
  String? betterAfterId;
  if (crossings.isNotEmpty && replacingId == null && sameAsId == null) {
    betterAfterId = _nearestValidEdge(ring, vertex);
  }
  return VertexPlacement(
    ring: placed,
    vertexId: id,
    sameAsId: sameAsId,
    crossings: crossings,
    betterAfterId: betterAfterId,
  );
}

/// Crossings involving an edge of vertex [id]. Crossings the ring already
/// had are not this vertex's fault and are left out.
List<Crossing> _crossingsAt(List<Vertex> ring, String id) {
  if (ring.length < 4) return const [];
  return [
    for (final c in GeometryService.crossings([
      [ring],
    ]))
      if ({c.first.$1, c.first.$2, c.second.$1, c.second.$2}.contains(id)) c,
  ];
}

/// The edge nearest to [vertex] where inserting it makes no crossing.
String? _nearestValidEdge(List<Vertex> ring, Vertex vertex) {
  if (ring.length < 3) return null;
  final plane = LocalPlane.around([
    (lon: vertex.lon, lat: vertex.lat),
    for (final v in ring) (lon: v.lon, lat: v.lat),
  ]);
  final p = plane.project((lon: vertex.lon, lat: vertex.lat));
  String? best;
  var bestDistance = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final candidate = [
      ...ring.sublist(0, i + 1),
      vertex,
      ...ring.sublist(i + 1),
    ];
    if (_crossingsAt(candidate, vertex.id).isNotEmpty) continue;
    final distance = distanceToSegmentSquared(
      p,
      plane.project((lon: a.lon, lat: a.lat)),
      plane.project((lon: b.lon, lat: b.lat)),
    );
    if (distance < bestDistance) {
      bestDistance = distance;
      best = a.id;
    }
  }
  return best;
}
