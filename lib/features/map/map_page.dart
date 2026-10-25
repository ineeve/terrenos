import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/offline_tile_provider.dart';
import 'package:terrenos/features/map/map_overlays.dart';
import 'package:terrenos/features/map/my_location.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Tile provider for imagery: downloaded tiles first, then the network.
/// Overridden in tests so no network is used.
final imageryTileProviderProvider = Provider<TileProvider>((ref) {
  final provider = OfflineFirstTileProvider(
    storage: ref.watch(tileStorageProvider),
  );
  ref.onDispose(provider.close);
  return provider;
});

/// Where the map tab is looking, so offline areas are framed from there.
final mapViewProvider = NotifierProvider<MapViewController, MapView>(
  MapViewController.new,
);

typedef MapView = ({LatLng center, double zoom});

class MapViewController extends Notifier<MapView> {
  @override
  MapView build() => (center: const LatLng(39.6, -8), zoom: 7);

  // A method rather than a setter, to match the other controllers.
  // ignore: use_setters_to_change_properties
  void update(MapView view) => state = view;
}

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

/// The map tab (SPEC.md §3.2): imagery, administrative boundaries, the
/// user's properties and position.
class MapPage extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final source = ref.watch(imagerySourceProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navMap),
        actions: [
          IconButton(
            tooltip: l10n.offlineMapsTitle,
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => unawaited(context.push(Routes.offlineAreas)),
          ),
          IconButton(
            tooltip: l10n.mapImagery,
            icon: const Icon(Icons.layers_outlined),
            onPressed: () => _chooseImagery(context, ref),
          ),
        ],
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: const LatLng(39.6, -8),
          initialZoom: 7,
          minZoom: 6,
          maxZoom: 20,
          cameraConstraint: CameraConstraint.containCenter(bounds: bounds),
          onPositionChanged: (camera, _) => ref
              .read(mapViewProvider.notifier)
              .update((center: camera.center, zoom: camera.zoom)),
        ),
        children: [
          TileLayer(
            key: ValueKey(source),
            wmsOptions: source.wmsOptions,
            tileProvider: ref.watch(imageryTileProviderProvider),
            userAgentPackageName: 'pt.terrenos.app',
          ),
          const AdminBoundariesLayer(),
          const PropertiesLayer(),
          const MyLocationLayer(),
          const Scalebar(alignment: Alignment.bottomLeft),
          SimpleAttributionWidget(
            source: Text('$dgtAttribution ${source.year}'),
          ),
          const Align(
            alignment: Alignment.topRight,
            child: Padding(padding: EdgeInsets.all(12), child: CompassButton()),
          ),
          const Align(
            alignment: Alignment.bottomRight,
            // Above the attribution.
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 44),
              child: CentreOnMeButton(),
            ),
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
                const Divider(),
                Consumer(
                  builder: (context, ref, _) => SwitchListTile(
                    title: Text(l10n.mapAdminBoundaries),
                    subtitle: Text(l10n.mapAdminBoundariesHint),
                    value: ref.watch(adminOverlayProvider),
                    onChanged: (visible) => ref
                        .read(adminOverlayProvider.notifier)
                        .show(visible: visible),
                  ),
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
