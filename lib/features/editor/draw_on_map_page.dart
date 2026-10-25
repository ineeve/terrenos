import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/caop/caop.dart';
import 'package:terrenos/core/editing/boundary_editor.dart';
import 'package:terrenos/core/editing/snapping.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/features/map/imagery_layer.dart';
import 'package:terrenos/features/map/map_page.dart';
import 'package:terrenos/features/vertices/vertex_format.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Draws a boundary on the orthophoto (REG-1, ADR 0007).
///
/// A crosshair stays at the centre of the map: pan the map to put it on a
/// marker or corner visible in the imagery, then "Add here" or "Move here".
/// Tapping the map also adds a vertex at the tapped point. The crosshair
/// avoids the finger hiding the target, which a loupe would otherwise
/// solve (REG-10). Positions snap to other properties' vertices within
/// 10 px (REG-7). Edits go through [onEdit] so the caller saves drafts.
class DrawOnMapPage extends ConsumerStatefulWidget {
  const new({
    required this.editor,
    required this.onEdit,
    this.propertyId,
    super.key,
  });

  final BoundaryEditor editor;
  final void Function(void Function() change) onEdit;

  /// The property being edited, so its own vertices aren't snap targets.
  final String? propertyId;

  @override
  ConsumerState<DrawOnMapPage> createState() => _DrawOnMapPageState();
}

class _DrawOnMapPageState extends ConsumerState<DrawOnMapPage> {
  final _map = MapController();
  String? _selectedId;
  LatLng? _crosshair;

  BoundaryEditor get _editor => widget.editor;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  /// Vertices of other properties: the snap targets.
  List<LonLat> get _neighbourVertices => [
    for (final doc
        in ref.read(propertiesProvider).value ?? const <PropertyDocument>[])
      if (doc.id != widget.propertyId)
        if (doc.geometry.current case final current?)
          for (final v in current.vertices) (lon: v.lon, lat: v.lat),
  ];

  /// [position] snapped to a neighbour's vertex, if one is close on screen.
  LonLat _snapped(LonLat position) {
    final camera = _map.camera;
    return snapTo(position, _neighbourVertices, (p) {
          final o = camera.latLngToScreenOffset(LatLng(p.lat, p.lon));
          return (o.dx, o.dy);
        }) ??
        position;
  }

  void _add(LonLat position) {
    final snapped = _snapped(position);
    widget.onEdit(() {
      _selectedId = _editor
          .add(snapped, source: VertexSource.map, afterId: _selectedId)
          .id;
    });
    setState(() {});
  }

  void _moveSelected(LonLat position) {
    final id = _selectedId;
    if (id == null) return;
    final snapped = _snapped(position);
    widget.onEdit(() => _editor.move(id, snapped, source: VertexSource.map));
    setState(() {});
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    widget.onEdit(() {
      _editor.delete(id);
      _selectedId = null;
    });
    setState(() {});
  }

  void _select(Vertex v) {
    setState(() => _selectedId = v.id);
    _map.move(LatLng(v.lat, v.lon), _map.camera.zoom);
  }

  LonLat get _centre {
    final c = _crosshair ?? _map.camera.center;
    return (lon: c.longitude, lat: c.latitude);
  }

