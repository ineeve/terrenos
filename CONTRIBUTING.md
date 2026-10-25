# Contributing to Terrenos

Thank you for helping. Terrenos is an offline-first Android app for
registering land properties in mainland Portugal. Read [SPEC.md](SPEC.md) for
what the app does and [PLAN.md](PLAN.md) for the order in which it is built.

## Setup

1. Install Flutter **3.47.8** (stable) and the Android SDK.
2. `flutter pub get` (this also generates the translations in `lib/l10n/gen/`).
3. Run the app: `flutter run --flavor dev`.

The `dev` flavour installs as "Terrenos Dev" next to the `prod` app, so two
copies can sync with each other on one phone. Plain `flutter run` without
`--flavor` does not work.

## Before opening a pull request

Run the same checks as CI:

```sh
dart format $(git ls-files '*.dart')
flutter analyze
dart run tool/check_arb.dart
dart run tool/check_licenses.dart
flutter test --coverage && dart run tool/check_coverage.dart
```

Each pull request should:

- Do one task from PLAN.md, or fix one issue.
- Include tests: unit tests for logic, widget tests for new screens.
- Add every new string to **both** `lib/l10n/app_en.arb` and
  `lib/l10n/app_pt.arb`. Portuguese means European Portuguese ("telemóvel",
  "ecrã"), never Brazilian Portuguese.
- Give every control a TalkBack label.
- Not make network requests anywhere except the map tile downloader.
- Record decisions that change the spec in `docs/adr/`.

## Dependencies

The app is MIT-licensed. Dependencies under GPL, LGPL or AGPL can't be used;
`tool/check_licenses.dart` enforces this.

## Secrets

Never commit signing keys, keystores, `key.properties` or service-account
files. Release signing is configured only through CI secrets.
