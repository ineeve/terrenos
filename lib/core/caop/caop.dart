/// Official administrative boundaries, bundled with the app (SPEC.md §6.2).
///
/// Reads `assets/caop/caop.json` (built by `tool/caop/build_caop.py`):
/// coordinates are degrees × `scale`, delta-encoded per ring.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:terrenos/core/format/text.dart';

/// A bounding box in degrees.
typedef Bounds = ({double minLon, double minLat, double maxLon, double maxLat});

/// A place's administrative location (PROP-9).
typedef AdminLocation = ({String distrito, String concelho, String freguesia});

enum AreaKind { distrito, concelho, freguesia }

@immutable
class AdminArea {
  const new({
    required this.kind,
    required this.name,
    required this.bounds,
    required this.parts,
    this.code,
    this.concelho,
    this.distrito,
  });

  final AreaKind kind;
  final String name;
  final String? code;

  /// For freguesias and concelhos.
  final String? concelho;
  final String? distrito;
  final Bounds bounds;

  /// Polygons → rings → `[lon0, lat0, lon1, lat1, …]`; the first ring of
  /// each polygon is the outer boundary.
  final List<List<Float64List>> parts;

  bool boundsContain(double lat, double lon, {double margin = 0}) =>
      lon >= bounds.minLon - margin &&
      lon <= bounds.maxLon + margin &&
      lat >= bounds.minLat - margin &&
      lat <= bounds.maxLat + margin;

  /// Even-odd containment across all rings (holes included).
  bool contains(double lat, double lon) {
    if (!boundsContain(lat, lon)) return false;
    var inside = false;
    for (final polygon in parts) {
      for (final ring in polygon) {
        final n = ring.length ~/ 2;
        for (var i = 0, j = n - 1; i < n; j = i++) {
          final xi = ring[2 * i];
          final yi = ring[2 * i + 1];
          final xj = ring[2 * j];
          final yj = ring[2 * j + 1];
          if ((yi > lat) != (yj > lat) &&
              lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
            inside = !inside;
          }
        }
      }
    }
    return inside;
  }

  /// Approximate distance in metres from a point to the area's boundary,
  /// on a local equirectangular plane (fine at these scales).
  double distanceMetres(double lat, double lon) {
    final kx = 111320 * cos(lat * pi / 180);
    const ky = 110540.0;
    var best = double.infinity;
    for (final polygon in parts) {
      for (final ring in polygon) {
        final n = ring.length ~/ 2;
        for (var i = 0; i < n; i++) {
          final j = (i + 1) % n;
          final ax = (ring[2 * i] - lon) * kx;
          final ay = (ring[2 * i + 1] - lat) * ky;
          final bx = (ring[2 * j] - lon) * kx;
          final by = (ring[2 * j + 1] - lat) * ky;
          final dx = bx - ax;
          final dy = by - ay;
          final len = dx * dx + dy * dy;
          final t = len == 0
              ? 0.0
              : (-(ax * dx + ay * dy) / len).clamp(0.0, 1.0);
          final px = ax + t * dx;
          final py = ay + t * dy;
          best = min(best, px * px + py * py);
        }
      }
    }
    return sqrt(best);
  }
}

class Caop {
  new({
    required this.edition,
    required this.freguesias,
    required this.concelhos,
    required this.distritos,
  });

  /// Parses the asset. Takes about a second for the full country, so call
  /// it in a background isolate.
  factory parse(String json) {
    final data = jsonDecode(json) as Map<String, Object?>;
    final scale = (data['scale']! as num).toDouble();

    Bounds bounds(List<Object?> b) => (
      minLon: (b[0]! as num) / scale,
      minLat: (b[1]! as num) / scale,
      maxLon: (b[2]! as num) / scale,
      maxLat: (b[3]! as num) / scale,
    );

    List<List<Float64List>> parts(List<Object?> encoded) => [
      for (final polygon in encoded)
        [
          for (final ring in polygon! as List<Object?>)
            _decodeRing(ring! as List<Object?>, scale),
        ],
    ];

    List<Map<String, Object?>> list(String key) =>
        (data[key]! as List<Object?>).cast<Map<String, Object?>>();

    return Caop(
      edition: data['edition']! as String,
      freguesias: [
        for (final f in list('freguesias'))
          AdminArea(
            kind: AreaKind.freguesia,
            code: f['c'] as String?,
            name: f['f']! as String,
            concelho: f['m']! as String,
            distrito: f['d']! as String,
            bounds: bounds(f['b']! as List<Object?>),
            parts: parts(f['p']! as List<Object?>),
          ),
      ],
      concelhos: [
        for (final m in list('municipios'))
          AdminArea(
            kind: AreaKind.concelho,
            name: m['n']! as String,
            concelho: m['n']! as String,
            distrito: m['d']! as String,
            bounds: bounds(m['b']! as List<Object?>),
            parts: parts(m['p']! as List<Object?>),
          ),
      ],
      distritos: [
        for (final d in list('distritos'))
          AdminArea(
            kind: AreaKind.distrito,
            name: d['n']! as String,
            distrito: d['n']! as String,
            bounds: bounds(d['b']! as List<Object?>),
            parts: parts(d['p']! as List<Object?>),
          ),
      ],
    );
  }

  final String edition;
  final List<AdminArea> freguesias;
  final List<AdminArea> concelhos;
  final List<AdminArea> distritos;

  /// Boundaries are simplified independently, so neighbouring freguesias
  /// can leave thin gaps; points within this distance of one still match.
  static const borderToleranceMetres = 25.0;

  /// The freguesia containing a point (PROP-9). Points in a simplification
  /// gap get the nearest freguesia within [borderToleranceMetres].
  AdminLocation? locate(double lat, double lon) {
    for (final f in freguesias) {
      if (f.contains(lat, lon)) return _location(f);
    }
    // ~25 m in degrees, generously.
    const margin = 0.0004;
    AdminArea? nearest;
    var nearestDistance = borderToleranceMetres;
    for (final f in freguesias) {
      if (!f.boundsContain(lat, lon, margin: margin)) continue;
      final d = f.distanceMetres(lat, lon);
      if (d <= nearestDistance) {
        nearest = f;
        nearestDistance = d;
      }
    }
    return nearest == null ? null : _location(nearest);
  }

  /// Places whose name matches [query], ignoring case and accents (MAP-9):
  /// distritos first, then concelhos, then freguesias; names starting with
  /// the query before names merely containing it.
  List<AdminArea> search(String query, {int limit = 20}) {
    final q = foldForSearch(query);
    if (q.isEmpty) return const [];
    final starts = <AdminArea>[];
    final contains = <AdminArea>[];
    for (final area in [...distritos, ...concelhos, ...freguesias]) {
      final name = foldForSearch(area.name);
      if (name.startsWith(q)) {
        starts.add(area);
      } else if (name.contains(q)) {
        contains.add(area);
      }
    }
    return [...starts, ...contains].take(limit).toList();
  }

  static AdminLocation _location(AdminArea f) =>
      (distrito: f.distrito!, concelho: f.concelho!, freguesia: f.name);
}

Float64List _decodeRing(List<Object?> encoded, double scale) {
  final out = Float64List(encoded.length);
  var x = 0;
  var y = 0;
  for (var i = 0; i + 1 < encoded.length; i += 2) {
    x += encoded[i]! as int;
    y += encoded[i + 1]! as int;
    out[i] = x / scale;
    out[i + 1] = y / scale;
  }
  return out;
}
