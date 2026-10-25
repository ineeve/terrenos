import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:terrenos/core/crs/coordinates.dart';
import 'package:terrenos/core/crs/pt_tm06.dart';

String _nbsp(String s) => s.replaceAll(' ', ' ');

void main() {
  setUpAll(initializeDateFormatting);

  group('parseNumber', () {
    const cases = {
      '41.15835': 41.15835,
      '41,15835': 41.15835,
      '-8.6285': -8.6285,
      '−8,6285': -8.6285, // Unicode minus, as in some PDFs
      '+12': 12.0,
      '-41 234,56': -41234.56,
      '-41 234,56': -41234.56,
      '164.321,78': 164321.78,
      '164,321.78': 164321.78,
      '1,234,567': 1234567.0,
      '.5': 0.5,
      '  7  ': 7.0,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test('"$key"', () => expect(parseNumber(key), Parsed.value(value)));
    }

    for (final bad in ['abc', '1,2,3', '41.1.5', '--8', '8-', '1,23,45.6']) {
      test('rejects "$bad"', () {
        expect(
          parseNumber(bad),
          const Parsed.error(CoordinateError.notANumber),
        );
      });
    }

    test('empty input', () {
      expect(parseNumber('  '), const Parsed.error(CoordinateError.empty));
    });
  });

  group('parseDecimalDegrees', () {
    test('checks the range for each axis', () {
      expect(
        parseDecimalDegrees('91', CoordinateAxis.latitude).error,
        CoordinateError.outOfRange,
      );
      expect(parseDecimalDegrees('91', CoordinateAxis.longitude).value, 91);
      expect(
        parseDecimalDegrees('-181', CoordinateAxis.longitude).error,
        CoordinateError.outOfRange,
      );
    });
  });

  group('parseDms', () {
    const lat = 41 + 9 / 60 + 30.06 / 3600;
    const lon = -(8 + 37 / 60 + 42.6 / 3600);

    final latitudes = [
      '41°09\'30.06"N',
      '41º09’30,06”N',
      '41°9′30.06″ N',
      'N 41 09 30.06',
      '41 9 30,06',
      'n41°09\'30.06"',
    ];
    for (final input in latitudes) {
      test('latitude "$input"', () {
        expect(
          parseDms(input, CoordinateAxis.latitude).value,
          closeTo(lat, 1e-9),
        );
      });
    }

    final longitudes = [
      '8°37\'42.60"W',
      '8°37\'42,6"O',
      'W 8 37 42.6',
      '-8°37\'42.6"',
      '−8 37 42.6',
      "8°37.71'W",
    ];
    for (final input in longitudes) {
      test('longitude "$input"', () {
        expect(
          parseDms(input, CoordinateAxis.longitude).value,
          closeTo(lon, 1e-9),
        );
      });
    }

    test('degrees only and an east longitude', () {
      expect(parseDms('41°', CoordinateAxis.latitude).value, 41);
      expect(parseDms('6 E', CoordinateAxis.longitude).value, 6);
      expect(parseDms('6 L', CoordinateAxis.longitude).value, 6);
      expect(parseDms('37 S', CoordinateAxis.latitude).value, -37);
    });

    test('errors', () {
      expect(
        parseDms('', CoordinateAxis.latitude).error,
        CoordinateError.empty,
      );
      expect(
        parseDms('41 60 0 N', CoordinateAxis.latitude).error,
        CoordinateError.minutesOrSecondsTooLarge,
      );
      expect(
        parseDms('41 9 60', CoordinateAxis.latitude).error,
        CoordinateError.minutesOrSecondsTooLarge,
      );
      expect(
        parseDms('8 37 42 N', CoordinateAxis.longitude).error,
        CoordinateError.wrongHemisphere,
      );
      expect(
        parseDms('41 9 30 W', CoordinateAxis.latitude).error,
        CoordinateError.wrongHemisphere,
      );
      expect(
        parseDms('-8 37 42 W', CoordinateAxis.longitude).error,
        CoordinateError.notANumber,
      );
      expect(
        parseDms('41.5 30', CoordinateAxis.latitude).error,
        CoordinateError.notANumber,
      );
      expect(
        parseDms('1 2 3 4', CoordinateAxis.latitude).error,
        CoordinateError.notANumber,
      );
      expect(
        parseDms('41x', CoordinateAxis.latitude).error,
        CoordinateError.notANumber,
      );
      expect(
        parseDms('95 N', CoordinateAxis.latitude).error,
        CoordinateError.outOfRange,
      );
    });
  });

  group('formatting', () {
    test('decimal degrees use 7 decimals and the locale separator', () {
      expect(formatDecimalDegrees(41.15835, 'en'), '41.1583500');
      expect(formatDecimalDegrees(-8.6285, 'pt'), '-8,6285000');
    });

    test('DMS uses O for west in Portuguese and W in English', () {
      expect(
        formatDms(41.158350, CoordinateAxis.latitude, 'en'),
        '41°09\'30.06"N',
      );
      expect(
        formatDms(-8.6285, CoordinateAxis.longitude, 'en'),
        '8°37\'42.60"W',
      );
      expect(
        formatDms(-8.6285, CoordinateAxis.longitude, 'pt'),
        '8°37\'42,60"O',
      );
      expect(formatDms(-37.1, CoordinateAxis.latitude, 'pt'), '37°06\'00,00"S');
    });

    test('DMS rounding carries into minutes and degrees', () {
      expect(
        formatDms(40 + 59.99999999 / 60, CoordinateAxis.latitude, 'en'),
        '41°00\'00.00"N',
      );
    });

    test('DMS output parses back to the same value', () {
      for (final v in [41.1583500, 36.9500001, 42.1499999]) {
        final text = formatDms(v, CoordinateAxis.latitude, 'pt');
        expect(
          parseDms(text, CoordinateAxis.latitude).value,
          closeTo(v, 0.005 / 3600),
        );
      }
    });

    test('metres group thousands per locale, or not at all', () {
      expect(formatMetres(-41234.56, 'pt'), _nbsp('-41 234,56'));
      expect(formatMetres(-41234.56, 'en'), '-41,234.56');
      expect(formatMetres(164321.784, 'pt', grouping: false), '164321,78');
    });
  });

  group('checkPair (§7.5)', () {
    test('a point in Portugal raises nothing', () {
      final check = checkPair(CoordinateSystem.wgs84, 41.15835, -8.6285);
      expect(check.outsidePortugal, isFalse);
      expect(check.suggestNegativeLongitude, isFalse);
      expect(check.suggestSwap, isFalse);
    });

    test('a positive longitude suggests the negative one', () {
      final check = checkPair(CoordinateSystem.wgs84, 41.15835, 8.6285);
      expect(check.outsidePortugal, isTrue);
      expect(check.suggestNegativeLongitude, isTrue);
      expect(check.suggestSwap, isFalse);
    });

    test('swapped lat/lon suggests a swap', () {
      final check = checkPair(CoordinateSystem.wgs84, -8.6285, 41.15835);
      expect(check.suggestSwap, isTrue);
    });

    test('PT-TM06 values are converted and swaps detected', () {
      final faro = PtTm06.fromLatLon(37.0194, -7.9304);
      final ok = checkPair(CoordinateSystem.ptTm06, faro.m, faro.p);
      expect(ok.outsidePortugal, isFalse);
      expect(ok.lat, closeTo(37.0194, 1e-7));

      // Swapped, Faro's M/P land in the Atlantic.
      final swapped = checkPair(CoordinateSystem.ptTm06, faro.p, faro.m);
      expect(swapped.outsidePortugal, isTrue);
      expect(swapped.suggestSwap, isTrue);
    });

    test('a swap that still lands in Portugal is not detectable', () {
      // Porto's values swapped fall near the Spanish border, still inside
      // the tolerance, so no warning is raised; the preview pin shows it.
      final porto = PtTm06.fromLatLon(41.15835, -8.6285);
      expect(
        checkPair(CoordinateSystem.ptTm06, porto.p, porto.m).outsidePortugal,
        isFalse,
      );
    });

    test('far away points get no suggestion', () {
      final check = checkPair(CoordinateSystem.wgs84, 48.85, 2.35); // Paris
      expect(check.outsidePortugal, isTrue);
      expect(check.suggestNegativeLongitude, isFalse);
      expect(check.suggestSwap, isFalse);
    });

    test('absurd PT-TM06 values are outside without suggestions', () {
      final check = checkPair(CoordinateSystem.ptTm06, 50000000, -30000000);
      expect(check.outsidePortugal, isTrue);
      expect(check.suggestSwap, isFalse);
    });
  });

  test('rounding helpers', () {
    expect(roundDegrees(41.123456789), 41.1234568);
    expect(roundMetres(-41234.565), -41234.57);
  });
}
