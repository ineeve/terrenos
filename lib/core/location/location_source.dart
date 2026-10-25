/// Where the phone is (SPEC.md §7.3, §7.4).
///
/// An interface so an external Bluetooth GNSS receiver can be added later,
/// and so tests can supply positions.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// One position fix.
typedef Fix = ({
  double lat,
  double lon,

  /// Estimated horizontal accuracy (68 %), in metres.
  double accuracyMetres,
  DateTime at,

  /// Android reported a mock location (VAL-8).
  bool mocked,
});

enum LocationAvailability { granted, denied, deniedForever, serviceDisabled }

abstract interface class LocationSource {
  /// Checks, and if needed asks for, permission to use the location.
  Future<LocationAvailability> ensurePermission();

  /// Fixes at the best accuracy, about once a second.
  Stream<Fix> fixes();

  /// Opens the app's system settings, for permanently denied permission.
  Future<void> openSettings();
}

class GeolocatorLocationSource implements LocationSource {
  /// The `foss` flavour has no Google Play Services, so it uses Android's
  /// own location manager (SPEC.md §5.3).
  const new();

  bool get _withoutPlayServices => appFlavor == 'foss';

  @override
  Future<LocationAvailability> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAvailability.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAvailability.granted,
      LocationPermission.deniedForever => LocationAvailability.deniedForever,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationAvailability.denied,
    };
  }

  @override
  Stream<Fix> fixes() =>
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          intervalDuration: const Duration(seconds: 1),
          forceLocationManager: _withoutPlayServices,
        ),
      ).map(
        (p) => (
          lat: p.latitude,
          lon: p.longitude,
          accuracyMetres: p.accuracy,
          at: p.timestamp,
          mocked: p.isMocked,
        ),
      );

  @override
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }
}
