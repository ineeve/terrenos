/// Go to vertex (VTX-10, PLAN.md T2.4): the distance to a vertex and an
/// arrow pointing at it, from GPS and the compass, so users can find on
/// site the markers they planned at home. The phone buzzes on arrival, and
/// the vertex can then be surveyed (VTX-9).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/location/compass.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/features/editor/gps_capture.dart';
import 'package:terrenos/features/map/map_overlays.dart';
import 'package:terrenos/features/map/map_page.dart';
import 'package:terrenos/features/map/my_location.dart';
import 'package:terrenos/features/vertices/survey_vertex_page.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

class GoToVertexPage extends ConsumerStatefulWidget {
  const new({
    required this.vertex,
    required this.label,
    this.parts = const [],
    super.key,
  });

  /// Guides the user to [vertex]. Completes with the survey outcome if the
  /// user surveyed it from here, otherwise `null`.
  static Future<SurveyOutcome?> open(
    BuildContext context, {
    required Vertex vertex,
    required String label,
    BoundaryParts parts = const [],
  }) => Navigator.of(context).push<SurveyOutcome>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          GoToVertexPage(vertex: vertex, label: label, parts: parts),
    ),
  );

  final Vertex vertex;

  /// E.g. `V3`.
  final String label;
  final BoundaryParts parts;

  @override
  ConsumerState<GoToVertexPage> createState() => _GoToVertexPageState();
}

class _GoToVertexPageState extends ConsumerState<GoToVertexPage>
    with GpsCapture {
  final _map = MapController();
  final _arrival = ArrivalDetector();
  StreamSubscription<CompassReading?>? _compassReadings;
  CompassReading? _compass;
  bool _framed = false;

  LatLng get _target => LatLng(widget.vertex.lat, widget.vertex.lon);

  @override
  void initState() {
    super.initState();
    _compassReadings = ref
        .read(compassSourceProvider)
        .readings()
        .listen((reading) => setState(() => _compass = reading));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!await startGps() && mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    unawaited(_compassReadings?.cancel());
    _map.dispose();
    super.dispose();
  }

  @override
  void onFix(LocationFix fix) {
    final distance = inverse(
      (lon: fix.lon, lat: fix.lat),
      (lon: widget.vertex.lon, lat: widget.vertex.lat),
    ).distanceMetres;
    if (_arrival.update(
      distanceMetres: distance,
      accuracyMetres: fix.accuracyMetres,
    )) {
      unawaited(ref.read(arrivalSignalProvider)());
    }
    // The user and the vertex both in view, once; after that the user
    // moves the map as they like.
    if (!_framed) {
      _framed = true;
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: [_target, LatLng(fix.lat, fix.lon)],
          padding: const EdgeInsets.all(64),
          maxZoom: 19,
        ),
      );
    }
  }

  Future<void> _survey() async {
    final outcome = await SurveyVertexPage.open(
      context,
      vertex: widget.vertex,
      label: widget.label,
      parts: widget.parts,
    );
    if (outcome != null && mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.goToTitle(widget.label))),
      body: Column(
        children: [
          Expanded(child: _mapView(l10n)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _guidance(l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guidance(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final fix = latestFix;
    final compass = _compass;
    final arrived = _arrival.arrived;

    final Widget status;
    if (fix == null) {
      status = Text(l10n.goToWaiting, style: theme.textTheme.titleMedium);
    } else {
      final g = inverse(
        (lon: fix.lon, lat: fix.lat),
        (lon: widget.vertex.lon, lat: widget.vertex.lat),
      );
      final distance = formatDistance(g.distanceMetres, languageCode: language);
      final direction = compassName(
        l10n,
        CompassDirection.fromBearing(g.bearingDegrees),
      );
      status = Row(
        children: [
          // With a compass the arrow turns with the phone; without one it
          // points relative to north, at the top of the screen.
          DirectionArrow(
            degrees: g.bearingDegrees - (compass?.headingDegrees ?? 0),
            arrived: arrived,
            semanticLabel: arrived
                ? l10n.goToArrived(widget.label)
                : l10n.goToArrow(widget.label, distance, direction),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Semantics(
              liveRegion: arrived,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (arrived)
                    Text(
                      l10n.goToArrived(widget.label),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.green.shade700,
                      ),
                    ),
                  Text(distance, style: theme.textTheme.displaySmall),
                  Text(l10n.goToDirection(direction)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final note = compass == null
        ? l10n.goToNoCompass
        : compass.needsCalibration
        ? l10n.goToCalibrate
        : null;
    final surveyLabel = Text(
      l10n.surveyTitle(widget.label),
      style: const TextStyle(fontSize: 20),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: AccuracyIndicator(fix: fix),
        ),
        const SizedBox(height: 8),
        status,
        if (note != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.explore_off_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(note, style: theme.textTheme.bodySmall)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // The survey can start anywhere; on arrival it is the main action.
        SizedBox(
          height: 72,
          child: arrived
              ? FilledButton.icon(
                  onPressed: _survey,
                  icon: const Icon(Icons.gps_fixed, size: 32),
                  label: surveyLabel,
                )
              : OutlinedButton.icon(
                  onPressed: _survey,
                  icon: const Icon(Icons.gps_fixed, size: 32),
                  label: surveyLabel,
                ),
        ),
      ],
    );
  }

  Widget _mapView(AppLocalizations l10n) {
    final source = ref.watch(imagerySourceProvider);
    final fix = latestFix;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _target,
        initialZoom: 18,
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
            if (fix != null)
              Polyline(
                points: [LatLng(fix.lat, fix.lon), _target],
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
              point: _target,
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
          ],
        ),
        const Scalebar(alignment: Alignment.bottomLeft),
        MapAttribution(sources: ['$dgtAttribution ${source.year}']),
      ],
    );
  }
}

/// A large arrow turned [degrees] clockwise from the top of the screen;
/// a check mark once the user has arrived.
class DirectionArrow extends StatelessWidget {
  const new({
    required this.degrees,
    required this.semanticLabel,
    this.arrived = false,
    super.key,
  });

  final double degrees;
  final bool arrived;
  final String semanticLabel;

  static const size = 120.0;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: ExcludeSemantics(
      child: arrived
          ? Icon(Icons.where_to_vote, size: size, color: Colors.green.shade700)
          : Transform.rotate(
              angle: degrees * pi / 180,
              child: Icon(
                Icons.navigation,
                size: size,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
    ),
  );
}
