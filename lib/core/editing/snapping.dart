/// Snapping to neighbouring properties' vertices (REG-7), so shared
/// boundaries line up exactly.
library;

import 'package:terrenos/core/geometry/geodesy.dart';

/// Default snapping distance on screen, in logical pixels.
const snapPixels = 10.0;

/// The candidate closest to [target] on screen, if it is within
/// [maxPixels]. [toScreen] converts a position to screen pixels for the
/// current map view.
LonLat? snapTo(
  LonLat target,
  Iterable<LonLat> candidates,
  (double, double) Function(LonLat) toScreen, {
  double maxPixels = snapPixels,
}) {
  final (tx, ty) = toScreen(target);
  LonLat? best;
  var bestSq = maxPixels * maxPixels;
  for (final c in candidates) {
    final (x, y) = toScreen(c);
    final d = (x - tx) * (x - tx) + (y - ty) * (y - ty);
    if (d <= bestSq) {
      bestSq = d;
      best = c;
    }
  }
  return best;
}
