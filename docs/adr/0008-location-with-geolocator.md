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
