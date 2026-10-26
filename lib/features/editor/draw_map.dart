/// Draw mode: the boundary on the map with handles (REG-1, REG-7, REG-10),
/// over the same layers as the map tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/places/places.dart';
import 'package:terrenos/features/map/map_overlays.dart';
import 'package:terrenos/features/map/map_page.dart';
import 'package:terrenos/features/map/my_location.dart';
import 'package:terrenos/features/map/place_labels.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Where a tap or drag ends up, and whether it snapped to a neighbour's
/// vertex (REG-7).
typedef DrawPosition = ({LonLat position, bool snapped});

class DrawMap extends ConsumerStatefulWidget {
  const new({
    required this.parts,
    required this.selectedId,
    required this.onAdd,
    required this.onSelect,
    required this.onDrag,
    required this.onMove,
    required this.onInsert,
    required this.onDelete,
    this.propertyId,
    this.crossings = const [],
    super.key,
  });

  /// The boundary as shown, including any vertex being dragged.
  final BoundaryParts parts;
  final String? selectedId;

  /// Edges drawn in red because they cross (VAL-2).
  final List<Crossing> crossings;

  /// The property being edited; its saved boundary isn't a snap target.
  final String? propertyId;

  final ValueChanged<DrawPosition> onAdd;
  final ValueChanged<String> onSelect;

  /// While dragging, so the shape, area and coordinates follow the finger;
  /// `null` when the drag ends.
  final void Function(String id, DrawPosition? position) onDrag;

  /// When a drag ends: one undo step per drag.
  final void Function(String id, DrawPosition position) onMove;

  /// Tapping the midpoint handle that follows vertex `afterId`.
  final void Function(String afterId, LonLat position) onInsert;

  /// Long-press on a vertex.
  final ValueChanged<String> onDelete;

  /// Snap within this distance on screen (REG-7).
  static const snapPixels = 10.0;

  /// Visible handle size and the larger area that responds to touch.
  static const handleSize = 16.0;
  static const touchSize = 44.0;

  @override
  ConsumerState<DrawMap> createState() => _DrawMapState();
}

class _DrawMapState extends ConsumerState<DrawMap> {
  final _map = MapController();
  final GlobalKey _mapKey = GlobalKey();

  /// Finger position while dragging, for the loupe.
  Offset? _finger;
  String? _dragging;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  /// Vertices of the other properties on the phone (REG-7).
  List<LonLat> get _snapTargets => [
    for (final doc
        in ref.read(propertiesProvider).value ?? const <PropertyDocument>[])
      if (doc.id != widget.propertyId)
        if (doc.geometry.current case final current?)
          for (final v in current.vertices) (lon: v.lon, lat: v.lat),
  ];

  DrawPosition _at(Offset local) {
    final camera = _map.camera;
    for (final target in _snapTargets) {
      final screen = camera.latLngToScreenOffset(
        LatLng(target.lat, target.lon),
      );
      if ((screen - local).distance <= DrawMap.snapPixels) {
        return (position: target, snapped: true);
      }
    }
    final ll = camera.screenOffsetToLatLng(local);
    return (position: (lon: ll.longitude, lat: ll.latitude), snapped: false);
  }

  Offset _local(Offset global) =>
      (_mapKey.currentContext!.findRenderObject()! as RenderBox).globalToLocal(
        global,
      );

