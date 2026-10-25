import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/features/map/map_page.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Background shown where there is no imagery: zoomed out, or offline
/// before an area is downloaded (MAP-3).
const mapBackground = Color(0xFFE6EBE0);

/// OpenStreetMap as a low-detail basemap, below the imagery zoom only
/// (ADR 0008). Goes underneath [ImageryTileLayer].
class BasemapTileLayer extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TileLayer(
    urlTemplate: OsmBasemap.urlTemplate,
    tileProvider: ref.watch(imageryTileProviderProvider),
    maxZoom: OsmBasemap.maxZoom.toDouble(),
    userAgentPackageName: 'pt.terrenos.app',
  );
}

/// Credits the map sources on screen: OpenStreetMap while its basemap is
/// shown, DGT once the orthophotos are. Tapping opens OpenStreetMap's
/// copyright page, as its tile policy asks. Wraps on narrow maps.
class MapAttribution extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = MapCamera.of(context).zoom;
    final source = ref.watch(imagerySourceProvider);
    final parts = [
      if (zoom <= OsmBasemap.maxZoom) OsmBasemap.attribution,
      if (zoom >= ImagerySource.minZoom) '$dgtAttribution ${source.year}',
    ];
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(left: 96),
        child: Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
          child: InkWell(
            onTap: () => launchUrl(
              Uri.parse(OsmBasemap.copyrightUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                parts.join(' · '),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The selected DGT orthophotos, from zoom 14 (ImagerySource.minZoom).
/// Shared by every map in the app.
class ImageryTileLayer extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(imagerySourceProvider);
    return TileLayer(
      key: ValueKey(source),
      wmsOptions: WMSTileLayerOptions(
        baseUrl: source.baseUrl,
        layers: [source.layer],
        format: 'image/jpeg',
        version: '1.3.0',
        transparent: false,
      ),
      tileProvider: ref.watch(imageryTileProviderProvider),
      minZoom: ImagerySource.minZoom.toDouble(),
      userAgentPackageName: 'pt.terrenos.app',
    );
  }
}

/// "Zoom in to see the orthophotos", shown below the imagery zoom.
class ZoomInHint extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    if (MapCamera.of(context).zoom >= ImagerySource.minZoom) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.zoom_in, size: 20),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context).zoomInForImagery),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
