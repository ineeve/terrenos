/// Cities, towns, villages and hamlets of mainland Portugal, from the
/// bundled OpenStreetMap extract (SPEC.md §6.3, ADR 0010). Used for the
/// place names on the map and for map search (MAP-9, MAP-15).
library;

import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/properties/property_query.dart';

const placesAsset = 'assets/places/places.json';

/// Required by the ODbL wherever the place names are shown.
const osmAttribution = '© OpenStreetMap';

/// OpenStreetMap's `place` values that are kept, largest first.
enum PlaceKind {
  city,
  town,
  village,
  hamlet;

  /// The kind for an OSM `place` value, or `null` if it isn't kept.
  static PlaceKind? fromOsm(String value) =>
      values.where((k) => k.name == value).firstOrNull;
}

class Place {
  new({
    required this.name,
    required this.kind,
    required this.x,
    required this.y,
    required this.freguesia,
  }) : folded = foldAccents(name);

  final String name;
  final PlaceKind kind;

  /// Longitude and latitude in 1e-5 degrees, like the CAOP asset.
  final int x;
  final int y;

  /// DICOFRE code of the freguesia the place lies in.
  final String freguesia;

  /// [name] for accent- and case-insensitive search.
  final String folded;

  LatLng get point =>
      LatLng(y / AdminBoundaries.scale, x / AdminBoundaries.scale);
}

class Places {
  new({required this.osmTimestamp, required this.places});

  factory fromJson(Map<String, Object?> json) {
    if (json['format'] != 1) {
      throw FormatException('Unknown places asset format', json['format']);
    }
    return Places(
      osmTimestamp: json['osmTimestamp']! as String,
      places: [
        for (final p in (json['places']! as List).cast<List<Object?>>())
          Place(
            name: p[0]! as String,
            kind: PlaceKind.values[p[1]! as int],
            x: p[2]! as int,
            y: p[3]! as int,
            freguesia: p[4]! as String,
          ),
      ],
    );
  }

  /// Parses the asset text; call it off the UI thread.
  factory parse(String text) =>
      Places.fromJson(jsonDecode(text) as Map<String, Object?>);

  /// When the OpenStreetMap data was extracted.
  final String osmTimestamp;

  /// Most important first: by kind, then by population. The map labels
  /// places in this order, so a bigger place wins when labels overlap.
  final List<Place> places;
}
