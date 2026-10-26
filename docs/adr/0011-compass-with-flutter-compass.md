# 0011 — Compass with flutter_compass; arrival within the GPS accuracy

- **Status:** accepted (M2, T2.4, 2026-10-26)
- **Refines:** SPEC.md VTX-10, §5 (libraries)

## Context

Go to vertex (VTX-10) needs the direction the phone is facing, to turn an
arrow towards the marker, and a vibration when the user gets there.

## Decision

- **Compass:** `flutter_compass` 0.8.1 (MIT), as SPEC.md §5 planned. On
  Android it reads the rotation vector sensor, which fuses the gyroscope and
  is steadier than computing a heading from the magnetometer and
  accelerometer ourselves (e.g. with `sensors_plus`). It has no Google Play
  Services dependency, so it also suits the `foss` flavour. The plugin was
  last released in November 2024; if it stops building, the fallback is a
  small platform channel over the same sensor.
- The app reads it through `CompassSource`, so tests turn a fake phone.
- **Magnetic north:** the plugin's heading is magnetic. The declination in
  mainland Portugal is about 1–2° west, far below a phone compass's own
  error (often ±15° or worse), so it isn't corrected.
- **No compass:** without readings, the arrow points relative to north at
  the top of the screen, and the screen says so. When Android reports the
  sensor as unreliable or worse than ±30°, the user is asked to calibrate
  (figure of eight).
- **Arrival:** within the fix's accuracy, but never closer than 2 m. It
  buzzes once (three pulses through `HapticFeedback`, no extra permission
  or package) and re-arms only after the user is clearly away again (the
  reach plus at least 3 m), so GPS jitter at the marker doesn't buzz
  repeatedly.

## Consequences

- One new native dependency, checked by `tool/check_licenses.dart`.
- `HapticFeedback` follows the system's touch-vibration setting; a user who
  turned that off still gets the on-screen "You are at V3".
- The arrow's accuracy is the compass's; the distance and the 8-point
  direction in words don't depend on it.
