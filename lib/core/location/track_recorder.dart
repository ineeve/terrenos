/// Continuous walk mode (REG-3): a track recorded while the user walks
/// along the boundary, then simplified into vertices.
library;

import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/model/vertex.dart';

/// Keeps a fix every [minDistanceMetres] walked or every [interval],
/// whichever comes first (REG-3). Fixes less precise than
/// [maxAccuracyMetres] are left out and counted, since one bad fix would
/// put a spike in the boundary.
class TrackRecorder {
  new({
    this.minDistanceMetres = 2,
    this.interval = const Duration(seconds: 5),
    this.maxAccuracyMetres = GeometryValidator.defaultAccuracyThresholdMetres,
  });

  final double minDistanceMetres;
  final Duration interval;
  final double maxAccuracyMetres;

  final _points = <LocationFix>[];
  var _length = 0.0;
  var _skipped = 0;

  List<LocationFix> get points => List.unmodifiable(_points);

  /// Metres walked along the kept points.
  double get lengthMetres => _length;

  /// Fixes left out as too imprecise.
  int get skipped => _skipped;

  /// Records [fix] if it is precise enough and far or late enough after
  /// the last point kept. `true` when it was kept.
  bool add(LocationFix fix) {
    if (fix.accuracyMetres > maxAccuracyMetres) {
      _skipped++;
      return false;
    }
    final last = _points.lastOrNull;
    if (last != null) {
      final distance = inverse(
        (lon: last.lon, lat: last.lat),
        (lon: fix.lon, lat: fix.lat),
      ).distanceMetres;
      if (distance < minDistanceMetres &&
          fix.at.difference(last.at) < interval) {
        return false;
      }
      _length += distance;
    }
    _points.add(fix);
    return true;
  }
}

/// The track simplified with Douglas–Peucker at [toleranceMetres] (REG-3),
/// as a closed ring: points the user walked back to near the start are
/// dropped too. At least 3 points are kept when the track has them.
List<LocationFix> simplifyTrack(
  List<LocationFix> track,
  double toleranceMetres,
) {
  if (track.length <= 3) return track;
  final ring = [
    for (final (i, fix) in track.indexed)
      Vertex(id: '$i', lon: fix.lon, lat: fix.lat, source: VertexSource.gps),
  ];
  return [
    for (final v in GeometryService.simplifyRing(ring, toleranceMetres))
      track[int.parse(v.id)],
  ];
}
