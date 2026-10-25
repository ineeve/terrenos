import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/location/gps_averaging.dart';
import 'package:terrenos/core/location/location_source.dart';

LocationFix _fix(
  double lat,
  double lon,
  double accuracy, {
  int second = 0,
  bool mocked = false,
}) => LocationFix(
  lat: lat,
  lon: lon,
  accuracyMetres: accuracy,
  at: DateTime.utc(2026, 10, 25, 12, 0, second),
  mocked: mocked,
);

void main() {
  group('averageFixes (§7.3)', () {
    test('nothing to average', () {
      expect(averageFixes(const []), isNull);
    });

    test('weights by 1/accuracy² and keeps the median accuracy', () {
      final avg = averageFixes([
        _fix(40.2000000, -8.4300000, 2, second: 1),
        _fix(40.2000100, -8.4300100, 4, second: 2),
        _fix(40.2000050, -8.4300050, 3, second: 3),
      ])!;
      // Weights 1/4, 1/16, 1/9.
      const w = [1 / 4, 1 / 16, 1 / 9];
      final lat =
          (40.2 * w[0] + 40.20001 * w[1] + 40.200005 * w[2]) /
          (w[0] + w[1] + w[2]);
      expect(avg.lat, closeTo(lat, 1e-7));
      expect(avg.samples, 3);
      expect(avg.accuracyMetres, 3);
      expect(avg.at, DateTime.utc(2026, 10, 25, 12, 0, 3));
      expect(avg.mocked, isFalse);
    });

    test('drops fixes worse than twice the median accuracy', () {
      final avg = averageFixes([
        _fix(40.2, -8.43, 3),
        _fix(40.2, -8.43, 4),
        _fix(40.2, -8.43, 5),
        // 25 m: far off and imprecise.
        _fix(40.21, -8.42, 25),
      ])!;
      expect(avg.samples, 3);
      expect(avg.lat, closeTo(40.2, 1e-9));
      expect(avg.accuracyMetres, 4);
    });

    test('one mocked fix marks the result (VAL-8)', () {
      final avg = averageFixes([
        _fix(40.2, -8.43, 3),
        _fix(40.2, -8.43, 3, mocked: true),
      ])!;
      expect(avg.mocked, isTrue);
      final gps = avg.toGpsFix('dev1');
      expect(gps.mocked, isTrue);
      expect(gps.samples, 2);
      expect(gps.deviceId, 'dev1');
    });

    test('a zero accuracy does not dominate infinitely', () {
      final avg = averageFixes([
        _fix(40.2, -8.43, 0),
        _fix(40.2001, -8.43, 0.1),
      ])!;
      expect(avg.lat, closeTo(40.20005, 1e-7));
    });

    test('positions are rounded to the stored 7 decimals', () {
      final avg = averageFixes([_fix(40.123456789, -8.987654321, 3)])!;
      expect((avg.lat, avg.lon), (40.1234568, -8.9876543));
    });
  });

  group('GpsSampler', () {
    test('collects for the duration and reports progress', () async {
      final source = StreamController<LocationFix>();
      final progress = <SamplingProgress>[];
      final result = GpsSampler(source.stream).sample(
        duration: const Duration(milliseconds: 400),
        onProgress: progress.add,
      );
      source
        ..add(_fix(40.2, -8.43, 3))
        ..add(_fix(40.2, -8.43, 5));
      final avg = await result;
      expect(avg!.samples, 2);
      expect(progress.last.fraction, 1);
      expect(progress.last.fixes, 2);
      expect(
        progress.map((p) => p.fraction),
        orderedEquals([...progress.map((p) => p.fraction)]..sort()),
      );
      expect(source.hasListener, isFalse);
    });

    test('no fix in time gives nothing', () async {
      final source = StreamController<LocationFix>();
      final avg = await GpsSampler(source.stream)
          .sample(duration: const Duration(milliseconds: 150));
      expect(avg, isNull);
    });

    test('can be stopped early with what it has', () async {
      final source = StreamController<LocationFix>();
      final stop = Completer<void>();
      final result = GpsSampler(source.stream)
          .sample(duration: const Duration(seconds: 30), stop: stop.future);
      source.add(_fix(40.2, -8.43, 3));
      await Future<void>.delayed(Duration.zero);
      stop.complete();
      final avg = await result;
      expect(avg!.samples, 1);
    });

    test('ends when the stream fails, e.g. location turned off', () async {
      final source = StreamController<LocationFix>();
      final result = GpsSampler(source.stream)
          .sample(duration: const Duration(seconds: 30));
      source
        ..add(_fix(40.2, -8.43, 3))
        ..addError(StateError('off'));
      expect((await result)!.samples, 1);
    });
  });
}
