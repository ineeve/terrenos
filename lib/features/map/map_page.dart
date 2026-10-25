import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/map/imagery.dart';
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
