/// Editing a boundary's vertex list, with undo and redo (SPEC.md §3.3,
/// §3.4). Pure Dart: the draw, walk and coordinate screens all edit through
/// this, so every method keeps vertex ids stable (VTX-1).
library;

import 'dart:math';

import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/geometry/planar.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';

/// Which ring is being edited: part index, ring index (0 = outer).
typedef RingRef = ({int part, int ring});

const ({int part, int ring}) outerRing = (part: 0, ring: 0);

class BoundaryEditor {
  /// [usedIds] are ids that must never be issued again: every vertex id in
  /// the property's history, including deleted ones (VTX-1).
  new({
    BoundaryParts initial = const [],
    Iterable<String> usedIds = const [],
    Random? random,
  }) : _parts = _copy(
         initial.isEmpty
             ? [
                 <List<Vertex>>[[]],
               ]
             : initial,
       ),
       _usedIds = {
         ...usedIds,
         for (final part in initial)
           for (final ring in part)
             for (final v in ring) v.id,
       },
       _random = random ?? Random.secure();

  /// At least 50 steps (REG-5).
  static const maxUndo = 100;

  BoundaryParts _parts;
  final Set<String> _usedIds;
  final Random _random;
  final _undo = <BoundaryParts>[];
  final _redo = <BoundaryParts>[];

  BoundaryParts get parts => _parts;
  List<Vertex> ring([RingRef ref = outerRing]) => _parts[ref.part][ref.ring];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Vertex? byId(String id) {
    for (final part in _parts) {
      for (final ring in part) {
        for (final v in ring) {
          if (v.id == id) return v;
        }
      }
    }
    return null;
  }

  /// Adds a vertex at the end of the ring, or after [afterId].
  Vertex add(
    LonLat position, {
    required VertexSource source,
    String? afterId,
    CoordinateInput? input,
    GpsFix? gps,
    RingRef ref = outerRing,
  }) {
    final vertex = _newVertex(position, source, input: input, gps: gps);
    _edit(ref, (ring) {
      final index = afterId == null
          ? ring.length
          : ring.indexWhere((v) => v.id == afterId) + 1;
      if (afterId != null && index == 0) {
        throw ArgumentError.value(afterId, 'afterId', 'No such vertex');
      }
      ring.insert(index, vertex);
    });
    return vertex;
  }

  /// Adds several vertices at the end of the ring as one undo step, e.g.
  /// from a recorded track (REG-3).
  List<Vertex> addAll(
    List<({LonLat position, GpsFix? gps})> points, {
    required VertexSource source,
    RingRef ref = outerRing,
  }) {
    final vertices = [
      for (final p in points) _newVertex(p.position, source, gps: p.gps),
    ];
    _edit(ref, (ring) => ring.addAll(vertices));
    return vertices;
  }

  /// Inserts a vertex into the edge nearest to [position] (VTX-8 option
  /// "into the nearest edge"). With fewer than 3 vertices it is appended.
  Vertex insertIntoNearestEdge(
    LonLat position, {
    required VertexSource source,
    CoordinateInput? input,
    GpsFix? gps,
    RingRef ref = outerRing,
  }) {
    final current = ring(ref);
    if (current.length < 3) {
      return add(position, source: source, input: input, gps: gps, ref: ref);
    }
    final plane = LocalPlane.around([
      position,
      for (final v in current) (lon: v.lon, lat: v.lat),
    ]);
    final p = plane.project(position);
    final xy = [
      for (final v in current) plane.project((lon: v.lon, lat: v.lat)),
    ];
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < xy.length; i++) {
      final d = distanceToSegmentSquared(p, xy[i], xy[(i + 1) % xy.length]);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return add(
      position,
      source: source,
      afterId: current[best].id,
      input: input,
      gps: gps,
      ref: ref,
    );
  }

  /// Moves a vertex, keeping its id. Typed coordinates are kept exactly in
  /// [input]; any other move clears it (SPEC.md §7.1). A GPS fix marks the
  /// vertex as surveyed; moving a surveyed vertex by hand makes it planned
  /// again, because its position no longer comes from the measurement.
  void move(
    String id,
    LonLat position, {
    required VertexSource source,
    CoordinateInput? input,
    GpsFix? gps,
  }) {
    _replace(
      id,
      (v) => Vertex(
        id: v.id,
        lon: position.lon,
        lat: position.lat,
        source: source,
        input: input,
        gps: gps,
      ),
    );
  }

