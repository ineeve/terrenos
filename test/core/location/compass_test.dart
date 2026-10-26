import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/location/compass.dart';

void main() {
  group('arrival at a vertex (VTX-10)', () {
    test('within the GPS accuracy, said once', () {
      final arrival = ArrivalDetector();
      expect(arrival.update(distanceMetres: 12, accuracyMetres: 4), isFalse);
      expect(arrival.arrived, isFalse);
      expect(arrival.update(distanceMetres: 3.9, accuracyMetres: 4), isTrue);
      expect(arrival.arrived, isTrue);
      // GPS jitter at the marker doesn't say it again.
      expect(arrival.update(distanceMetres: 1, accuracyMetres: 4), isFalse);
      expect(arrival.update(distanceMetres: 6.5, accuracyMetres: 4), isFalse);
      expect(arrival.arrived, isTrue);
    });

    test('again only after clearly walking away', () {
      final arrival = ArrivalDetector()
        ..update(distanceMetres: 2, accuracyMetres: 4)
        // Reach 4 m, plus at least 3 m.
        ..update(distanceMetres: 7.1, accuracyMetres: 4);
      expect(arrival.arrived, isFalse);
      expect(arrival.update(distanceMetres: 3, accuracyMetres: 4), isTrue);
    });

    test('never needs closer than 2 m', () {
      expect(ArrivalDetector.reachFor(0.5), 2);
      expect(ArrivalDetector.reachFor(8), 8);
      expect(
        ArrivalDetector().update(distanceMetres: 1.9, accuracyMetres: 0.5),
        isTrue,
      );
    });
  });

  test('an unreliable or coarse compass asks for calibration', () {
    CompassReading reading(double? accuracy) =>
        CompassReading(headingDegrees: 10, accuracyDegrees: accuracy);
    expect(reading(15).needsCalibration, isFalse);
    expect(reading(30).needsCalibration, isFalse);
    expect(reading(45).needsCalibration, isTrue);
    expect(reading(null).needsCalibration, isTrue);
  });
}
