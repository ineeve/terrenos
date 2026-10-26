// Builds assets/places/places.json from an OpenStreetMap extract of the
// cities, towns, villages and hamlets of mainland Portugal (SPEC.md §6.3,
// ADR 0010).
//
// Download the extract (about 5 MB, not committed) from Overpass:
//   curl -A terrenos-build https://overpass-api.de/api/interpreter \
//     --data-urlencode 'data=[out:json][timeout:240];
//       node(36.8,-9.6,42.2,-6.1)[place~"^(city|town|village|hamlet)$"][name];
//       out;' -o osm-places.json
//
// Usage:
//   dart run tool/build_places.dart osm-places.json
//
// The box also takes in part of Spain, so only places inside a CAOP
// freguesia are kept; each one records that freguesia's code, which search
// uses to say where a place is. Run it after tool/build_caop.dart.
import 'dart:convert';
import 'dart:io';

import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/places/places.dart';

const _assetPath = 'assets/places/places.json';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/build_places.dart <osm-places.json>');
    exit(2);
  }
  final osm = jsonDecode(File(args.first).readAsStringSync()) as Map;
  final timestamp = (osm['osm3s'] as Map)['timestamp_osm_base'] as String;
  final caop = AdminBoundaries.parse(File(caopAsset).readAsStringSync());

  final kept = <({Place place, int population})>[];
  var outside = 0;
  for (final element
      in (osm['elements'] as List).cast<Map<String, Object?>>()) {
    final tags = (element['tags']! as Map).cast<String, String>();
    final kind = PlaceKind.fromOsm(tags['place']!);
    final name = tags['name']!.trim();
    if (kind == null || name.isEmpty) continue;
    final lat = element['lat']! as num;
    final lon = element['lon']! as num;
    final found = caop.locate(lat.toDouble(), lon.toDouble());
    if (found == null) {
      outside++;
      continue;
    }
    kept.add((
      place: Place(
        name: name,
        kind: kind,
        x: (lon * AdminBoundaries.scale).round(),
        y: (lat * AdminBoundaries.scale).round(),
        freguesia: found.freguesia.code,
      ),
      population: _population(tags['population']),
    ));
  }

  // Most important first, so labels and search results keep this order.
  kept.sort((a, b) {
    final byKind = a.place.kind.index.compareTo(b.place.kind.index);
    if (byKind != 0) return byKind;
    final byPopulation = b.population.compareTo(a.population);
    if (byPopulation != 0) return byPopulation;
    return a.place.folded.compareTo(b.place.folded);
  });

  // The same name twice in one freguesia is one place mapped twice; keep
  // the more important one.
  final seen = <String>{};
  final places = [
    for (final (:place, population: _) in kept)
      if (seen.add('${place.freguesia} ${place.folded}')) place,
  ];

  final json = jsonEncode({
    'format': 1,
    'source':
        'OpenStreetMap place nodes. © OpenStreetMap contributors, ODbL 1.0.',
    'osmTimestamp': timestamp,
    'places': [
      for (final p in places) [p.name, p.kind.index, p.x, p.y, p.freguesia],
    ],
  });
  File(_assetPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(json);

  final counts = {
    for (final kind in PlaceKind.values)
      kind.name: places.where((p) => p.kind == kind).length,
  };
  stdout
    ..writeln('OSM data from $timestamp')
    ..writeln(
      'Kept ${places.length} places $counts; $outside outside mainland '
      'Portugal, ${kept.length - places.length} duplicates',
    )
    ..writeln(
      'Wrote $_assetPath: ${(json.length / 1e6).toStringAsFixed(2)} MB '
      '(${(gzip.encode(utf8.encode(json)).length / 1e6).toStringAsFixed(2)} '
      'MB compressed)',
    );
}

/// OSM populations are free text: "1234", "1 234", "1.234", sometimes
/// with a note. Unknown counts as 0.
int _population(String? value) {
  final digits = RegExp(r'^[\d .,]+').firstMatch(value ?? '')?.group(0);
  return int.tryParse(digits?.replaceAll(RegExp('[ .,]'), '') ?? '') ?? 0;
}