  /// Confirms a vertex on site without moving it (VTX-9 "Keep").
  void confirm(String id, GpsFix gps) {
    _replace(
      id,
      (v) => Vertex(
        id: v.id,
        lon: v.lon,
        lat: v.lat,
        source: v.source,
        input: v.input,
        gps: gps,
      ),
    );
  }

  void delete(String id) {
    for (var p = 0; p < _parts.length; p++) {
      for (var r = 0; r < _parts[p].length; r++) {
        if (_parts[p][r].any((v) => v.id == id)) {
          _edit((
            part: p,
            ring: r,
          ), (ring) => ring.removeWhere((v) => v.id == id));
          return;
        }
      }
    }
    throw ArgumentError.value(id, 'id', 'No such vertex');
  }

  /// Moves the vertex at [from] to position [to] (VTX-14).
  void reorder(int from, int to, {RingRef ref = outerRing}) {
    _edit(ref, (ring) {
      final vertex = ring.removeAt(from);
      ring.insert(to.clamp(0, ring.length), vertex);
    });
  }

  /// Reverses the direction of the ring, keeping the first vertex first.
  void reverse({RingRef ref = outerRing}) {
    _edit(ref, (ring) {
      if (ring.length < 2) return;
      final rest = ring.sublist(1).reversed.toList();
      ring
        ..removeRange(1, ring.length)
        ..addAll(rest);
    });
  }

  /// Makes [id] the first vertex, keeping the order around the ring.
  void startAt(String id, {RingRef ref = outerRing}) {
    _edit(ref, (ring) {
      final index = ring.indexWhere((v) => v.id == id);
      if (index < 0) throw ArgumentError.value(id, 'id', 'No such vertex');
      final rotated = [...ring.sublist(index), ...ring.sublist(0, index)];
      ring
        ..clear()
        ..addAll(rotated);
    });
  }

  /// Replaces the whole boundary, e.g. after simplification or import.
  void replaceAll(BoundaryParts parts) {
    _push();
    _parts = _copy(parts);
    for (final part in parts) {
      for (final ring in part) {
        _usedIds.addAll(ring.map((v) => v.id));
      }
    }
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_parts);
    _parts = _undo.removeLast();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_parts);
    _parts = _redo.removeLast();
  }

  Vertex _newVertex(
    LonLat position,
    VertexSource source, {
    CoordinateInput? input,
    GpsFix? gps,
  }) {
    String id;
    do {
      id = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    } while (!_usedIds.add(id));
    return Vertex(
      id: id,
      lon: position.lon,
      lat: position.lat,
      source: source,
      input: input,
      gps: gps,
    );
  }

  void _replace(String id, Vertex Function(Vertex) change) {
    for (var p = 0; p < _parts.length; p++) {
      for (var r = 0; r < _parts[p].length; r++) {
        final i = _parts[p][r].indexWhere((v) => v.id == id);
        if (i >= 0) {
          _edit((part: p, ring: r), (ring) => ring[i] = change(ring[i]));
          return;
        }
      }
    }
    throw ArgumentError.value(id, 'id', 'No such vertex');
  }

  void _edit(RingRef ref, void Function(List<Vertex> ring) change) {
    final next = _copy(_parts);
    change(next[ref.part][ref.ring]);
    _push();
    _parts = next;
  }

  void _push() {
    _undo.add(_parts);
    if (_undo.length > maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  static BoundaryParts _copy(BoundaryParts parts) => [
    for (final part in parts) [for (final ring in part) List.of(ring)],
  ];
}

/// The outcome of measuring a planned vertex on site (VTX-9).
typedef SurveyComparison = ({
  double distanceMetres,
  double bearingDegrees,
  CompassDirection direction,

  /// Within the measurement's own accuracy the stored position is as good
  /// as the new one, so the app suggests keeping it (SPEC.md §7.3).
  bool suggestKeep,
});

SurveyComparison compareSurvey(Vertex stored, LonLat measured, GpsFix fix) {
  final g = inverse((lon: stored.lon, lat: stored.lat), measured);
  return (
    distanceMetres: g.distanceMetres,
    bearingDegrees: g.bearingDegrees,
    direction: CompassDirection.fromBearing(g.bearingDegrees),
    suggestKeep: g.distanceMetres <= fix.accuracyMetres,
  );
}
