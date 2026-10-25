# 0002 — One entry point; flavours defined in Gradle

- **Status:** accepted (M0)
- **Changes:** SPEC.md Appendix B (`main_dev.dart | main_prod.dart`)

## Decision

There is one `lib/main.dart`. The `dev`, `prod` and `foss` flavours are Gradle
product flavours (`android/app/build.gradle.kts`). Dart code that needs the
flavour reads Flutter's `appFlavor` constant.

## Why

The flavours differ in Android-level things (application id, app name, and
later the Google Play Services dependency for Nearby), not in Dart start-up
code. Separate entry points would duplicate `main` for no benefit.

## Consequences

- Every build and run command needs `--flavor`, e.g. `flutter run --flavor dev`.
- `dev` installs as `pt.terrenos.app.dev` ("Terrenos Dev") beside `prod`.
- Release builds are signed with keys from `android/key.properties`
  (gitignored) or `TERRENOS_*` environment variables in CI; without them they
  fall back to the debug key and can't be uploaded to Google Play.
