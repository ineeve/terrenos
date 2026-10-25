/// The user's position on the map and the "centre on me" button (MAP-4).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

@immutable
class MyLocationState {
  const new({this.access, this.fix});

  /// `null` until checked.
  final LocationAccess? access;
  final LocationFix? fix;
}

final myLocationProvider =
    NotifierProvider<MyLocationController, MyLocationState>(
      MyLocationController.new,
    );

/// Follows the position while permission is granted. Permission is only
/// asked for when the user taps "centre on me", never on start.
class MyLocationController extends Notifier<MyLocationState> {
  StreamSubscription<LocationFix>? _fixes;

  LocationSource get _source => ref.read(locationSourceProvider);

  @override
  MyLocationState build() {
    // GPS only runs while the app is on screen. Coming back also picks up a
    // permission granted in the system settings meanwhile.
    final lifecycle = AppLifecycleListener(
      onHide: _stop,
      onShow: () => unawaited(_startIfAllowed()),
    );
    ref.onDispose(() {
      lifecycle.dispose();
      unawaited(_fixes?.cancel());
    });
    unawaited(_startIfAllowed());
    return const MyLocationState();
  }

  void _stop() {
    unawaited(_fixes?.cancel());
    _fixes = null;
    // A position from before the pause would be out of date.
    state = MyLocationState(access: state.access);
  }

  Future<void> _startIfAllowed() async {
    final access = await _source.access();
    if (!ref.mounted) return;
    _update(access);
  }

  /// Asks for permission if needed and starts following the position.
  Future<LocationAccess> enable() async {
    final access = await _source.requestAccess();
    if (ref.mounted) _update(access);
    return access;
  }

  Future<void> openSettings(LocationAccess access) =>
      _source.openSettings(access);

  void _update(LocationAccess access) {
    state = MyLocationState(
      access: access,
      fix: access == LocationAccess.granted ? state.fix : null,
    );
    if (access != LocationAccess.granted) {
      unawaited(_fixes?.cancel());
      _fixes = null;
      return;
    }
    _fixes ??= _source.fixes().listen(
      (fix) => state = MyLocationState(access: state.access, fix: fix),
      // Location was turned off or revoked while listening.
      onError: (Object _) async {
        _fixes = null;
        await _startIfAllowed();
      },
      cancelOnError: true,
    );
  }
}

/// A dot at the position with a circle showing its accuracy.
class MyLocationLayer extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fix = ref.watch(myLocationProvider.select((s) => s.fix));
    if (fix == null) return const SizedBox.shrink();
    final point = LatLng(fix.lat, fix.lon);
    const blue = Color(0xFF1A73E8);
    return Stack(
      children: [
        CircleLayer(
          circles: [
            CircleMarker(
              point: point,
              radius: fix.accuracyMetres,
              useRadiusInMeter: true,
              color: blue.withValues(alpha: 0.15),
              borderColor: blue.withValues(alpha: 0.5),
              borderStrokeWidth: 1,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: point,
              width: 20,
              height: 20,
              child: Semantics(
                label: AppLocalizations.of(context).mapMyLocation,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(blurRadius: 4, color: Colors.black38),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Moves the map to the user's position, asking for permission first if
/// needed (MAP-4).
class CentreOnMeButton extends ConsumerStatefulWidget {
  const new({super.key});

  /// Zoom used when centring from further out: a few parcels across.
  static const zoom = 17.0;

  @override
  ConsumerState<CentreOnMeButton> createState() => _CentreOnMeButtonState();
}

class _CentreOnMeButtonState extends ConsumerState<CentreOnMeButton> {
  /// Centre as soon as the first fix arrives.
  bool _waiting = false;

  void _centre(LocationFix fix) {
    final map = MapController.of(context);
    map.move(
      LatLng(fix.lat, fix.lon),
      map.camera.zoom < CentreOnMeButton.zoom
          ? CentreOnMeButton.zoom
          : map.camera.zoom,
    );
  }

  Future<void> _pressed() async {
    final location = ref.read(myLocationProvider);
    if (location.fix case final fix?) return _centre(fix);

    final controller = ref.read(myLocationProvider.notifier);
    final access = await controller.enable();
    if (!mounted) return;
    if (access == LocationAccess.granted) {
      setState(() => _waiting = true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            access == LocationAccess.serviceOff
                ? l10n.locationServiceOff
                : l10n.locationDenied,
          ),
          action: access == LocationAccess.denied
              ? null
              : SnackBarAction(
                  label: l10n.actionSettings,
                  onPressed: () => unawaited(controller.openSettings(access)),
                ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen(myLocationProvider.select((s) => s.fix), (_, fix) {
      if (_waiting && fix != null) {
        setState(() => _waiting = false);
        _centre(fix);
      }
    });
    final location = ref.watch(myLocationProvider);
    final icon = location.fix != null
        ? Icons.my_location
        : location.access == LocationAccess.granted
        ? Icons.location_searching
        : Icons.location_disabled;
    return FloatingActionButton.small(
      heroTag: null,
      tooltip: l10n.mapCentreOnMe,
      onPressed: _pressed,
      child: Icon(icon),
    );
  }
}
