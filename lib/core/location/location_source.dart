/// The phone's position (SPEC.md §7.3, MAP-4).
///
/// The map shows it with an accuracy circle. Walk mode (PLAN.md T2.1) adds
/// averaging and a foreground service on top of the same source.
library;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

@immutable
class LocationFix {
  const new({
    required this.lat,
    required this.lon,
    required this.accuracyMetres,
    required this.at,
    this.mocked = false,
  });

  final double lat;
  final double lon;

  /// Estimated horizontal accuracy (68 % confidence radius).
  final double accuracyMetres;
  final DateTime at;

  /// The fix came from a mock-location app (REG-13).
  final bool mocked;

  @override
  bool operator ==(Object other) =>
      other is LocationFix &&
      other.lat == lat &&
      other.lon == lon &&
      other.accuracyMetres == accuracyMetres &&
      other.at == at &&
      other.mocked == mocked;

  @override
  int get hashCode => Object.hash(lat, lon, accuracyMetres, at, mocked);
}

enum LocationAccess {
  granted,

  /// The user hasn't allowed it yet; asking again shows the system dialog.
  denied,

  /// Android won't ask again; only the app settings can change it.
  deniedForever,

  /// Location is turned off for the whole phone.
  serviceOff,
}

abstract interface class LocationSource {
  /// The current state, without asking the user.
  Future<LocationAccess> access();

  /// Asks for permission if Android still allows asking.
  Future<LocationAccess> requestAccess();

  /// Fixes about once a second at the best accuracy, while listened to.
  Stream<LocationFix> fixes();

  /// Opens the phone's location settings or this app's settings, whichever
  /// can fix [access].
  Future<void> openSettings(LocationAccess access);
}

class GeolocatorLocationSource implements LocationSource {
  @override
  Future<LocationAccess> access() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    return _access(await Geolocator.checkPermission());
  }

  @override
  Future<LocationAccess> requestAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return _access(permission);
  }

  static LocationAccess _access(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => LocationAccess.granted,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => LocationAccess.denied,
      };

  @override
  Stream<LocationFix> fixes() =>
      Geolocator.getPositionStream(
        locationSettings: defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(intervalDuration: const Duration(seconds: 1))
            : const LocationSettings(),
      ).map(
        (p) => LocationFix(
          lat: p.latitude,
          lon: p.longitude,
          accuracyMetres: p.accuracy,
          at: p.timestamp,
          mocked: p.isMocked,
        ),
      );

  @override
  Future<void> openSettings(LocationAccess access) async {
    if (access == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