  MapOptions _options(BuildContext context) {
    final points = [
      for (final part in widget.parts)
        for (final ring in part)
          for (final v in ring) LatLng(v.lat, v.lon),
    ];
    // Where the user is, if known; otherwise where the map tab was.
    final fix = ref.read(myLocationProvider).fix;
    final view = ref.read(mapViewProvider);
    return MapOptions(
      initialCenter: fix == null ? view.center : LatLng(fix.lat, fix.lon),
      initialZoom: view.zoom < 16 ? 16 : view.zoom,
      initialCameraFit: points.length < 2
          ? (points.isEmpty
                ? null
                : CameraFit.coordinates(coordinates: points, maxZoom: 18))
          : CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(48),
              maxZoom: 19,
            ),
      minZoom: 6,
      maxZoom: 21,
      cameraConstraint: CameraConstraint.containCenter(bounds: MapPage.bounds),
      // Handles are easier to place on a map that keeps north up, and
      // without double-tap zoom a tap adds its vertex at once instead of
      // after the double-tap wait.
      interactionOptions: const InteractionOptions(
        flags:
            InteractiveFlag.all &
            ~InteractiveFlag.rotate &
            ~InteractiveFlag.doubleTapZoom &
            ~InteractiveFlag.doubleTapDragZoom,
      ),
      onTap: (tap, _) => widget.onAdd(_at(tap.relative!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(imagerySourceProvider);
    final colours = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final rings = [
      for (final part in widget.parts)
        for (final ring in part) ring,
    ];
    final byId = {
      for (final ring in rings)
        for (final v in ring) v.id: v,
    };

    return Stack(
      children: [
        KeyedSubtree(
          key: _mapKey,
          child: FlutterMap(
            mapController: _map,
            options: _options(context),
            children: [
              TileLayer(
                key: ValueKey(source),
                wmsOptions: source.wmsOptions,
                tileProvider: ref.watch(imageryTileProviderProvider),
                userAgentPackageName: 'pt.terrenos.app',
              ),
              const AdminBoundariesLayer(),
              const PlaceLabelsLayer(),
              _OtherProperties(except: widget.propertyId),
              const MyLocationLayer(),
              PolygonLayer(
                polygons: [
                  for (final ring in rings)
                    if (ring.length >= 3)
                      Polygon(
                        points: [for (final v in ring) LatLng(v.lat, v.lon)],
                        color: colours.primary.withValues(alpha: 0.2),
                        borderColor: Colors.yellowAccent,
                        borderStrokeWidth: 2.5,
                      ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  for (final c in widget.crossings)
                    for (final (a, b) in [c.first, c.second])
                      if ((byId[a], byId[b]) case (final va?, final vb?))
                        Polyline(
                          points: [
                            LatLng(va.lat, va.lon),
                            LatLng(vb.lat, vb.lon),
                          ],
                          color: Colors.redAccent,
                          strokeWidth: 5,
                        ),
                  for (final ring in rings)
                    if (ring.length == 2)
                      Polyline(
                        points: [for (final v in ring) LatLng(v.lat, v.lon)],
                        color: Colors.yellowAccent,
                        strokeWidth: 2.5,
                      ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final ring in rings)
                    if (ring.length >= 2)
                      for (var i = 0; i < ring.length; i++)
                        if (ring.length >= 3 || i == 0)
                          _midpoint(ring[i], ring[(i + 1) % ring.length], l10n),
                  for (final ring in rings)
                    for (final v in ring) _vertex(v, l10n),
                ],
              ),
              const Scalebar(alignment: Alignment.bottomLeft),
              MapAttribution(
                sources: ['$dgtAttribution ${source.year}', osmAttribution],
              ),
              Align(
                alignment: Alignment.bottomRight,
                // Above the attribution.
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 60),
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: l10n.mapImagery,
                    onPressed: () => showMapLayers(context, ref),
                    child: const Icon(Icons.layers_outlined),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_finger case final finger?) _Loupe(finger: finger),
      ],
    );
  }

  Marker _midpoint(Vertex a, Vertex b, AppLocalizations l10n) {
    final position = (lon: (a.lon + b.lon) / 2, lat: (a.lat + b.lat) / 2);
    return Marker(
      key: ValueKey('mid-${a.id}'),
      point: LatLng(position.lat, position.lon),
      width: DrawMap.touchSize,
      height: DrawMap.touchSize,
      child: Semantics(
        button: true,
        label: l10n.drawInsertVertex,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onInsert(a.id, position),
          child: Center(
            child: Container(
              width: DrawMap.handleSize * 0.75,
              height: DrawMap.handleSize * 0.75,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black54),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Marker _vertex(Vertex v, AppLocalizations l10n) {
    final selected = v.id == widget.selectedId || v.id == _dragging;
    final size = selected ? DrawMap.handleSize * 1.4 : DrawMap.handleSize;
    // Planned vertices are hollow, surveyed ones filled (VTX-11).
    final fill = v.isSurveyed ? Colors.yellowAccent : Colors.white;
    return Marker(
      key: ValueKey('vertex-${v.id}'),
      point: LatLng(v.lat, v.lon),
      width: DrawMap.touchSize,
      height: DrawMap.touchSize,
      child: Semantics(
        button: true,
        selected: selected,
        label: l10n.drawVertex,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelect(v.id),
          onLongPress: () => widget.onDelete(v.id),
          onPanStart: (details) {
            setState(() {
              _dragging = v.id;
              _finger = _local(details.globalPosition);
            });
            widget.onSelect(v.id);
          },
          onPanUpdate: (details) {
            final local = _local(details.globalPosition);
            setState(() => _finger = local);
            widget.onDrag(v.id, _at(local));
          },
          onPanEnd: (_) => _endDrag(v.id),
          onPanCancel: () => _endDrag(v.id, commit: false),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: selected ? Colors.orangeAccent : fill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: v.isSurveyed ? Colors.black : Colors.black87,
                  width: v.isSurveyed ? 2 : 3,
                ),
                boxShadow: const [
                  BoxShadow(blurRadius: 3, color: Colors.black38),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _endDrag(String id, {bool commit = true}) {
    final finger = _finger;
    setState(() {
      _dragging = null;
      _finger = null;
    });
    widget.onDrag(id, null);
    if (commit && finger != null) widget.onMove(id, _at(finger));
  }
}

/// A magnified view above the finger while dragging (REG-10).
class _Loupe extends StatelessWidget {
  const new({required this.finger});

  final Offset finger;

  static const size = 120.0;

  /// How far above the finger the loupe sits, so the finger doesn't hide
  /// it; below the finger near the top edge.
  static const lift = 100.0;

  @override
  Widget build(BuildContext context) {
    final offset = finger.dy > lift + size / 2 ? -lift : lift;
    return Positioned(
      left: finger.dx - size / 2,
      top: finger.dy + offset - size / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size(size, size),
          magnificationScale: 2.5,
          // Magnify what is under the finger, not under the loupe.
          focalPointOffset: Offset(0, -offset),
          decoration: const MagnifierDecoration(
            shape: CircleBorder(
              side: BorderSide(color: Colors.white, width: 3),
            ),
            shadows: [BoxShadow(blurRadius: 6, color: Colors.black45)],
          ),
        ),
      ),
    );
  }
}

/// The other properties, for context and snapping; not tappable here.
class _OtherProperties extends ConsumerWidget {
  const new({required this.except});

  final String? except;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider).value ?? const [];
    return PolygonLayer(
      polygons: [
        for (final doc in properties)
          if (doc.id != except)
            if (doc.geometry.current case final current?)
              for (final part in current.parts)
                if (part.isNotEmpty && part.first.length >= 3)
                  Polygon(
                    points: [for (final v in part.first) LatLng(v.lat, v.lon)],
                    color: Colors.white.withValues(alpha: 0.1),
                    borderColor: Colors.white70,
                    borderStrokeWidth: 1.5,
                    label: doc.name,
                    labelStyle: const TextStyle(
                      color: Colors.white70,
                      shadows: [Shadow(blurRadius: 3)],
                    ),
                  ),
      ],
    );
  }
}
