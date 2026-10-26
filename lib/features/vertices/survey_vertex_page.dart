/// Surveying an existing vertex on site (VTX-9, SPEC.md §4.1, §7.3): the
/// user stands on the marker and measures; the app says how far and in
/// which direction the measurement is from the stored position, and the
/// user keeps the stored coordinates, replaces them, or measures again.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/editing/boundary_editor.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/location/gps_averaging.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/features/editor/gps_capture.dart';
import 'package:terrenos/features/map/map_overlays.dart';
import 'package:terrenos/features/map/map_page.dart';
import 'package:terrenos/features/map/my_location.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// What the user decided after measuring.
enum SurveyChoice {
  /// Keep the stored coordinates and mark the vertex as surveyed.
  keep,

  /// Move the vertex to the measured position.
  replace,
}

typedef SurveyOutcome = ({SurveyChoice choice, AveragedFix fix});

class SurveyVertexPage extends ConsumerStatefulWidget {
  const new({
    required this.vertex,
    required this.label,
    this.parts = const [],
    super.key,
  });

  /// Opens the survey of [vertex]; `null` if the user leaves without
  /// choosing. [parts] is the boundary, drawn for context.
  static Future<SurveyOutcome?> open(
    BuildContext context, {
    required Vertex vertex,
    required String label,
    BoundaryParts parts = const [],
  }) => Navigator.of(context).push<SurveyOutcome>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          SurveyVertexPage(vertex: vertex, label: label, parts: parts),
    ),
  );

  final Vertex vertex;

  /// E.g. `V3`.
  final String label;
  final BoundaryParts parts;

  /// Close enough to the marker to see it on the orthophoto.
  static const zoom = 19.0;

  @override
  ConsumerState<SurveyVertexPage> createState() => _SurveyVertexPageState();
}

class _SurveyVertexPageState extends ConsumerState<SurveyVertexPage>
    with GpsCapture {
  final _map = MapController();
  AveragedFix? _fix;

  LatLng get _stored => LatLng(widget.vertex.lat, widget.vertex.lon);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!await startGps() && mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    final fix = await captureFix();
    if (fix == null || !mounted) return;
    setState(() => _fix = fix);
    // Both positions in view.
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [_stored, LatLng(fix.lat, fix.lon)],
        padding: const EdgeInsets.all(64),
        maxZoom: SurveyVertexPage.zoom,
      ),
    );
  }

  void _repeat() {
    setState(() => _fix = null);
    _map.move(_stored, SurveyVertexPage.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fix = _fix;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.surveyTitle(widget.label))),
      body: Column(
        children: [
          Expanded(child: _mapView(l10n)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AccuracyIndicator(fix: latestFix),
                  ),
                  const SizedBox(height: 8),
                  if (fix == null) ...[
                    Text(l10n.surveyHint),
                    const SizedBox(height: 12),
                    CaptureButton(
                      label: l10n.surveyMeasure,
                      icon: Icons.gps_fixed,
                      sampling: sampling,
                      onCapture: () => unawaited(_measure()),
                      onCancel: cancelCapture,
                    ),
                  ] else
                    _Result(
                      fix: fix,
                      comparison: compareSurvey(widget.vertex, (
                        lon: fix.lon,
                        lat: fix.lat,
                      ), fix.toGpsFix(ref.read(deviceProvider).deviceId)),
                      onChoose: (choice) =>
                          Navigator.of(context)
                              .pop<SurveyOutcome>((choice: choice, fix: fix)),
                      onRepeat: _repeat,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapView(AppLocalizations l10n) {
    final source = ref.watch(imagerySourceProvider);
    final fix = _fix;
    final measured = fix == null ? null : LatLng(fix.lat, fix.lon);
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _stored,
        initialZoom: SurveyVertexPage.zoom,
        minZoom: 6,
        maxZoom: 20,
      ),
      children: [
        TileLayer(
          wmsOptions: source.wmsOptions,
          tileProvider: ref.watch(imageryTileProviderProvider),
          userAgentPackageName: 'pt.terrenos.app',
        ),
        PolylineLayer(
          polylines: [
            for (final part in widget.parts)
              for (final ring in part)
                if (ring.length >= 2)
                  Polyline(
                    points: [
                      for (final v in ring) LatLng(v.lat, v.lon),
                      if (ring.length >= 3)
                        LatLng(ring.first.lat, ring.first.lon),
                    ],
                    color: Colors.yellowAccent,
                    strokeWidth: 2.5,
                  ),
            if (measured != null)
              Polyline(
                points: [_stored, measured],
                color: Colors.white,
                strokeWidth: 2,
                pattern: StrokePattern.dashed(segments: const [8, 6]),
              ),
          ],
        ),
        const MyLocationLayer(),
        MarkerLayer(
          markers: [
            Marker(
              point: _stored,
              width: 28,
              height: 28,
              child: Semantics(
                label: l10n.surveyStored(widget.label),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.vertex.isSurveyed
                        ? Colors.orangeAccent
                        : Colors.black54,
                    border: Border.all(color: Colors.orangeAccent, width: 4),
                  ),
                ),
              ),
            ),
            if (measured != null)
              Marker(
                point: measured,
                width: 36,
                height: 36,
                child: Semantics(
                  label: l10n.surveyMeasured,
                  child: const Icon(
                    Icons.add_circle,
                    size: 36,
                    color: Colors.lightBlueAccent,
                    shadows: [Shadow(blurRadius: 4)],
                  ),
                ),
              ),
          ],
        ),
        const Scalebar(alignment: Alignment.bottomLeft),
        MapAttribution(sources: ['$dgtAttribution ${source.year}']),
      ],
    );
  }
}

