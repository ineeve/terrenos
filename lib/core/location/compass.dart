/// The phone's compass, for the arrow in Go to vertex (VTX-10), and when
/// the user has reached the vertex.
library;

import 'dart:math';

import 'package:flutter_compass/flutter_compass.dart';
import 'package:meta/meta.dart';

/// Where the top of the phone points, in degrees clockwise from north.
@immutable
class CompassReading {
  const new({required this.headingDegrees, this.accuracyDegrees});

  final double headingDegrees;

  /// ± degrees; `null` when the sensor says it is unreliable, which
  /// usually means it needs calibrating.
  final double? accuracyDegrees;

  /// Worse than this, the user is asked to calibrate the compass.
  static const calibrateAbove = 30.0;

  bool get needsCalibration =>
      accuracyDegrees == null || accuracyDegrees! > calibrateAbove;
}

/// An interface so tests can turn the phone.
abstract interface class CompassSource {
  /// Readings while listened to; `null` readings, or none at all, on a
  /// phone without a compass.
  Stream<CompassReading?> readings();
}

/// Android's rotation vector sensor through flutter_compass (ADR 0011).
/// Headings are magnetic; the declination in mainland Portugal (about 1–2°
/// west) is far below a phone compass's own error, so it isn't corrected.
class PhoneCompass implements CompassSource {
  const new();

  @override
  Stream<CompassReading?> readings() =>
      (FlutterCompass.events ?? const Stream<CompassEvent>.empty()).map(
        (e) => switch (e.heading) {
          null => null,
          final heading => CompassReading(
            headingDegrees: heading % 360,
            accuracyDegrees: e.accuracy,
          ),
        },
      );
}

/// Says once that the user has reached a vertex: when they come within the
/// GPS accuracy of it (VTX-10), but never closer than [minReachMetres],
/// since a phone claiming ±1 m isn't that precise. After that it stays
/// quiet until the user has clearly walked away again, so the GPS jitter
/// at the marker doesn't buzz again and again.
class ArrivalDetector {
  static const minReachMetres = 2.0;

  bool _arrived = false;

  bool get arrived => _arrived;

  /// How close counts as arrived for a fix with this accuracy.
  static double reachFor(double accuracyMetres) =>
      max(accuracyMetres, minReachMetres);

  /// `true` only on the update where the user arrives.
  bool update({
    required double distanceMetres,
    required double accuracyMetres,
  }) {
    final reach = reachFor(accuracyMetres);
    if (!_arrived) {
      if (distanceMetres <= reach) return _arrived = true;
      return false;
    }
    // Leaving needs a clear margin beyond the reach.
    if (distanceMetres > reach + max(3, reach / 2)) _arrived = false;
    return false;
  }
}
