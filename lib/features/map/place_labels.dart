/// Names of cities, towns, villages and hamlets on the map (MAP-15).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/places/places.dart';

/// Whether place names are drawn; switched in the layers sheet.
final placeLabelsProvider = NotifierProvider<PlaceLabelsController, bool>(
  PlaceLabelsController.new,
);

class PlaceLabelsController extends Notifier<bool> {
  @override
  bool build() => true;

  // A method rather than a setter, to match the other controllers.
  // ignore: use_setters_to_change_properties
  void show({required bool visible}) => state = visible;
}

/// Cities at every zoom, towns from z9, villages from z11 and hamlets from
/// z13. Bigger places are labelled first, and a name that would overlap
/// one already drawn is left out, so the map never fills with text.
/// Labels stay upright when the map is rotated.
class PlaceLabelsLayer extends ConsumerStatefulWidget {
  const new({super.key});

  static const Map<PlaceKind, double> minZoom = {
    PlaceKind.city: 0,
    PlaceKind.town: 9,
    PlaceKind.village: 11,
    PlaceKind.hamlet: 13,
  };

  static const Map<PlaceKind, TextStyle> styles = {
    PlaceKind.city: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    PlaceKind.town: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    PlaceKind.village: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    PlaceKind.hamlet: TextStyle(fontSize: 12),
  };

  /// At most this many names at once, however many would fit.
  static const maxLabels = 120;

  /// The places labelled with [camera], in drawing order, with the box
  /// each label takes on screen. [sizeOf] gives a label's size.
  static List<({Place place, Rect box})> layout(
    MapCamera camera,
    List<Place> places,
    Size Function(Place place) sizeOf,
  ) {
    final kinds = {
      for (final MapEntry(:key, :value) in minZoom.entries)
        if (camera.zoom >= value) key,
    };
    // The visible area in the asset's integer units, so most places are
    // skipped without any projection.
    final visible = camera.visibleBounds;
    const scale = AdminBoundaries.scale;
    final west = visible.west * scale;
    final east = visible.east * scale;
    final south = visible.south * scale;
    final north = visible.north * scale;

    final placed = <({Place place, Rect box})>[];
    for (final place in places) {
      // Places are ordered by kind, so the rest are smaller still.
      if (!kinds.contains(place.kind)) break;
      if (place.x < west || place.x > east) continue;
      if (place.y < south || place.y > north) continue;
      final box = Rect.fromCenter(
        center: camera.latLngToScreenOffset(place.point),
        width: sizeOf(place).width,
        height: sizeOf(place).height,
      );
      // A little room between names.
      final spaced = box.inflate(_gap);
      if (placed.any((p) => p.box.inflate(_gap).overlaps(spaced))) continue;
      placed.add((place: place, box: box));
      if (placed.length == maxLabels) break;
    }
    return placed;
  }

  static const _gap = 4.0;

  @override
  ConsumerState<PlaceLabelsLayer> createState() => _PlaceLabelsLayerState();
}

class _PlaceLabelsLayerState extends ConsumerState<PlaceLabelsLayer> {
  /// Laid-out text per place: the white name and its dark outline.
  final _labels = <Place, ({TextPainter fill, TextPainter halo})>{};
  TextScaler? _scaler;

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final label in _labels.values) {
      label.fill.dispose();
      label.halo.dispose();
    }
    _labels.clear();
  }

  ({TextPainter fill, TextPainter halo}) _label(Place place) {
    return _labels[place] ??= () {
      final style = PlaceLabelsLayer.styles[place.kind]!;
      TextPainter painter(TextStyle style) => TextPainter(
        text: TextSpan(text: place.name, style: style),
        textDirection: TextDirection.ltr,
        textScaler: _scaler!,
      )..layout();
      return (
        fill: painter(style.copyWith(color: Colors.white)),
        halo: painter(
          style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.black87,
          ),
        ),
      );
    }();
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(placesProvider).value?.places;
    if (places == null || !ref.watch(placeLabelsProvider)) {
      return const SizedBox.shrink();
    }
    final scaler = MediaQuery.textScalerOf(context);
    // Only places near the screen are ever laid out; drop them all now
    // and then rather than keep thousands while panning around.
    if (scaler != _scaler || _labels.length > 2000) {
      _clear();
      _scaler = scaler;
    }
    final labels = PlaceLabelsLayer.layout(
      MapCamera.of(context),
      places,
      (place) => _label(place).fill.size,
    );
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PlaceLabelsPainter([
          for (final (:place, :box) in labels) (label: _label(place), box: box),
        ]),
      ),
    );
  }
}

class _PlaceLabelsPainter extends CustomPainter {
  new(this.labels);

  final List<({({TextPainter fill, TextPainter halo}) label, Rect box})> labels;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (:label, :box) in labels) {
      label.halo.paint(canvas, box.topLeft);
      label.fill.paint(canvas, box.topLeft);
    }
  }

  // Built anew whenever the camera moves.
  @override
  bool shouldRepaint(_PlaceLabelsPainter old) => true;
}
