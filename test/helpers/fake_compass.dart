import 'dart:async';

import 'package:terrenos/core/location/compass.dart';

/// A compass the test turns: [point] the phone, or [lose] the reading.
class FakeCompass implements CompassSource {
  final _readings = StreamController<CompassReading?>.broadcast();

  bool get listening => _readings.hasListener;

  void point(double headingDegrees, {double? accuracyDegrees = 15}) =>
      _readings.add(
        CompassReading(
          headingDegrees: headingDegrees,
          accuracyDegrees: accuracyDegrees,
        ),
      );

  void lose() => _readings.add(null);

  @override
  Stream<CompassReading?> readings() => _readings.stream;
}
