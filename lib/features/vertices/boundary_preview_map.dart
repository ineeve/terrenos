import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/features/map/imagery_layer.dart';

/// A non-interactive map of a boundary over the imagery, framed to fit.
/// Planned vertices are hollow, surveyed ones filled (VTX-11).
class BoundaryPreviewMap extends ConsumerWidget {
  const new({
    required this.parts,
    this.highlightId,
    this.height = 220,
    super.key,
  });

  final BoundaryParts parts;
  final String? highlightId;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colours = Theme.of(context).colorScheme;
    final points = [
      for (final part in parts)
        for (final ring in part)
          for (final v in ring) LatLng(v.lat, v.lon),
    ];

    // The preview is not interactive; editing happens in the vertex table.
    const interaction = InteractionOptions(flags: InteractiveFlag.none);
    final options = points.isEmpty
        ? const MapOptions(
            initialCenter: LatLng(39.6, -8),
            initialZoom: 6,
            interactionOptions: interaction,
            backgroundColor: mapBackground,
          )
        : MapOptions(
            backgroundColor: mapBackground,
            initialCameraFit: points.length == 1
                ? CameraFit.coordinates(
                    coordinates: points,
                    maxZoom: 18,
                    padding: const EdgeInsets.all(48),
                  )
                : CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(32),
                    maxZoom: 19,
                  ),
            interactionOptions: interaction,
          );

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          // Rebuild when the boundary changes so the camera re-fits.
          key: ValueKey(Object.hashAll(points)),
          options: options,
          children: [
            const BasemapTileLayer(),
            const ImageryTileLayer(),
            for (final part in parts)
              for (final ring in part)
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
                for (final part in parts)
                  for (final ring in part)
                    for (final v in ring)
                      Marker(
                        point: LatLng(v.lat, v.lon),
                        width: 18,
                        height: 18,
                        child: _VertexDot(
                          surveyed: v.isSurveyed,
                          highlighted: v.id == highlightId,
                        ),
                      ),
              ],
            ),
            const MapAttribution(),
          ],
        ),
      ),
    );
  }
}

class _VertexDot extends StatelessWidget {
  const new({required this.surveyed, required this.highlighted});

  final bool surveyed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colour = highlighted ? Colors.orangeAccent : Colors.yellowAccent;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: surveyed ? colour : Colors.black54,
        border: Border.all(color: colour, width: 3),
      ),
    );
  }
}
