/// Averaging GPS fixes for one vertex (SPEC.md §7.3, VTX-8, REG-2).
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:terrenos/core/crs/coordinates.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/model/vertex.dart';

/// The averaged position of fixes collected at one spot.
@immutable
class AveragedFix {
  const new({
    required this.lat,
    required this.lon,
    required this.accuracyMetres,
    required this.samples,
    required this.at,
    required this.mocked,
  });

  final double lat;
  final double lon;

  /// The median accuracy of the fixes used. Fixes seconds apart share most
  /// of their error (satellites, atmosphere, multipath), so averaging them
  /// barely improves it; claiming better would mislead the user.
  final double accuracyMetres;

  /// Fixes used after dropping the imprecise ones.
  final int samples;

  /// When the last fix used was taken.
  final DateTime at;

  /// Any fix came from a mock-location app (REG-13, VAL-8).
  final bool mocked;

  /// The `gps` record stored with the vertex (§7.3).
  GpsFix toGpsFix(String deviceId) => GpsFix(
    accuracyMetres: accuracyMetres,
    samples: samples,
    capturedAt: at,
    mocked: mocked,
    deviceId: deviceId,
  );
}

/// Drops fixes whose accuracy is worse than twice the median, then takes
/// the mean weighted by 1/accuracy² (§7.3). `null` without fixes.
AveragedFix? averageFixes(List<LocationFix> fixes) {
  if (fixes.isEmpty) return null;
  final limit = 2 * _median([for (final f in fixes) f.accuracyMetres]);
  final kept = [
    for (final f in fixes)
      if (f.accuracyMetres <= limit) f,
  ];
  var lat = 0.0;
  var lon = 0.0;
  var weights = 0.0;
  for (final f in kept) {
    // A reported accuracy of 0 would get infinite weight.
    final accuracy = f.accuracyMetres < 0.1 ? 0.1 : f.accuracyMetres;
    final w = 1 / (accuracy * accuracy);
    lat += f.lat * w;
    lon += f.lon * w;
    weights += w;
  }
  return AveragedFix(
    lat: roundDegrees(lat / weights),
    lon: roundDegrees(lon / weights),
    accuracyMetres: _median([for (final f in kept) f.accuracyMetres]),
    samples: kept.length,
    at: kept.map((f) => f.at).reduce((a, b) => a.isAfter(b) ? a : b),
    mocked: fixes.any((f) => f.mocked),
  );
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Progress while averaging, for the progress ring (§4.1).
@immutable
class SamplingProgress {
  const new({required this.fraction, required this.fixes, this.latest});

  final double fraction;
  final int fixes;
  final LocationFix? latest;
}

/// Collects fixes from a stream for a while and averages them.
class GpsSampler {
  new(this.fixes);

  /// Default averaging time (SET-6).
  static const defaultDuration = Duration(seconds: 5);

  final Stream<LocationFix> fixes;

  /// Collects for [duration] and averages. Completes with `null` if no fix
  /// arrived, e.g. indoors; or early, with what was collected, when
  /// [stop] completes. Progress is reported every fix and every 100 ms.
  Future<AveragedFix?> sample({
    Duration duration = defaultDuration,
    void Function(SamplingProgress)? onProgress,
    Future<void>? stop,
  }) async {
    final collected = <LocationFix>[];
    final done = Completer<void>();
    // Counted by the ticker rather than a stopwatch, so tests can run it
    // in fake time.
    var elapsed = Duration.zero;
    const tick = Duration(milliseconds: 100);
    void report() => onProgress?.call(
      SamplingProgress(
        fraction: (elapsed.inMicroseconds / duration.inMicroseconds).clamp(
          0,
          1,
        ),
        fixes: collected.length,
        latest: collected.lastOrNull,
      ),
    );
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    final subscription = fixes.listen(
      (fix) {
        collected.add(fix);
        report();
      },
      onError: (Object _) => finish(),
      onDone: finish,
    );
    final ticker = Timer.periodic(tick, (_) {
      elapsed += tick;
      report();
    });
    final timer = Timer(duration, finish);
    unawaited(stop?.then((_) => finish()));
    await done.future;
    timer.cancel();
    ticker.cancel();
    await subscription.cancel();
    if (elapsed >= duration) elapsed = duration;
    report();
    return averageFixes(collected);
  }
}
