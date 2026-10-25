/// Distritos, concelhos and freguesias of mainland Portugal, from the bundled
/// CAOP asset (SPEC.md §6.2, ADR 0007).
///
/// The asset stores each boundary line once, as an "arc" shared by the two
/// areas on either side; a freguesia is the list of its arcs. This keeps
/// neighbouring freguesias gap-free after simplification and lets the map
/// draw every border exactly once. Built by `tool/build_caop.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The CAOP edition in the asset; shown in the attribution.
const caopEdition = 2025;

const caopAsset = 'assets/caop/caop.json';

/// The highest administrative level a boundary line separates.
enum BoundaryLevel {
  /// The coast, the border with Spain, or estuaries outside any freguesia.
  outer,
  distrito,
  concelho,
  freguesia,
}

@immutable
class AdminArea {
  const new(this.code, this.name);

  /// DICO-style code: 2 digits for a distrito, 4 for a concelho.
  final String code;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is AdminArea && other.code == code && other.name == name;

  @override
  int get hashCode => Object.hash(code, name);

  @override
  String toString() => '$code $name';
}

class Freguesia {
  new({
    required this.code,
    required this.name,
    required this.shortName,
    required this.bounds,
    required this.arcs,
  });

  /// DICOFRE code, 6 digits: distrito, concelho, freguesia.
  final String code;

  /// Official name, e.g. "União das freguesias de Recardães e Espinhel".
  final String name;

  /// CAOP's simplified name, e.g. "Recardães e Espinhel".
  final String shortName;

  /// West, south, east, north in 1e-5 degrees.
  final Int32List bounds;

  /// Indices into [AdminBoundaries.arcs].
  final Int32List arcs;
}

/// Where a point lies.
@immutable
class AdminLocation {
  const new({
    required this.distrito,
    required this.concelho,
    required this.freguesia,
  });

  final AdminArea distrito;
  final AdminArea concelho;
  final Freguesia freguesia;
}

class AdminBoundaries {
  new({
    required this.edition,
    required this.distritos,
    required this.concelhos,
    required this.freguesias,
    required this.levels,
    required this.arcs,
  });

  factory fromJson(Map<String, Object?> json) {
    if (json['format'] != 1) {
      throw FormatException('Unknown CAOP asset format', json['format']);
    }
    Map<String, AdminArea> areas(String key) => {
      for (final entry in (json[key]! as List).cast<List<Object?>>())
        entry[0]! as String: AdminArea(
          entry[0]! as String,
          entry[1]! as String,
        ),
    };

    final levels = <BoundaryLevel>[];
    final arcs = <Int32List>[];
    for (final arc in (json['arcs']! as List).cast<List<Object?>>()) {
      levels.add(BoundaryLevel.values[arc[0]! as int]);
      // Delta-encoded: the first point, then differences from the last.
      final points = Int32List(arc.length - 1);
      var x = 0;
      var y = 0;
      for (var i = 1; i < arc.length; i += 2) {
        x += arc[i]! as int;
        y += arc[i + 1]! as int;
        points[i - 1] = x;
        points[i] = y;
      }
      arcs.add(points);
    }

    return AdminBoundaries(
      edition: json['edition']! as int,
      distritos: areas('distritos'),
      concelhos: areas('concelhos'),
      freguesias: [
        for (final f in (json['freguesias']! as List).cast<List<Object?>>())
          Freguesia(
            code: f[0]! as String,
            name: f[1]! as String,
            shortName: f[2]! as String,
            bounds: Int32List.fromList((f[3]! as List).cast<int>()),
            arcs: Int32List.fromList((f[4]! as List).cast<int>()),
          ),
      ],
      levels: levels,
      arcs: arcs,
    );
  }

  /// Parses the asset text: 20–40 ms on a desktop and several times that
  /// on a phone, so call it off the UI thread.
  factory parse(String text) =>
      AdminBoundaries.fromJson(jsonDecode(text) as Map<String, Object?>);

  /// Coordinates are stored as integers in units of 1e-5 degrees (≈ 1 m).
  static const scale = 100000;

  final int edition;
  final Map<String, AdminArea> distritos;
  final Map<String, AdminArea> concelhos;
  final List<Freguesia> freguesias;

  /// [levels] and [arcs] run in parallel. Each arc is a polyline of
  /// interleaved longitude and latitude in 1e-5 degrees.
  final List<BoundaryLevel> levels;
  final List<Int32List> arcs;

  /// The freguesia containing the point, or `null` outside mainland
  /// Portugal. A point exactly on a border may match either side.
  AdminLocation? locate(double lat, double lon) {
    final x = lon * scale;
    final y = lat * scale;
    for (final freguesia in freguesias) {
      final b = freguesia.bounds;
      if (x < b[0] || y < b[1] || x > b[2] || y > b[3]) continue;
      if (!_contains(freguesia, x, y)) continue;
      final code = freguesia.code;
      return AdminLocation(
        distrito: distritos[code.substring(0, 2)]!,
        concelho: concelhos[code.substring(0, 4)]!,
        freguesia: freguesia,
      );
    }
    return null;
  }

  /// Even-odd ray casting over every edge of the freguesia. Rings don't
  /// need to be assembled: each crossing toggles inside/outside whatever
  /// ring the edge belongs to.
  bool _contains(Freguesia freguesia, double x, double y) {
    var inside = false;
    for (final index in freguesia.arcs) {
      final points = arcs[index];
      for (var i = 2; i < points.length; i += 2) {
        final x1 = points[i - 2].toDouble();
        final y1 = points[i - 1].toDouble();
        final x2 = points[i].toDouble();
        final y2 = points[i + 1].toDouble();
        if ((y1 > y) != (y2 > y) && x < (x2 - x1) * (y - y1) / (y2 - y1) + x1) {
          inside = !inside;
        }
      }
    }
    return inside;
  }
}
