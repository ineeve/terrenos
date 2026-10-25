import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/caop/caop.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/format/text.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/identifiers.dart';
import 'package:terrenos/core/properties/location.dart';
import 'package:terrenos/features/vertices/coordinate_entry_page.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Tile provider for imagery. Overridden in tests so no network is used.
final imageryTileProviderProvider = Provider<TileProvider>(
  (ref) => NetworkTileProvider(headers: const {'User-Agent': imageryUserAgent}),
);

final imagerySourceProvider =
    NotifierProvider<ImagerySourceController, ImagerySource>(
      ImagerySourceController.new,
    );

class ImagerySourceController extends Notifier<ImagerySource> {
  @override
  ImagerySource build() => ImagerySource.ortos2025;

  // A method rather than a setter, to match the other controllers.
  // ignore: use_setters_to_change_properties
  void select(ImagerySource source) => state = source;
}

/// The map tab (SPEC.md §3.2). Properties, location and offline areas are
/// added in later tasks (PLAN.md M1–M2).
class MapPage extends ConsumerStatefulWidget {
  const new({super.key});

  /// Mainland Portugal with room around it for border parcels.
  static final bounds = LatLngBounds(
    const LatLng(
      MainlandPortugal.minLat - MainlandPortugal.bufferLat,
      MainlandPortugal.minLon - MainlandPortugal.bufferLon,
    ),
    const LatLng(
      MainlandPortugal.maxLat + MainlandPortugal.bufferLat,
      MainlandPortugal.maxLon + MainlandPortugal.bufferLon,
    ),
  );

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  final _controller = MapController();
  StreamSubscription<Fix>? _fixes;
  Fix? _fix;
  var _centreOnNextFix = false;

  /// A point chosen with "Go to coordinates" (MAP-10).
  LatLng? _pin;

  @override
  void dispose() {
    unawaited(_fixes?.cancel());
    _controller.dispose();
    super.dispose();
  }

