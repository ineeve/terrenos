/// Walk mode by points (REG-2, VTX-8, SPEC.md §4.1, §7.3): the user stands
/// at each corner and taps "Add point"; the app averages GPS for a few
/// seconds. Recording continues with the screen off (REG-13).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/location/gps_averaging.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/features/map/my_location.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Where a captured point goes (VTX-8).
enum InsertAt { end, afterSelected, nearestEdge }

class WalkPanel extends ConsumerStatefulWidget {
  const new({
    required this.selectedLabel,
    required this.onCapture,
    required this.onStop,
    super.key,
  });

  /// The selected vertex's label, e.g. `V3`; `null` when none is.
  final String? selectedLabel;
  final void Function(AveragedFix fix, InsertAt at) onCapture;

  /// Leaves walk mode, e.g. when location isn't allowed.
  final VoidCallback onStop;

  /// Below this, walk mode warns before starting (§7.3).
  static const lowBattery = 15;

  @override
  ConsumerState<WalkPanel> createState() => _WalkPanelState();
}

class _WalkPanelState extends ConsumerState<WalkPanel> {
  StreamSubscription<LocationFix>? _recording;
  LocationFix? _latest;
  SamplingProgress? _progress;
  Completer<void>? _cancel;
  late InsertAt _insertAt = widget.selectedLabel == null
      ? InsertAt.end
      : InsertAt.afterSelected;

  RecordingNotice _notice(AppLocalizations l10n) => RecordingNotice(
    title: l10n.walkNotificationTitle,
    text: l10n.walkNotificationText,
    channelName: l10n.walkNotificationChannel,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void didUpdateWidget(WalkPanel old) {
    super.didUpdateWidget(old);
    if (widget.selectedLabel == null && _insertAt == InsertAt.afterSelected) {
      _insertAt = InsertAt.end;
    }
  }

  @override
  void dispose() {
    unawaited(_recording?.cancel());
    _cancel?.complete();
    super.dispose();
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final access = await ref.read(myLocationProvider.notifier).enable();
    if (!mounted) return;
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
      widget.onStop();
      return;
    }
    // The notice still records without this; it just isn't shown.
    await ref.read(locationSourceProvider).requestNotifications();
    final battery = await ref.read(batteryLevelProvider)();
    if (!mounted) return;
    if (battery < WalkPanel.lowBattery && !await _confirmLowBattery(battery)) {
      widget.onStop();
      return;
    }
    if (!mounted) return;
    _recording = ref
        .read(locationHubProvider)
        .fixes(notice: _notice(l10n))
        .listen(
          (fix) => setState(() => _latest = fix),
          onError: (Object _) => setState(() => _latest = null),
        );
  }

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

  Future<void> _addPoint() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cancel = _cancel = Completer<void>();
    setState(() => _progress = const SamplingProgress(fraction: 0, fixes: 0));
    final fix =
        await GpsSampler(
          ref.read(locationHubProvider).fixes(notice: _notice(l10n)),
        ).sample(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          stop: cancel.future,
        );
    if (!mounted) return;
    final cancelled = cancel.isCompleted;
    setState(() {
      _progress = null;
      _cancel = null;
    });
    if (cancelled) return;
    if (fix == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.walkNoFix)));
      return;
    }
    widget.onCapture(fix, _insertAt);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = _progress;
    final selected = widget.selectedLabel;
    final seconds = GpsSampler.defaultDuration.inSeconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AccuracyIndicator(fix: _latest),
              const Spacer(),
              TextButton.icon(
                onPressed: progress == null ? widget.onStop : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(l10n.walkStop),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<InsertAt>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: InsertAt.end, label: Text(l10n.walkAtEnd)),
              ButtonSegment(
                value: InsertAt.afterSelected,
                enabled: selected != null,
                label: Text(l10n.walkAfter(selected ?? '—')),
              ),
              ButtonSegment(
                value: InsertAt.nearestEdge,
                label: Text(l10n.walkNearestEdge),
              ),
            ],
            selected: {_insertAt},
            onSelectionChanged: progress == null
                ? (s) => setState(() => _insertAt = s.single)
                : null,
          ),
          const SizedBox(height: 8),
          // At least 72 dp, for use with gloves or in the sun (§4.1).
          SizedBox(
            height: 72,
            child: progress == null
                ? FilledButton.icon(
                    onPressed: _addPoint,
                    icon: const Icon(Icons.add_location_alt, size: 32),
                    label: Text(
                      l10n.walkAddPoint,
                      style: const TextStyle(fontSize: 20),
                    ),
                  )
                : FilledButton.tonal(
                    onPressed: () => _cancel?.complete(),
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
          ),
        ],
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