/// "Measured 3.2 m to the north-east of the stored position · accuracy
/// ±4 m", with Replace, Keep and Repeat (§4.1). The suggested choice is
/// the filled button (§7.3).
class _Result extends StatelessWidget {
  const new({
    required this.fix,
    required this.comparison,
    required this.onChoose,
    required this.onRepeat,
  });

  final AveragedFix fix;
  final SurveyComparison comparison;
  final ValueChanged<SurveyChoice> onChoose;
  final VoidCallback onRepeat;

  /// Closer than this, a direction means nothing.
  static const samePlaceMetres = 0.05;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final accuracy = fix.accuracyMetres.round();
    final summary = comparison.distanceMetres < samePlaceMetres
        ? l10n.surveySamePlace(accuracy)
        : l10n.surveyResult(
            formatLength(comparison.distanceMetres, languageCode: language),
            compassName(l10n, comparison.direction),
            accuracy,
          );
    final warning = fix.mocked
        ? l10n.surveyMocked
        : fix.accuracyMetres > GeometryValidator.defaultAccuracyThresholdMetres
        ? l10n.surveyImprecise(accuracy)
        : null;
    final keep = comparison.suggestKeep;

    Widget choice(SurveyChoice value, String label) {
      void onPressed() => onChoose(value);
      final suggested = (value == SurveyChoice.keep) == keep;
      return Expanded(
        child: SizedBox(
          height: 56,
          child: suggested
              ? FilledButton(onPressed: onPressed, child: Text(label))
              : OutlinedButton(onPressed: onPressed, child: Text(label)),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(summary, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 4),
        Text(keep ? l10n.surveySuggestKeep : l10n.surveySuggestReplace),
        if (warning != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.warning_amber, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  warning,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            choice(SurveyChoice.replace, l10n.surveyReplace),
            const SizedBox(width: 8),
            choice(SurveyChoice.keep, l10n.surveyKeep),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 56,
                child: TextButton.icon(
                  onPressed: onRepeat,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.surveyRepeat),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "north-east", "nordeste"… for a direction (VTX-9).
String compassName(AppLocalizations l10n, CompassDirection direction) =>
    switch (direction) {
      CompassDirection.north => l10n.compassNorth,
      CompassDirection.northEast => l10n.compassNorthEast,
      CompassDirection.east => l10n.compassEast,
      CompassDirection.southEast => l10n.compassSouthEast,
      CompassDirection.south => l10n.compassSouth,
      CompassDirection.southWest => l10n.compassSouthWest,
      CompassDirection.west => l10n.compassWest,
      CompassDirection.northWest => l10n.compassNorthWest,
    };