  /// MAP-4: asks for permission when first needed, then follows the GPS.
  Future<void> _locate() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final source = ref.read(locationSourceProvider);
    final availability = await source.ensurePermission();
    if (!mounted) return;
    switch (availability) {
      case LocationAvailability.granted:
        break;
      case LocationAvailability.serviceDisabled:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.locationServiceOff)),
        );
        return;
      case LocationAvailability.denied:
        messenger.showSnackBar(SnackBar(content: Text(l10n.locationDenied)));
        return;
      case LocationAvailability.deniedForever:
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.locationDenied),
            action: SnackBarAction(
              label: l10n.actionOpenSettings,
              onPressed: source.openSettings,
            ),
          ),
        );
        return;
    }
    if (_fix case final fix?) _centreOn(fix);
    _centreOnNextFix = _fix == null;
    _fixes ??= source.fixes().listen((fix) {
      setState(() => _fix = fix);
      if (_centreOnNextFix) {
        _centreOnNextFix = false;
        _centreOn(fix);
      }
    });
  }

  void _centreOn(Fix fix) => _controller.move(
    LatLng(fix.lat, fix.lon),
    max(_controller.camera.zoom, 17),
  );

  Future<void> _goToCoordinates() async {
    final l10n = AppLocalizations.of(context);
    final typed = await CoordinateEntryPage.open(
      context,
      title: l10n.goToCoordinates,
    );
    if (typed == null) return;
    final point = LatLng(typed.position.lat, typed.position.lon);
    setState(() => _pin = point);
    _controller.move(point, max(_controller.camera.zoom, 18));
  }

  Future<void> _search() async {
    final target = await showSearch<Bounds?>(
      context: context,
      delegate: MapSearchDelegate(
        l10n: AppLocalizations.of(context),
        properties: ref.read(propertiesProvider).value ?? const [],
        caop: ref.read(caopProvider).value,
      ),
    );
    if (target == null) return;
    _controller.fitCamera(
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
    final source = ref.watch(imagerySourceProvider);
    // Start loading CAOP early: the overlay and automatic locations use it.
    ref.watch(caopProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navMap),
        actions: [
          IconButton(
            tooltip: l10n.mapSearch,
            icon: const Icon(Icons.search),
            onPressed: _search,
          ),
          IconButton(
            tooltip: l10n.goToCoordinates,
            icon: const Icon(Icons.pin_drop_outlined),
            onPressed: _goToCoordinates,
          ),
          IconButton(
            tooltip: l10n.mapImagery,
            icon: const Icon(Icons.layers_outlined),
            onPressed: () => _chooseImagery(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // Several tabs have a FAB; no hero animation between them.
        heroTag: null,
        tooltip: l10n.myLocation,
        onPressed: _locate,
        child: const Icon(Icons.my_location),
      ),
      body: FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCenter: const LatLng(39.6, -8),
          initialZoom: 7,
          minZoom: 6,
          maxZoom: 20,
          cameraConstraint: CameraConstraint.containCenter(
            bounds: MapPage.bounds,
          ),
        ),
        children: [
          TileLayer(
            key: ValueKey(source),
            wmsOptions: WMSTileLayerOptions(
              baseUrl: source.baseUrl,
              layers: [source.layer],
              format: 'image/jpeg',
              version: '1.3.0',
              transparent: false,
            ),
            tileProvider: ref.watch(imageryTileProviderProvider),
            userAgentPackageName: 'pt.terrenos.app',
          ),
          const AdminBoundariesLayer(),
          const PropertiesLayer(),
          if (_fix case final fix?) ...[
            CircleLayer(
              circles: [
                CircleMarker(
                  point: LatLng(fix.lat, fix.lon),
                  radius: fix.accuracyMetres,
                  useRadiusInMeter: true,
                  color: Colors.lightBlueAccent.withValues(alpha: 0.2),
                  borderColor: Colors.lightBlueAccent,
                  borderStrokeWidth: 1,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(fix.lat, fix.lon),
                  width: 22,
                  height: 22,
                  child: Semantics(
                    label: l10n.locationAccuracy(
                      fix.accuracyMetres.toStringAsFixed(0),
                    ),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_pin case final pin?)
            MarkerLayer(
              markers: [
                Marker(
                  point: pin,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.redAccent,
                    size: 40,
                  ),
                ),
              ],
            ),
          const Scalebar(alignment: Alignment.bottomLeft),
          SimpleAttributionWidget(
            source: Text('$dgtAttribution ${source.year}'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseImagery(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final current = ref.read(imagerySourceProvider);
    final choice = await showModalBottomSheet<ImagerySource>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: RadioGroup<ImagerySource>(
            groupValue: current,
            onChanged: (s) => Navigator.of(context).pop(s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    l10n.mapImagery,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                RadioListTile(
                  value: ImagerySource.ortos2025,
                  title: Text(
                    l10n.imageryLatest('${ImagerySource.ortos2025.year}'),
                  ),
                ),
                RadioListTile(
                  value: ImagerySource.ortos2018,
                  title: Text(
                    l10n.imageryPrevious('${ImagerySource.ortos2018.year}'),
                  ),
                  subtitle: Text(l10n.imageryPreviousHint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice != null) ref.read(imagerySourceProvider.notifier).select(choice);
  }
}

/// The user's properties on the map, labelled with their names (MAP-5).
/// Tapping one opens a summary with Details and Edit (MAP-6).
class PropertiesLayer extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PropertiesLayer> createState() => _PropertiesLayerState();
}

class _PropertiesLayerState extends ConsumerState<PropertiesLayer> {
  final LayerHitNotifier<String> _hits = ValueNotifier(null);

  @override
  void dispose() {
    _hits.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final properties = ref.watch(propertiesProvider).value ?? const [];
    final colour = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () {
        final id = _hits.value?.hitValues.firstOrNull;
        if (id != null) unawaited(showPropertySummary(context, id));
      },
      child: PolygonLayer<String>(
        hitNotifier: _hits,
        polygons: [
          for (final doc in properties)
            if (doc.geometry.current case final current?)
              for (final part in current.parts)
                if (part.isNotEmpty && part.first.length >= 3)
                  Polygon<String>(
                    points: [for (final v in part.first) LatLng(v.lat, v.lon)],
                    holePointsList: [
                      for (final hole in part.skip(1))
                        [for (final v in hole) LatLng(v.lat, v.lon)],
                    ],
                    color: colour.withValues(alpha: 0.25),
                    borderColor: Colors.yellowAccent,
                    borderStrokeWidth: 2.5,
                    label: doc.name,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 3)],
                    ),
                    labelPlacementCalculator:
                        const PolygonLabelPlacementCalculator.polylabel(),
                    hitValue: doc.id,
                  ),
        ],
      ),
    );
  }
}

/// Bottom sheet with a property's name, process number and area (MAP-6).
Future<void> showPropertySummary(BuildContext context, String id) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(child: _PropertySummary(id: id)),
      ),
    );

class _PropertySummary extends ConsumerWidget {
  const new({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final doc = ref.watch(propertyProvider(id));
    if (doc == null) return const SizedBox.shrink();
    final language = Localizations.localeOf(context).languageCode;
    final unit = ref.watch(settingsProvider.select((s) => s.areaUnit));
    final current = doc.geometry.current;
    final area = current == null || current.vertices.length < 3
        ? null
        : GeometryService.measure(current.parts).areaSquareMetres;
    final number = doc.processNumber;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(doc.name, style: Theme.of(context).textTheme.titleLarge),
          if (number != null) Text(l10n.processNumberShort(number)),
          if (readLocation(doc) case final location?)
            Text(formatLocation(location)),
          if (area != null)
            Text(formatArea(area, unit, languageCode: language)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(context.push(Routes.propertyBoundary(id)));
                  },
                  icon: const Icon(Icons.edit_location_alt),
                  label: Text(l10n.editBoundaryTitle),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(context.push(Routes.property(id)));
                  },
                  child: Text(l10n.propertyDetails),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Official boundaries over the imagery (MAP-2): distritos when zoomed
/// out, concelhos at medium zoom, freguesias up close. Works offline.
class AdminBoundariesLayer extends ConsumerWidget {
  const new({super.key});

  static const concelhoZoom = 9.0;
  static const freguesiaZoom = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caop = ref.watch(caopProvider).value;
    if (caop == null) return const SizedBox.shrink();
    final zoom = MapCamera.of(context).zoom;
    final level = zoom >= freguesiaZoom
        ? AreaKind.freguesia
        : zoom >= concelhoZoom
        ? AreaKind.concelho
        : AreaKind.distrito;
    return PolylineLayer(polylines: ref.watch(boundaryLinesProvider(level)));
  }
}

/// Boundary lines per level, built once from CAOP.
final ProviderFamily<List<Polyline>, AreaKind> boundaryLinesProvider =
    Provider.family<List<Polyline>, AreaKind>((ref, kind) {
      final caop = ref.watch(caopProvider).value;
      if (caop == null) return const [];
      final (areas, width) = switch (kind) {
        AreaKind.distrito => (caop.distritos, 2.5),
        AreaKind.concelho => (caop.concelhos, 2.0),
        AreaKind.freguesia => (caop.freguesias, 1.2),
      };
      final colour = Colors.white.withValues(alpha: 0.75);
      return [
        for (final area in areas)
          for (final polygon in area.parts)
            for (final ring in polygon)
              Polyline(
                points: [
                  for (var i = 0; i < ring.length; i += 2)
                    LatLng(ring[i + 1], ring[i]),
                  LatLng(ring[1], ring[0]),
                ],
                color: colour,
                strokeWidth: width,
              ),
      ];
    });

/// Search over the user's properties (by name or process number) and CAOP
/// places (MAP-9, IDN-6). Returns the bounds to show.
class MapSearchDelegate extends SearchDelegate<Bounds?> {
  new({required this.l10n, required this.properties, required this.caop})
    : super(searchFieldLabel: l10n.mapSearch);

  final AppLocalizations l10n;
  final List<PropertyDocument> properties;
  final Caop? caop;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: l10n.actionClear,
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => const BackButton();

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final q = foldForSearch(query);
    if (q.isEmpty) return const SizedBox.shrink();
    final key = Identifiers.normalizeProcessNumber(query);
    final matchingProperties = [
      for (final doc in properties)
        if (doc.geometry.current case final current?
            when current.vertices.length >= 3 &&
                (foldForSearch(doc.name).contains(q) ||
                    (doc.processNumber != null &&
                        key.isNotEmpty &&
                        Identifiers.normalizeProcessNumber(doc.processNumber!)
                            .contains(key))))
          (doc, GeometryService.measure(current.parts).bounds),
    ];
    final places = caop?.search(query) ?? const <AdminArea>[];
    if (matchingProperties.isEmpty && places.isEmpty) {
      return Center(child: Text(l10n.mapSearchNoResults));
    }
    return ListView(
      children: [
        for (final (doc, bounds) in matchingProperties)
          ListTile(
            leading: const Icon(Icons.landscape),
            title: Text(doc.name),
            subtitle: doc.processNumber == null
                ? null
                : Text(l10n.processNumberShort(doc.processNumber!)),
            onTap: () => close(context, (
              minLon: bounds.minLon,
              minLat: bounds.minLat,
              maxLon: bounds.maxLon,
              maxLat: bounds.maxLat,
            )),
          ),
        for (final place in places)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(place.name),
            subtitle: Text(switch (place.kind) {
              AreaKind.distrito => l10n.areaKindDistrito,
              AreaKind.concelho =>
                '${l10n.areaKindConcelho} · ${place.distrito}',
              AreaKind.freguesia =>
                '${l10n.areaKindFreguesia} · ${place.concelho}',
            }),
            onTap: () => close(context, place.bounds),
          ),
      ],
    );
  }
}
