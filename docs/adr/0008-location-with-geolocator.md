# 0008 — Location with geolocator; asked for only on request

- **Status:** accepted (M1, T1.2, 2026-10-25)
- **Refines:** SPEC.md §5.1 (Location), MAP-4

## Decision

- `geolocator` 14 behind a `LocationSource` interface
  (`lib/core/location/location_source.dart`), so tests use a fake and walk
  mode (T2.1) can build on it.
- Permission is requested only when the user taps "centre on me", never at
  start. If it was already granted, the map shows the position straight
  away. "While in use" only; no background location.
- GPS stops while the app is in the background and starts again when it
  returns, which also picks up a permission granted in the system settings.
- The map shows the CAOP boundaries by zoom: distritos always, concelhos
  from z9, freguesias from z12. They can be switched off in the layers sheet
  (not remembered across restarts yet).

## Consequences

- **`foss` flavour:** `geolocator_android` always includes Google's
  `play-services-location`, which F-Droid doesn't accept. T4.5 (or the
  F-Droid work) must exclude it from `foss` and use Android's
  `LocationManager` there (`AndroidSettings(forceLocationManager: true)`),
  or switch plugins for that flavour.
- `geolocator_linux` brings in `dbus`, `geoclue` and `gsettings`. They are
  MPL-2.0, which SPEC.md §5.3 allows, but their licence text mentions the GPL
  as a possible secondary licence, so they are in the reviewed allow-list of
  `tool/check_licenses.dart`. The Android app doesn't include them.
- Spike S6 (500 polygons and 50 000 vertices at 60 fps on the reference
  phone) still needs a phone. The CAOP overlay adds up to 9 899 lines and
  263 000 points at z12+, culled and simplified by flutter_map; it is part
  of what S6 should measure.

## Update (T2.1, 2026-10-25)

- Walk mode records through `geolocator`'s foreground service with an
  ongoing notification (REG-13). Since Android 14 that needs the
  `FOREGROUND_SERVICE_LOCATION` permission; the notification needs
  `POST_NOTIFICATIONS`, asked for with `permission_handler`.
- `permission_handler` is pinned to 12.x: 13.x requires `compileSdk` 37,
  and Flutter 3.47 builds against 36.
- Google's fused location refuses to start when "Google Location
  Accuracy" is off, even with GPS on (seen on the emulator), and in the app
  it shows Google's prompt to turn that setting on.

## Update (T2.2, 2026-10-25): Android's GPS provider only

The app always uses Android's own location provider
(`forceLocationManager: true`), never Google's fused location (the user's
choice, option B of three):

- Google's prompt asks users to let Google process Wi-Fi and cell
  information. The app says it collects no data; even though that data
  would go to Google rather than to us, the prompt undermines it.
- It works the same on phones without Google Play services, so the `foss`
  flavour needs no other location code. `geolocator_android` still bundles
  `play-services-location`; T4.5 must exclude it from `foss`, which is
  safe because the fused client is never created.
- Surveying happens outdoors, where both use the same satellites. The
  costs are a slower first fix after the phone was indoors and no position
  dot indoors; walk mode shows "No GPS" until a fix arrives.

A single `LocationHub` owns the app's one GPS stream (geolocator allows
only one per app) and restarts it with the recording notice while walk
mode records, so the map's position dot can't keep recording from running
as a foreground service.
- Fixes for one vertex are averaged as in SPEC.md §7.3. The stored accuracy
  is the median of the fixes used, not reduced by averaging: fixes seconds
  apart share most of their error.
- `integration_test/field_recording_test.dart` checks recording, the
  foreground service and averaging on a device or emulator (see
  CONTRIBUTING.md); it isn't part of CI.
