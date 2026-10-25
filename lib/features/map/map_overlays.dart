/// Administrative boundaries over the map (MAP-2) and the compass (MAP-11).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Whether the CAOP boundaries are drawn; switched in the layers sheet.
final adminOverlayProvider = NotifierProvider<AdminOverlayController, bool>(
  AdminOverlayController.new,
);

class AdminOverlayController extends Notifier<bool> {
  @override
  bool build() => true;

  // A method rather than a setter, to match the other controllers.
  // ignore: use_setters_to_change_properties
  void show({required bool visible}) => state = visible;
}

/// The boundary lines as map polylines, built once per level.
final adminBoundaryLinesProvider =
    Provider<Map<BoundaryLevel, List<Polyline>>?>((ref) {
      final caop = ref.watch(adminBoundariesProvider).value;
      if (caop == null) return null;
      final lines = {
        for (final level in BoundaryLevel.values) level: <Polyline>[],
      };
      for (var i = 0; i < caop.arcs.length; i++) {
        final points = caop.arcs[i];
        final level = caop.levels[i];
        final style = AdminBoundariesLayer.styles[level]!;
        lines[level]!.add(
          Polyline(
            points: [
              for (var j = 0; j < points.length; j += 2)
                LatLng(
                  points[j + 1] / AdminBoundaries.scale,
                  points[j] / AdminBoundaries.scale,
                ),
            ],
            color: style.colour,
            strokeWidth: style.width,
            borderColor: Colors.black45,
            borderStrokeWidth: style.width >= 2 ? 1 : 0,
          ),
        );
      }
      return lines;
    });

/// Distrito borders at every zoom, concelhos from z9 and freguesias from
/// z12, so the map isn't cluttered when zoomed out (MAP-2).
class AdminBoundariesLayer extends ConsumerWidget {
  const new({super.key});

  static const concelhoZoom = 9.0;
  static const freguesiaZoom = 12.0;

  static const Map<BoundaryLevel, ({Color colour, double width})> styles = {
    BoundaryLevel.outer: (colour: Colors.white, width: 2.5),
    BoundaryLevel.distrito: (colour: Colors.white, width: 2.5),
    BoundaryLevel.concelho: (colour: Color(0xE6FFFFFF), width: 1.8),
    BoundaryLevel.freguesia: (colour: Color(0xB3FFFFFF), width: 1.0),
  };

  /// The levels drawn at [zoom], most detailed first so wider borders are
  /// painted on top.
  static List<BoundaryLevel> levelsAt(double zoom) => [
    if (zoom >= freguesiaZoom) BoundaryLevel.freguesia,
    if (zoom >= concelhoZoom) BoundaryLevel.concelho,
    BoundaryLevel.distrito,
    BoundaryLevel.outer,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(adminBoundaryLinesProvider);
    if (lines == null || !ref.watch(adminOverlayProvider)) {
      return const SizedBox.shrink();
    }
    final zoom = MapCamera.of(context).zoom;
    return PolylineLayer(
      polylines: [for (final level in levelsAt(zoom)) ...lines[level]!],
    );
  }
}

/// Shows north while the map is rotated; tapping turns north up again
/// (MAP-11).
class CompassButton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final rotation = MapCamera.of(context).rotation;
    if (rotation % 360 == 0) return const SizedBox.shrink();
    return FloatingActionButton.small(
      heroTag: null,
      tooltip: AppLocalizations.of(context).mapNorthUp,
      onPressed: () => MapController.of(context).rotate(0),
      child: Transform.rotate(
        angle: rotation * pi / 180,
        child: const Icon(Icons.navigation),
      ),
    );
  }
}
