/// The phone's position (SPEC.md §7.3, MAP-4).
///
/// The map shows it with an accuracy circle. Walk mode (PLAN.md T2.1) adds
/// averaging and a foreground service on top of the same source.
library;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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

/// The notification shown while recording in the field (REG-13). While a
/// stream with a notice is listened to, Android keeps it running with the
/// screen off as a foreground service.
@immutable
class RecordingNotice {
  const new({
    required this.title,
    required this.text,
    required this.channelName,
  });

  final String title;
  final String text;

  /// Shown in Android's notification settings for the app.
  final String channelName;
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
  /// With a [notice], they keep coming with the screen off (REG-13).
  Stream<LocationFix> fixes({RecordingNotice? notice});

  /// Asks to show notifications (Android 13+), so the recording notice is
  /// visible. Recording works either way; returns whether it's allowed.
  Future<bool> requestNotifications();

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

  /// Google's fused location first: it also uses Wi-Fi, so the first fix
  /// comes sooner. It refuses to start when Google's location service is
  /// off (Android's "Google Location Accuracy"), even with GPS on; then
  /// Android's own GPS provider is used, which is what surveying needs.
  @override
  Stream<LocationFix> fixes({RecordingNotice? notice}) async* {
    try {
      await for (final p in _positions(notice, locationManager: false)) {
        yield _fix(p);
      }
    } on LocationServiceDisabledException {
      if (!await Geolocator.isLocationServiceEnabled()) rethrow;
      yield* _positions(notice, locationManager: true).map(_fix);
    }
  }

  static Stream<Position> _positions(
    RecordingNotice? notice, {
    required bool locationManager,
  }) => Geolocator.getPositionStream(
    locationSettings: defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            intervalDuration: const Duration(seconds: 1),
            forceLocationManager: locationManager,
            foregroundNotificationConfig: notice == null
                ? null
                : ForegroundNotificationConfig(
                    notificationTitle: notice.title,
                    notificationText: notice.text,
                    notificationChannelName: notice.channelName,
                    // Fixes keep coming with the screen off.
                    enableWakeLock: true,
                    setOngoing: true,
                  ),
          )
        : const LocationSettings(),
  );

  static LocationFix _fix(Position p) => LocationFix(
    lat: p.latitude,
    lon: p.longitude,
    accuracyMetres: p.accuracy,
    at: p.timestamp,
    mocked: p.isMocked,
  );

  @override
  Future<bool> requestNotifications() async =>
      (await Permission.notification.request()).isGranted;

  @override
  Future<void> openSettings(LocationAccess access) async {
    if (access == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
