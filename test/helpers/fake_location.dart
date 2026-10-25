import 'dart:async';

import 'package:terrenos/core/location/location_source.dart';

/// Positions supplied by the test.
class FakeLocationSource implements LocationSource {
  LocationAvailability availability = LocationAvailability.granted;
  final _fixes = StreamController<Fix>.broadcast();
  int settingsOpened = 0;

  void emit(double lat, double lon, {double accuracy = 5}) => _fixes.add((
    lat: lat,
    lon: lon,
    accuracyMetres: accuracy,
    at: DateTime.utc(2026, 10, 25),
    mocked: false,
  ));

  @override
  Future<LocationAvailability> ensurePermission() async => availability;

  @override
  Stream<Fix> fixes() => _fixes.stream;

  @override
  Future<void> openSettings() async => settingsOpened++;
}
