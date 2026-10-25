import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/crs/pt_tm06.dart';

/// Reference points converted with PROJ (see the file header).
List<({double lat, double lon, double m, double p})> _reference() =>
    File('test_fixtures/pttm06_reference.csv')
        .readAsLinesSync()
        .where((l) => !l.startsWith('#') && !l.startsWith('lat'))
        .map((line) {
          final v = line.split(',').map(double.parse).toList();
          return (lat: v[0], lon: v[1], m: v[2], p: v[3]);
        })
        .toList();

/// Distance in metres between two nearby lat/lon points.
double _metres(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180 * cos(lat1 * pi / 180);
  return r * sqrt(dLat * dLat + dLon * dLon);
}

void main() {
  final points = _reference();

  test('the fixture covers mainland Portugal', () {
    expect(points, hasLength(50));
  });

  test('WGS84 → PT-TM06 matches PROJ within 1 cm', () {
    for (final ref in points) {
      final got = PtTm06.fromLatLon(ref.lat, ref.lon);
      final error = sqrt(pow(got.m - ref.m, 2) + pow(got.p - ref.p, 2));
      expect(error, lessThan(0.01), reason: '$ref → $got');
    }
  });

  test('PT-TM06 → WGS84 matches PROJ within 1 cm', () {
    for (final ref in points) {
      final got = PtTm06.toLatLon(ref.m, ref.p);
      final error = _metres(ref.lat, ref.lon, got.lat, got.lon);
      expect(error, lessThan(0.01), reason: '$ref → $got');
    }
  });

  test('the projection origin maps to (0, 0)', () {
    final origin = PtTm06.fromLatLon(39.6682583333333, -8.13310833333333);
    expect(origin.m.abs(), lessThan(0.001));
    expect(origin.p.abs(), lessThan(0.001));
  });
}
