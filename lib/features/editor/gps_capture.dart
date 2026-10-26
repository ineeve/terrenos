/// Capturing a GPS position in the field, shared by walk mode (REG-2,
/// VTX-8) and surveying a vertex (VTX-9): permission, the low battery
/// warning, the recording notice (REG-13), averaging (§7.3), the accuracy
/// indicator and the large capture button (§4.1).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/location/gps_averaging.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/features/map/my_location.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Below this battery level (%), capture warns before starting (§7.3).
const lowBattery = 15;

/// Follows the position while the screen is open, recording as a
/// foreground service so it carries on with the screen off, and averages
/// fixes on demand.
mixin GpsCapture<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  StreamSubscription<LocationFix>? _recording;
  Completer<void>? _cancel;

  /// The latest fix, for the accuracy indicator; `null` without one.
  LocationFix? latestFix;

  /// Progress while averaging; `null` otherwise.
  SamplingProgress? sampling;

  RecordingNotice _notice(AppLocalizations l10n) => RecordingNotice(
    title: l10n.walkNotificationTitle,
    text: l10n.walkNotificationText,
    channelName: l10n.walkNotificationChannel,
  );

  /// Asks for location, warns about a low battery, then starts following
  /// the position. `false` if location isn't available or the user chose
  /// not to go on; the caller should then leave.
  Future<bool> startGps() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final access = await ref.read(myLocationProvider.notifier).enable();
    if (!mounted) return false;
    if (access != LocationAccess.granted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            access == LocationAccess.serviceOff
                ? l10n.locationServiceOff
                : l10n.locationDenied,
          ),
        ),
      );
      return false;
    }
    // The notice still records without this; it just isn't shown.
    await ref.read(locationSourceProvider).requestNotifications();
    final battery = await ref.read(batteryLevelProvider)();
    if (!mounted) return false;
    if (battery < lowBattery && !await _confirmLowBattery(battery)) {
      return false;
    }
    if (!mounted) return false;
    _recording = ref
        .read(locationHubProvider)
        .fixes(notice: _notice(l10n))
        .listen((fix) {
          setState(() => latestFix = fix);
          onFix(fix);
        }, onError: (Object _) => setState(() => latestFix = null));
    return true;
  }

  /// Called with each fix while following the position.
  void onFix(LocationFix fix) {}

  Future<bool> _confirmLowBattery(int level) async {
    final l10n = AppLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.walkLowBatteryTitle),
        content: Text(l10n.walkLowBatteryBody(level)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionContinueAnyway),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  /// Averages fixes for a few seconds (§7.3). `null` if cancelled, or if
  /// no fix arrived, which is explained to the user.
  Future<AveragedFix?> captureFix() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cancel = _cancel = Completer<void>();
    setState(() => sampling = const SamplingProgress(fraction: 0, fixes: 0));
    final fix =
        await GpsSampler(
          ref.read(locationHubProvider).fixes(notice: _notice(l10n)),
        ).sample(
          onProgress: (p) {
            if (mounted) setState(() => sampling = p);
          },
          stop: cancel.future,
        );
    if (!mounted) return null;
    final cancelled = cancel.isCompleted;
    setState(() {
      sampling = null;
      _cancel = null;
    });
    if (cancelled) return null;
    if (fix == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.walkNoFix)));
    }
    return fix;
  }

  /// Stops averaging early; [captureFix] then returns `null`.
  void cancelCapture() {
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  @override
  void dispose() {
    unawaited(_recording?.cancel());
    cancelCapture();
    super.dispose();
  }
}

/// The capture button: at least 72 dp, for use with gloves or in the sun
/// (§4.1). While averaging it shows a progress ring and cancels on tap.
class CaptureButton extends StatelessWidget {
  const new({
    required this.label,
    required this.icon,
    required this.sampling,
    required this.onCapture,
    required this.onCancel,
    super.key,
  });

  final String label;
  final IconData icon;
  final SamplingProgress? sampling;
  final VoidCallback onCapture;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = sampling;
    final seconds = GpsSampler.defaultDuration.inSeconds;
    return SizedBox(
      height: 72,
      child: progress == null
          ? FilledButton.icon(
              onPressed: onCapture,
              icon: Icon(icon, size: 32),
              label: Text(label, style: const TextStyle(fontSize: 20)),
            )
          : FilledButton.tonal(
              onPressed: onCancel,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 40,
                    child: CircularProgressIndicator(
                      value: progress.fraction,
                      strokeWidth: 5,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      l10n.walkAveraging(
                        ((1 - progress.fraction) * seconds).ceil(),
                        progress.fixes,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// GPS accuracy: green < 5 m, amber 5–15 m, red > 15 m, always with the
/// number, so colour isn't the only cue (§4.1).
class AccuracyIndicator extends StatelessWidget {
  const new({required this.fix, super.key});

  final LocationFix? fix;

  static const good = 5.0;
  static const fair = 15.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fix = this.fix;
    final (colour, text) = switch (fix?.accuracyMetres) {
      null => (Colors.grey, l10n.walkNoGps),
      final a when a < good => (
        Colors.green.shade700,
        l10n.walkAccuracy(a.round()),
      ),
      final a when a <= fair => (
        Colors.amber.shade800,
        l10n.walkAccuracy(a.round()),
      ),
      final a => (Colors.red.shade700, l10n.walkAccuracy(a.round())),
    };
    return Semantics(
      label: text,
      child: Chip(
        avatar: Icon(Icons.gps_fixed, color: colour),
        label: Text(text),
        side: BorderSide(color: colour, width: 2),
      ),
    );
  }
}
