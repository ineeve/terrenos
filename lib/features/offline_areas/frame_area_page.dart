import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/core/format/size_format.dart';
import 'package:terrenos/core/map/offline_area.dart';
import 'package:terrenos/core/map/tile_math.dart';
import 'package:terrenos/features/map/map_page.dart';
import 'package:terrenos/features/offline_areas/offline_areas_controller.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// The user frames an area on the map, chooses the detail, sees the tile
/// count and size, then downloads it (MAP-7).
class FrameAreaPage extends ConsumerStatefulWidget {
  const new({super.key});

  /// Space between the map's edge and the frame, in logical pixels.
  static const inset = 24.0;

  /// The frame opens at least this close in, so it starts under 4 km².
  static const minInitialZoom = 15.0;

  @override
  ConsumerState<FrameAreaPage> createState() => _FrameAreaPageState();
}

class _FrameAreaPageState extends ConsumerState<FrameAreaPage> {
  final _map = MapController();
  OfflineDetail _detail = OfflineDetail.high;
  LatLngBounds? _bounds;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _frame(MapCamera camera) {
    const inset = FrameAreaPage.inset;
    final size = camera.nonRotatedSize;
    final bounds = LatLngBounds(
      camera.screenOffsetToLatLng(const Offset(inset, inset)),
      camera.screenOffsetToLatLng(
        Offset(size.width - inset, size.height - inset),
      ),
    );
    if (bounds != _bounds) setState(() => _bounds = bounds);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final source = ref.watch(imagerySourceProvider);
    final view = ref.read(mapViewProvider);
    final colours = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.offlineFrameTitle)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: view.center,
                    initialZoom: max(view.zoom, FrameAreaPage.minInitialZoom),
                    minZoom: 6,
                    maxZoom: 20,
                    cameraConstraint: CameraConstraint.containCenter(
                      bounds: MapPage.bounds,
                    ),
                    // A rotated frame isn't a latitude/longitude rectangle.
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onMapReady: () => _frame(_map.camera),
                    onPositionChanged: (camera, _) => _frame(camera),
                  ),
                  children: [
                    TileLayer(
                      key: ValueKey(source),
                      wmsOptions: source.wmsOptions,
                      tileProvider: ref.watch(imageryTileProviderProvider),
                      userAgentPackageName: 'pt.terrenos.app',
                    ),
                    const PropertiesLayer(),
                  ],
                ),
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.all(FrameAreaPage.inset),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: colours.primary, width: 3),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: _EstimatePanel(
              bounds: _bounds,
              detail: _detail,
              onDetail: (d) => setState(() => _detail = d),
              onDownload: _download,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _download() async {
    final bounds = _bounds;
    if (bounds == null) return;
    final l10n = AppLocalizations.of(context);
    final count = ref.read(offlineAreasProvider).areas.length;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: l10n.offlineNameDefault(count + 1)),
    );
    if (name == null || !mounted) return;
    await ref
        .read(offlineAreasProvider.notifier)
        .add(
          name: name,
          source: ref.read(imagerySourceProvider),
          bounds: bounds,
          detail: _detail,
        );
    if (mounted) context.pop();
  }
}

class _EstimatePanel extends StatelessWidget {
  const new({
    required this.bounds,
    required this.detail,
    required this.onDetail,
    required this.onDownload,
  });

  final LatLngBounds? bounds;
  final OfflineDetail detail;
  final ValueChanged<OfflineDetail> onDetail;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final bounds = this.bounds;
    final area = bounds == null ? null : rectangleAreaSquareMetres(bounds);
    final tooLarge = area != null && area > OfflineArea.maxAreaSquareMetres;
    final estimate = bounds == null
        ? null
        : OfflineArea.estimate(bounds, detail);
    String km2(double m2) => formatSquareKilometres(m2, languageCode: language);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.offlineFrameHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          SegmentedButton<OfflineDetail>(
            segments: [
              ButtonSegment(
                value: OfflineDetail.normal,
                label: Text(l10n.offlineDetailNormal),
              ),
              ButtonSegment(
                value: OfflineDetail.high,
                label: Text(l10n.offlineDetailHigh),
              ),
            ],
            selected: {detail},
            onSelectionChanged: (s) => onDetail(s.single),
          ),
          const SizedBox(height: 12),
          if (area != null) Text(l10n.editorArea(km2(area))),
          if (tooLarge)
            Text(
              l10n.offlineFrameTooLarge(km2(OfflineArea.maxAreaSquareMetres)),
              style: TextStyle(color: theme.colorScheme.error),
            )
          else if (estimate != null)
            Text(
              l10n.offlineFrameEstimate(
                formatCount(estimate.tiles, languageCode: language),
                formatBytes(estimate.bytes, languageCode: language),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: bounds == null || tooLarge ? null : onDownload,
            icon: const Icon(Icons.download),
            label: Text(l10n.actionDownload),
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? widget.initial : name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.offlineNameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        TextButton(onPressed: _save, child: Text(l10n.actionDownload)),
      ],
    );
  }
}