  MapOptions _options() {
    final points = [for (final v in _editor.ring()) LatLng(v.lat, v.lon)];
    return MapOptions(
      initialCenter: const LatLng(39.6, -8),
      initialZoom: 7,
      minZoom: 6,
      maxZoom: 21,
      initialCameraFit: points.length >= 2
          ? CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(64),
              maxZoom: 19,
            )
          : points.length == 1
          ? CameraFit.coordinates(coordinates: points, maxZoom: 18)
          : null,
      cameraConstraint: CameraConstraint.containCenter(bounds: MapPage.bounds),
      backgroundColor: mapBackground,
      onTap: (_, point) => _add((lon: point.longitude, lat: point.latitude)),
      onPositionChanged: (camera, _) =>
          setState(() => _crosshair = camera.center),
    );
  }

  Future<void> _search() async {
    final target = await showSearch<Bounds?>(
      context: context,
      delegate: MapSearchDelegate(
        l10n: AppLocalizations.of(context),
        properties:
            ref.read(propertiesProvider).value ?? const <PropertyDocument>[],
        caop: ref.read(caopProvider).value,
      ),
    );
    if (target == null) return;
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(target.minLat, target.minLon),
          LatLng(target.maxLat, target.maxLon),
        ),
        padding: const EdgeInsets.all(32),
        maxZoom: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colours = Theme.of(context).colorScheme;
    final language = Localizations.localeOf(context).languageCode;
    final settings = ref.watch(settingsProvider);
    final ring = _editor.ring();
    final selected = _selectedId == null ? null : _editor.byId(_selectedId!);
    final measurements = ring.length >= 3
        ? GeometryService.measure(_editor.parts)
        : null;
    final others =
        ref.watch(propertiesProvider).value ?? const <PropertyDocument>[];

    final centre = _crosshair == null ? null : _centre;
    final (line1, line2) = centre == null
        ? ('', '')
        : formatVertex(
            Vertex(
              id: '_',
              lon: centre.lon,
              lat: centre.lat,
              source: VertexSource.map,
            ),
            settings.coordinateFormat,
            language,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.drawTitle),
        actions: [
          IconButton(
            tooltip: l10n.mapSearch,
            icon: const Icon(Icons.search),
            onPressed: _search,
          ),
          IconButton(
            tooltip: l10n.actionUndo,
            icon: const Icon(Icons.undo),
            onPressed: _editor.canUndo
                ? () {
                    widget.onEdit(_editor.undo);
                    setState(() {});
                  }
                : null,
          ),
          IconButton(
            tooltip: l10n.actionRedo,
            icon: const Icon(Icons.redo),
            onPressed: _editor.canRedo
                ? () {
                    widget.onEdit(_editor.redo);
                    setState(() {});
                  }
                : null,
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionDone),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: _options(),
            children: [
              const BasemapTileLayer(),
              const ImageryTileLayer(),
              // Neighbouring properties, for orientation and snapping.
              PolygonLayer(
                polygons: [
                  for (final doc in others)
                    if (doc.id != widget.propertyId)
                      if (doc.geometry.current case final current?)
                        for (final part in current.parts)
                          if (part.first.length >= 3)
                            Polygon(
                              points: [
                                for (final v in part.first)
                                  LatLng(v.lat, v.lon),
                              ],
                              borderColor: Colors.white70,
                              borderStrokeWidth: 1.5,
                            ),
                ],
              ),
              if (ring.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: [for (final v in ring) LatLng(v.lat, v.lon)],
                      color: colours.primary.withValues(alpha: 0.25),
                      borderColor: Colors.yellowAccent,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                )
              else if (ring.length == 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [for (final v in ring) LatLng(v.lat, v.lon)],
                      color: Colors.yellowAccent,
                      strokeWidth: 2.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final (i, v) in ring.indexed)
                    Marker(
                      point: LatLng(v.lat, v.lon),
                      width: 44,
                      height: 44,
                      child: Semantics(
                        button: true,
                        label: 'V${i + 1}',
                        child: GestureDetector(
                          onTap: () => _select(v),
                          child: Center(
                            child: _VertexHandle(
                              surveyed: v.isSurveyed,
                              selected: v.id == _selectedId,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const ZoomInHint(),
              const Scalebar(alignment: Alignment.bottomLeft),
              const MapAttribution(),
            ],
          ),
          // The crosshair marks the map centre.
          const IgnorePointer(
            child: Center(
              child: Icon(
                Icons.add,
                size: 40,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      measurements == null
                          ? l10n.drawHint
                          : [
                              l10n.editorArea(
                                formatArea(
                                  measurements.areaSquareMetres,
                                  settings.areaUnit,
                                  languageCode: language,
                                ),
                              ),
                              l10n.editorPerimeter(
                                formatLength(
                                  measurements.perimeterMetres,
                                  languageCode: language,
                                ),
                              ),
                            ].join(' · '),
                    ),
                    if (centre != null)
                      Text(
                        '${l10n.crosshair}: $line1 · $line2',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.actionDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: selected == null ? null : _deleteSelected,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: selected == null
                      ? null
                      : () => _moveSelected(_centre),
                  icon: const Icon(Icons.open_with),
                  label: Text(l10n.actionMoveHere),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _add(_centre),
                  icon: const Icon(Icons.add_location_alt),
                  label: Text(l10n.actionAddHere),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VertexHandle extends StatelessWidget {
  const new({required this.surveyed, required this.selected});

  final bool surveyed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colour = selected ? Colors.orangeAccent : Colors.yellowAccent;
    final size = selected ? 24.0 : 18.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: surveyed ? colour : Colors.black54,
        border: Border.all(color: colour, width: 3),
      ),
    );
  }
}

/// Opens the drawing page for [editor]; used by the boundary editor.
Future<void> openDrawOnMap(
  BuildContext context, {
  required BoundaryEditor editor,
  required void Function(void Function() change) onEdit,
  String? propertyId,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        DrawOnMapPage(editor: editor, onEdit: onEdit, propertyId: propertyId),
  ),
);
