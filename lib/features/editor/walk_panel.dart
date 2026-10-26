/// Walk mode by points (REG-2, VTX-8, SPEC.md §4.1, §7.3): the user stands
/// at each corner and taps "Add point"; the app averages GPS for a few
/// seconds. Recording continues with the screen off (REG-13).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/core/location/gps_averaging.dart';
import 'package:terrenos/features/editor/gps_capture.dart';
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

  @override
  ConsumerState<WalkPanel> createState() => _WalkPanelState();
}

class _WalkPanelState extends ConsumerState<WalkPanel> with GpsCapture {
  late InsertAt _insertAt = widget.selectedLabel == null
      ? InsertAt.end
      : InsertAt.afterSelected;

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

  Future<void> _addPoint() async {
    final fix = await captureFix();
    if (fix != null) widget.onCapture(fix, _insertAt);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = sampling != null;
    final selected = widget.selectedLabel;
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
        ],
      ),
    );
  }
}
