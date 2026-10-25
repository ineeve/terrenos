# Terrenos

Offline-first Android app (Flutter) for registering land properties in mainland Portugal on a
map. Users can draw a boundary, walk it with GPS, or type each vertex's coordinates
(WGS84 / PT-TM06). Properties can be shared directly between phones, with no server.

App de Android (Flutter), sem servidor, para registar terrenos em Portugal continental no mapa,
com sincronização direta entre telemóveis.

## Documents

- [SPEC.md](SPEC.md): product and technical specification
- [PLAN.md](PLAN.md): implementation plan

## Status

Milestone M0 (foundations) is in progress; see [PLAN.md](PLAN.md). The data
model, file storage, first-run setup (PT/EN) and settings exist. Map and
property features are not built yet.

## Development

Requires Flutter 3.47.8 (stable) and the Android SDK.

```sh
flutter pub get
flutter run --flavor dev      # installs as "Terrenos Dev"
flutter test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the checks CI runs, and
[docs/adr/](docs/adr/) for decisions that refine the spec.

## Licence

[MIT](LICENSE)
