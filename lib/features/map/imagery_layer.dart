import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/features/map/map_page.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Background shown where there is no imagery: zoomed out, or offline
/// before an area is downloaded (MAP-3).
const mapBackground = Color(0xFFE6EBE0);

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
