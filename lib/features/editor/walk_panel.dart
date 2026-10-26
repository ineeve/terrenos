/// Walk mode (SPEC.md §4.1, §7.3). By points (REG-2, VTX-8): the user
/// stands at each corner and taps "Add point"; the app averages GPS for a
/// few seconds. Continuous (REG-3): the app records a track while the user
/// walks along the boundary, then simplifies it into vertices. Recording
/// continues with the screen off (REG-13).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/location/gps_averaging.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/location/track_recorder.dart';
import 'package:terrenos/features/editor/gps_capture.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Where a captured point goes (VTX-8).
enum InsertAt { end, afterSelected, nearestEdge }

enum WalkMode {
  /// A vertex at each corner (REG-2).
  points,

  /// A recorded track (REG-3).
  track,
}

class WalkPanel extends ConsumerStatefulWidget {
  const new({
    required this.selectedLabel,
    required this.onCapture,
    required this.onTrack,
    required this.onStop,
    this.onTrackChanged,
    super.key,
  });

  /// The selected vertex's label, e.g. `V3`; `null` when none is.
  final String? selectedLabel;
  final void Function(AveragedFix fix, InsertAt at) onCapture;

  /// A finished track, simplified: the vertices to add (REG-3).
  final ValueChanged<List<LocationFix>> onTrack;

  /// The track so far while recording, to draw it; `null` when not
  /// recording.
  final ValueChanged<List<LocationFix>?>? onTrackChanged;

  /// Leaves walk mode, e.g. when location isn't allowed.
  final VoidCallback onStop;

  /// Douglas–Peucker tolerances offered after recording (REG-3).
  static const tolerances = [0.5, 1.0, 2.0, 5.0];
  static const defaultTolerance = 1.0;

  @override
  ConsumerState<WalkPanel> createState() => _WalkPanelState();
}

class _WalkPanelState extends ConsumerState<WalkPanel> with GpsCapture {
  late InsertAt _insertAt = widget.selectedLabel == null
      ? InsertAt.end
      : InsertAt.afterSelected;
  WalkMode _mode = WalkMode.points;

  /// While recording a track; `null` otherwise.
  TrackRecorder? _track;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!await startGps() && mounted) widget.onStop();
    });
  }

  @override
  void didUpdateWidget(WalkPanel old) {
    super.didUpdateWidget(old);
    if (widget.selectedLabel == null && _insertAt == InsertAt.afterSelected) {
      _insertAt = InsertAt.end;
    }
  }

  @override
  void onFix(LocationFix fix) {
    final track = _track;
    if (track != null && track.add(fix)) {
      widget.onTrackChanged?.call(track.points);
    }
  }

  Future<void> _addPoint() async {
    final fix = await captureFix();
    if (fix != null) widget.onCapture(fix, _insertAt);
  }

  void _startTrack() {
    setState(() => _track = TrackRecorder());
    widget.onTrackChanged?.call(const []);
  }

  Future<void> _finishTrack() async {
    final l10n = AppLocalizations.of(context);
    final points = _track!.points;
    setState(() => _track = null);
    if (points.length < 3) {
      widget.onTrackChanged?.call(null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.trackTooShort)));
      return;
    }
    final simplified = await showDialog<List<LocationFix>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TrackReview(points: points),
    );
    if (!mounted) return;
    widget.onTrackChanged?.call(null);
    if (simplified != null) widget.onTrack(simplified);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = sampling != null || _track != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AccuracyIndicator(fix: latestFix),
              const Spacer(),
              TextButton.icon(
                onPressed: busy ? null : widget.onStop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(l10n.walkStop),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<WalkMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: WalkMode.points,
                icon: const Icon(Icons.place_outlined),
                label: Text(l10n.walkModePoints),
              ),
              ButtonSegment(
                value: WalkMode.track,
                icon: const Icon(Icons.timeline),
                label: Text(l10n.walkModeTrack),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: busy
                ? null
                : (s) => setState(() => _mode = s.single),
          ),
          const SizedBox(height: 8),
          ...switch (_mode) {
            WalkMode.points => _pointsControls(l10n, busy),
            WalkMode.track => _trackControls(l10n),
          },
        ],
      ),
    );
  }

  List<Widget> _pointsControls(AppLocalizations l10n, bool busy) {
    final selected = widget.selectedLabel;
    return [
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
        onSelectionChanged: busy
            ? null
            : (s) => setState(() => _insertAt = s.single),
      ),
      const SizedBox(height: 8),
      CaptureButton(
        label: l10n.walkAddPoint,
        icon: Icons.add_location_alt,
        sampling: sampling,
        onCapture: () => unawaited(_addPoint()),
        onCancel: cancelCapture,
      ),
    ];
  }

  List<Widget> _trackControls(AppLocalizations l10n) {
    final track = _track;
    final language = Localizations.localeOf(context).languageCode;
    return [
      if (track == null)
        Text(l10n.trackHint)
      else
        Semantics(
          liveRegion: true,
          child: Text(
            [
              l10n.trackProgress(
                track.points.length,
                formatDistance(track.lengthMetres, languageCode: language),
              ),
              if (track.skipped > 0) l10n.trackSkipped(track.skipped),
            ].join(' · '),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      const SizedBox(height: 8),
      // At least 72 dp, for use with gloves or in the sun (§4.1).
      SizedBox(
        height: 72,
        child: track == null
            ? FilledButton.icon(
                onPressed: _startTrack,
                icon: const Icon(Icons.fiber_manual_record, size: 32),
                label: Text(
                  l10n.trackStart,
                  style: const TextStyle(fontSize: 20),
                ),
              )
            : FilledButton.tonalIcon(
                onPressed: () => unawaited(_finishTrack()),
                icon: const Icon(Icons.stop, size: 32),
                label: Text(
                  l10n.trackFinish,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
      ),
    ];
  }
}

/// After recording: how many vertices the track becomes at each tolerance
/// (REG-3). Completes with the simplified track, or `null` to discard it.
class _TrackReview extends StatefulWidget {
  const new({required this.points});

  final List<LocationFix> points;

  @override
  State<_TrackReview> createState() => _TrackReviewState();
}

class _TrackReviewState extends State<_TrackReview> {
  double _tolerance = WalkPanel.defaultTolerance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final simplified = simplifyTrack(widget.points, _tolerance);
    return AlertDialog(
      title: Text(l10n.trackReviewTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.trackReviewBody(widget.points.length, simplified.length)),
          const SizedBox(height: 16),
          Text(
            l10n.trackTolerance,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            showSelectedIcon: false,
            segments: [
              for (final t in WalkPanel.tolerances)
                ButtonSegment(
                  value: t,
                  label: Text(formatLength(t, languageCode: language)),
                ),
            ],
            selected: {_tolerance},
            onSelectionChanged: (s) => setState(() => _tolerance = s.single),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.trackToleranceHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionDiscard),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(simplified),
          child: Text(l10n.trackAdd),
        ),
      ],
    );
  }
}
