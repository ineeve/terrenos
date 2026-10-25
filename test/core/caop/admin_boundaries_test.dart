import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';

void main() {
  late AdminBoundaries caop;

  setUpAll(() {
    caop = AdminBoundaries.parse(File(caopAsset).readAsStringSync());
  });

  test('holds the whole of CAOP 2025 for the mainland', () {
    expect(caop.edition, caopEdition);
    expect(caop.distritos, hasLength(18));
    expect(caop.concelhos, hasLength(278));
    expect(caop.freguesias, hasLength(3049));
    expect(caop.levels, hasLength(caop.arcs.length));
    for (final f in caop.freguesias) {
      expect(caop.concelhos[f.code.substring(0, 4)], isNotNull, reason: f.code);
      expect(caop.distritos[f.code.substring(0, 2)], isNotNull, reason: f.code);
      expect(f.arcs.every((i) => i < caop.arcs.length), isTrue);
    }
  });

  test('every border line is classified', () {
    final counts = <BoundaryLevel, int>{};
    for (final level in caop.levels) {
      counts[level] = (counts[level] ?? 0) + 1;
    }
    // From the CAOP 2025 cont_trocos layer.
    expect(counts, {
      BoundaryLevel.freguesia: 5958,
      BoundaryLevel.concelho: 2494,
      BoundaryLevel.distrito: 798,
      BoundaryLevel.outer: 649,
    });
  });

  test('matches the unsimplified boundaries at reference points', () {
    final reference = jsonDecode(
      File('test_fixtures/caop_reference.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final points = (reference['points']! as List).cast<Map<String, Object?>>();
    expect(points, hasLength(greaterThanOrEqualTo(100)));
    for (final point in points) {
      final found = caop.locate(
        point['lat']! as double,
        point['lon']! as double,
      );
      expect(found?.freguesia.code, point['freguesia'], reason: '$point');
    }
  });

  test('finds well-known places', () {
    void expectIn(double lat, double lon, String concelho, String distrito) {
      final found = caop.locate(lat, lon);
      expect(found?.concelho.name, concelho, reason: '$lat, $lon');
      expect(found?.distrito.name, distrito, reason: '$lat, $lon');
    }

    expectIn(38.7076, -9.1365, 'Lisboa', 'Lisboa'); // Praça do Comércio
    expectIn(41.1488, -8.6110, 'Porto', 'Porto'); // Avenida dos Aliados
    expectIn(38.5713, -7.9091, 'Évora', 'Évora'); // Praça do Giraldo
    expectIn(37.0157, -7.9351, 'Faro', 'Faro'); // Sé de Faro
    expectIn(41.8030, -6.7564, 'Bragança', 'Bragança'); // Castelo
    expectIn(40.2085, -8.4265, 'Coimbra', 'Coimbra'); // Universidade
  });

  test('names come with the simplified designation', () {
    final porto = caop.locate(41.1488, -8.6110)!.freguesia;
    expect(porto.code, startsWith('1312'));
    expect(porto.name, isNotEmpty);
    expect(porto.shortName.length, lessThanOrEqualTo(porto.name.length));
  });

  test('is null outside mainland Portugal', () {
    expect(caop.locate(39.5, -10), isNull); // Atlantic
    expect(caop.locate(38.879, -6.97), isNull); // Badajoz, Spain
    expect(caop.locate(40.4168, -3.7038), isNull); // Madrid
    expect(caop.locate(32.65, -16.9), isNull); // Madeira isn't included
  });

  test('rejects an unknown asset format', () {
    expect(() => AdminBoundaries.parse('{"format": 2}'), throwsFormatException);
  });
}
