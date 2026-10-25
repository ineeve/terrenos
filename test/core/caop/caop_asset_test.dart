import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/caop/caop.dart';

/// Checks the real bundled asset (spike S3, PLAN.md): known places resolve to
/// the right freguesia/concelho, and lookups are fast.
void main() {
  late Caop caop;
  late Duration parseTime;

  setUpAll(() {
    final watch = Stopwatch()..start();
    caop = Caop.parse(File('assets/caop/caop.json').readAsStringSync());
    parseTime = watch.elapsed;
  });

  test('covers every mainland area', () {
    expect(caop.edition, 'CAOP2025');
    expect(caop.distritos, hasLength(18));
    expect(caop.concelhos, hasLength(278));
    expect(caop.freguesias.length, greaterThan(3000));
  });

  const places = [
    // Avenida dos Aliados, Porto.
    (41.1496, -8.6109, 'Porto', 'Porto'),

    // Praça do Comércio, Lisboa.
    (38.7077, -9.1365, 'Lisboa', 'Lisboa'),

    // Praça do Giraldo, Évora.
    (38.5714, -7.9070, 'Évora', 'Évora'),

    // Sé de Faro.
    (37.0124, -7.9354, 'Faro', 'Faro'),

    // Mirandela town centre.
    (41.4870, -7.1803, 'Mirandela', 'Bragança'),

    // Sé de Viseu.
    (40.6610, -7.9105, 'Viseu', 'Viseu'),
  ];

  for (final (lat, lon, concelho, distrito) in places) {
    test('$lat, $lon is in $concelho ($distrito)', () {
      final location = caop.locate(lat, lon);
      expect(location, isNotNull);
      expect(location!.concelho, concelho);
      expect(location.distrito, distrito);
    });
  }

  test('the sea and Spain are not located', () {
    expect(caop.locate(39.5, -9.8), isNull); // Atlantic
    expect(caop.locate(40.4168, -3.7038), isNull); // Madrid
  });

  test('parsing and lookups are fast enough (S3)', () {
    final watch = Stopwatch()..start();
    for (final (lat, lon, _, _) in places) {
      caop.locate(lat, lon);
    }
    final perLookup = watch.elapsedMicroseconds / places.length;
    // Budgets with headroom for slow CI machines; measured values are
    // recorded in ADR 0006.
    expect(perLookup, lessThan(50000));
    expect(parseTime.inMilliseconds, lessThan(10000));
  });

  test('search finds places by name without accents', () {
    final results = caop.search('sao joao da madeira');
    expect(results.first.name, 'São João da Madeira');
    expect(results.first.kind, AreaKind.concelho);
  });
}
