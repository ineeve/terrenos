import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/caop/caop.dart';

/// Encodes a ring of (lon, lat) like tool/caop/build_caop.py does.
List<int> _ring(List<(double, double)> points) {
  final out = <int>[];
  var px = 0;
  var py = 0;
  for (final (lon, lat) in points) {
    final x = (lon * 1e5).round();
    final y = (lat * 1e5).round();
    out.addAll([x - px, y - py]);
    px = x;
    py = y;
  }
  return out;
}

List<int> _box(double minLon, double minLat, double maxLon, double maxLat) => [
  (minLon * 1e5).round(),
  (minLat * 1e5).round(),
  (maxLon * 1e5).round(),
  (maxLat * 1e5).round(),
];

/// Two side-by-side freguesias with a 10 m gap between them, the second with
/// a hole; one concelho; one distrito.
final String _json = jsonEncode({
  'edition': 'TEST',
  'scale': 1e5,
  'freguesias': [
    {
      'c': '010101',
      'f': 'São João',
      'm': 'Águeda',
      'd': 'Aveiro',
      'b': _box(-8.50, 40.50, -8.40, 40.60),
      'p': [
        [
          _ring([
            (-8.50, 40.50),
            (-8.40, 40.50),
            (-8.40, 40.60),
            (-8.50, 40.60),
          ]),
        ],
      ],
    },
    {
      'c': '010102',
      'f': 'Fermentelos',
      'm': 'Águeda',
      'd': 'Aveiro',
      'b': _box(-8.39988, 40.50, -8.30, 40.60),
      'p': [
        [
          _ring([
            (-8.39988, 40.50),
            (-8.30, 40.50),
            (-8.30, 40.60),
            (-8.39988, 40.60),
          ]),
          _ring([
            (-8.36, 40.54),
            (-8.34, 40.54),
            (-8.34, 40.56),
            (-8.36, 40.56),
          ]),
        ],
      ],
    },
  ],
  'municipios': [
    {
      'n': 'Águeda',
      'd': 'Aveiro',
      'b': _box(-8.50, 40.50, -8.30, 40.60),
      'p': [
        [
          _ring([
            (-8.50, 40.50),
            (-8.30, 40.50),
            (-8.30, 40.60),
            (-8.50, 40.60),
          ]),
        ],
      ],
    },
  ],
  'distritos': [
    {
      'n': 'Aveiro',
      'b': _box(-8.50, 40.50, -8.30, 40.60),
      'p': [
        [
          _ring([
            (-8.50, 40.50),
            (-8.30, 40.50),
            (-8.30, 40.60),
            (-8.50, 40.60),
          ]),
        ],
      ],
    },
  ],
});

void main() {
  final caop = Caop.parse(_json);

  test('decodes areas and rings', () {
    expect(caop.edition, 'TEST');
    expect(caop.freguesias, hasLength(2));
    expect(caop.freguesias.first.parts.single.single, hasLength(8));
    expect(caop.freguesias.first.parts.single.single[0], -8.50);
    expect(caop.freguesias.first.bounds.maxLat, 40.60);
    expect(caop.concelhos.single.distrito, 'Aveiro');
  });

  test('locates the freguesia containing a point', () {
    expect(caop.locate(40.55, -8.45), (
      distrito: 'Aveiro',
      concelho: 'Águeda',
      freguesia: 'São João',
    ));
    expect(caop.locate(40.52, -8.32)!.freguesia, 'Fermentelos');
  });

  test('a point in a hole is not in that freguesia', () {
    expect(caop.locate(40.55, -8.35), isNull);
  });

  test('a point in a simplification gap gets the nearest freguesia', () {
    // 3 m east of São João's edge, 7 m from Fermentelos.
    expect(caop.locate(40.55, -8.39996)!.freguesia, 'São João');
  });

  test('points far outside are not located', () {
    expect(caop.locate(41.5, -8), isNull);
  });

  test('search ignores accents and case and ranks prefixes first', () {
    expect(caop.search('sao joao').map((a) => a.name), ['São João']);
    expect(caop.search('AGUEDA').map((a) => a.kind), [AreaKind.concelho]);
    expect(caop.search('aveiro').single.kind, AreaKind.distrito);
    expect(caop.search('ment').map((a) => a.name), ['Fermentelos']);
    expect(caop.search('  '), isEmpty);
  });

  test('distance to a boundary is roughly right', () {
    final f = caop.freguesias.first;
    // 0.001° of latitude ≈ 110.5 m north of the top edge.
    expect(f.distanceMetres(40.601, -8.45), closeTo(110.5, 1));
  });
}
