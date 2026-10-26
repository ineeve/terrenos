/// Offline search over place names: distritos, concelhos and freguesias
/// from CAOP, and cities, towns, villages and hamlets from OpenStreetMap
/// (MAP-9). Accent- and case-insensitive.
library;

import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'package:meta/meta.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/places/places.dart';
import 'package:terrenos/core/properties/property_query.dart';

/// What a search result is, most important first within a match quality.
enum PlaceResultKind {
  distrito,
  concelho,
  city,
  town,
  freguesia,
  village,
  hamlet;

  static PlaceResultKind of(PlaceKind kind) => switch (kind) {
    PlaceKind.city => city,
    PlaceKind.town => town,
    PlaceKind.village => village,
    PlaceKind.hamlet => hamlet,
  };
}

@immutable
class PlaceResult {
  const new({
    required this.name,
    required this.kind,
    required this.centre,
    this.where,
    this.southWest,
    this.northEast,
  });

  final String name;
  final PlaceResultKind kind;

  /// Where the place is, e.g. "Pombeiro da Beira, Arganil"; `null` for a
  /// distrito.
  final String? where;

  final LatLng centre;

  /// The area's bounding box, for administrative areas; `null` for a
  /// point.
  final LatLng? southWest;
  final LatLng? northEast;
}

class PlaceSearch {
  new(AdminBoundaries caop, Places places) {
    // Bounding boxes of concelhos and distritos, from their freguesias.
    final boxes = <String, List<int>>{};
    void grow(String code, List<int> b) {
      final box = boxes[code];
      if (box == null) {
        boxes[code] = [...b];
      } else {
        box[0] = min(box[0], b[0]);
        box[1] = min(box[1], b[1]);
        box[2] = max(box[2], b[2]);
        box[3] = max(box[3], b[3]);
      }
    }

    final freguesias = <String, Freguesia>{};
    for (final f in caop.freguesias) {
      freguesias[f.code] = f;
      grow(f.code.substring(0, 2), f.bounds);
      grow(f.code.substring(0, 4), f.bounds);
    }

    PlaceResult area(
      String name,
      PlaceResultKind kind,
      List<int> box,
      String? where,
    ) {
      LatLng at(int x, int y) =>
          LatLng(y / AdminBoundaries.scale, x / AdminBoundaries.scale);
      return PlaceResult(
        name: name,
        kind: kind,
        where: where,
        centre: at((box[0] + box[2]) ~/ 2, (box[1] + box[3]) ~/ 2),
        southWest: at(box[0], box[1]),
        northEast: at(box[2], box[3]),
      );
    }

    for (final d in caop.distritos.values) {
      if (boxes[d.code] case final box?) {
        _add(d.name, area(d.name, PlaceResultKind.distrito, box, null));
      }
    }
    for (final c in caop.concelhos.values) {
      if (boxes[c.code] case final box?) {
        final distrito = caop.distritos[c.code.substring(0, 2)]?.name;
        _add(c.name, area(c.name, PlaceResultKind.concelho, box, distrito));
      }
    }
    for (final f in caop.freguesias) {
      final concelho = caop.concelhos[f.code.substring(0, 4)]?.name;
      final result = area(
        f.shortName,
        PlaceResultKind.freguesia,
        f.bounds,
        concelho,
      );
      _add(f.shortName, result);
      // Also found by the official name, e.g. "União das freguesias de …".
      if (f.name != f.shortName) _add(f.name, result);
    }
    for (final p in places.places) {
      final freguesia = freguesias[p.freguesia];
      final concelho = caop.concelhos[p.freguesia.substring(0, 4)]?.name;
      final parish = freguesia?.shortName;
      _add(
        p.name,
        PlaceResult(
          name: p.name,
          kind: PlaceResultKind.of(p.kind),
          where: [
            if (parish != null && foldAccents(parish) != p.folded) parish,
            ?concelho,
          ].join(', '),
          centre: p.point,
        ),
      );
    }
  }

  /// Queries shorter than this find nothing, to keep the list useful.
  static const minQueryLength = 2;

  final _names = <String>[];
  final _results = <PlaceResult>[];

  void _add(String name, PlaceResult result) {
    _names.add(foldAccents(name));
    _results.add(result);
  }

  /// Up to [limit] places matching [query]: exact names first, then names
  /// starting with it, then names with a word starting with it, then any
  /// other match. Ties go to the more important kind of place, then to the
  /// bigger place.
  List<PlaceResult> search(String query, {int limit = 30}) {
    final q = foldAccents(query.trim());
    if (q.length < minQueryLength) return const [];
    final found = <({int quality, int index})>[];
    for (var i = 0; i < _names.length; i++) {
      final name = _names[i];
      final at = name.indexOf(q);
      if (at < 0) continue;
      final quality = name.length == q.length
          ? 0
          : at == 0
          ? 1
          : _wordStart(name, q)
          ? 2
          : 3;
      found.add((quality: quality, index: i));
    }
    found.sort((a, b) {
      final byQuality = a.quality.compareTo(b.quality);
      if (byQuality != 0) return byQuality;
      final byKind = _results[a.index].kind.index.compareTo(
        _results[b.index].kind.index,
      );
      if (byKind != 0) return byKind;
      return a.index.compareTo(b.index);
    });
    final results = <PlaceResult>[];
    for (final f in found) {
      final result = _results[f.index];
      // A freguesia found by both its names is listed once.
      if (results.any((r) => identical(r, result))) continue;
      results.add(result);
      if (results.length == limit) break;
    }
    return results;
  }

  static bool _wordStart(String name, String q) {
    for (var at = name.indexOf(q); at > 0; at = name.indexOf(q, at + 1)) {
      if (const {' ', '-', '(', "'"}.contains(name[at - 1])) return true;
    }
    return false;
  }
}
