/// Boundary validation rules VAL-1 to VAL-9 (SPEC.md §3.5).
///
/// Overlap with other properties (VAL-7) needs the other properties and is
/// checked separately.
library;

import 'package:meta/meta.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';

/// Mainland Portugal's extent in degrees (D7) and the 50 km tolerance
/// around it used by VAL-6.
abstract final class MainlandPortugal {
  static const minLat = 36.9;
  static const maxLat = 42.2;
  static const minLon = -9.6;
  static const maxLon = -6.1;

  /// About 50 km: 0.45° of latitude, 0.6° of longitude at 40° N.
  static const bufferLat = 0.45;
  static const bufferLon = 0.6;

  static bool contains(double lat, double lon, {bool withBuffer = false}) {
    final dLat = withBuffer ? bufferLat : 0;
    final dLon = withBuffer ? bufferLon : 0;
    return lat >= minLat - dLat &&
        lat <= maxLat + dLat &&
        lon >= minLon - dLon &&
        lon <= maxLon + dLon;
  }
}

enum Severity {
  /// Blocks saving.
  error,

  /// Shown to the user; saving is allowed.
  warning,
}

@immutable
sealed class GeometryIssue {
  const new();

  Severity get severity;
}

/// VAL-1: a ring has fewer than 3 distinct vertices.
final class TooFewVertices extends GeometryIssue {
  const new({required this.part, required this.ring});

  final int part;
  final int ring;

  @override
  Severity get severity => Severity.error;
}

/// VAL-2: edges cross or touch.
final class SelfIntersection extends GeometryIssue {
  const new(this.crossings);

  final List<Crossing> crossings;

  @override
  Severity get severity => Severity.error;
}

/// VAL-3: area outside 1 m² … 10 000 ha.
final class AreaOutOfRange extends GeometryIssue {
  const new(this.areaSquareMetres);

  static const minSquareMetres = 1.0;
  static const double maxSquareMetres = 10000 * 10000.0;

  final double areaSquareMetres;

  @override
  Severity get severity => Severity.error;
}

/// VAL-6: vertices outside mainland Portugal (with a 50 km tolerance).
final class OutsidePortugal extends GeometryIssue {
  const new({required this.vertexIds, required this.swapLooksRight});

  final List<String> vertexIds;

  /// Swapping latitude and longitude would put these vertices in Portugal,
  /// the usual cause in imported files.
  final bool swapLooksRight;

  @override
  Severity get severity => Severity.warning;
}

/// VAL-8: GPS vertices that are imprecise or came from a mock location.
final class LowConfidenceVertices extends GeometryIssue {
  const new({required this.imprecise, required this.mocked});

  final List<String> imprecise;
  final List<String> mocked;

  @override
  Severity get severity => Severity.warning;
}

/// VAL-9: too many vertices.
final class TooManyVertices extends GeometryIssue {
  const new(this.count);

  static const max = 5000;

  final int count;

  @override
  Severity get severity => Severity.error;
}

@immutable
class ValidationResult {
  const new({
    required this.parts,
    required this.issues,
    required this.removedDuplicates,
    this.measurements,
  });

  /// The boundary to save: duplicates removed (VAL-5).
  final BoundaryParts parts;
  final List<GeometryIssue> issues;
  final int removedDuplicates;

  /// Present when the boundary is measurable.
  final Measurements? measurements;

  bool get canSave => issues.every((i) => i.severity != Severity.error);
}

abstract final class GeometryValidator {
  static const defaultAccuracyThresholdMetres = 15.0;

  static ValidationResult validate(
    BoundaryParts parts, {
    double accuracyThresholdMetres = defaultAccuracyThresholdMetres,
  }) {
    final cleaned = GeometryService.withoutDuplicates(parts);
    final removed = _count(parts) - _count(cleaned);
    final issues = <GeometryIssue>[];

    var ringsOk = cleaned.isNotEmpty;
    for (var p = 0; p < cleaned.length; p++) {
      if (cleaned[p].isEmpty) ringsOk = false;
      for (var r = 0; r < cleaned[p].length; r++) {
        if (cleaned[p][r].length < 3) {
          issues.add(TooFewVertices(part: p, ring: r));
          ringsOk = false;
        }
      }
    }

    final count = _count(cleaned);
    if (count > TooManyVertices.max) issues.add(TooManyVertices(count));

    final vertices = [
      for (final part in cleaned)
        for (final ring in part) ...ring,
    ];
    final outside = [
      for (final v in vertices)
        if (!MainlandPortugal.contains(v.lat, v.lon, withBuffer: true)) v,
    ];
    if (outside.isNotEmpty) {
      issues.add(
        OutsidePortugal(
          vertexIds: [for (final v in outside) v.id],
          swapLooksRight: outside.every(
            (v) => MainlandPortugal.contains(v.lon, v.lat),
          ),
        ),
      );
    }

    final imprecise = [
      for (final v in vertices)
        if (v.gps != null && v.gps!.accuracyMetres > accuracyThresholdMetres)
          v.id,
    ];
    final mocked = [
      for (final v in vertices)
        if (v.gps?.mocked ?? false) v.id,
    ];
    if (imprecise.isNotEmpty || mocked.isNotEmpty) {
      issues.add(LowConfidenceVertices(imprecise: imprecise, mocked: mocked));
    }

    Measurements? measurements;
    // Crossing and area checks only make sense on well-formed rings, and
    // only once the count is small enough to check quickly.
    if (ringsOk && count <= TooManyVertices.max) {
      final crossings = GeometryService.crossings(cleaned);
      if (crossings.isNotEmpty) issues.add(SelfIntersection(crossings));
      measurements = GeometryService.measure(cleaned);
      final area = measurements.areaSquareMetres;
      if (area < AreaOutOfRange.minSquareMetres ||
          area > AreaOutOfRange.maxSquareMetres) {
        issues.add(AreaOutOfRange(area));
      }
    }

    return ValidationResult(
      parts: cleaned,
      issues: List.unmodifiable(issues),
      removedDuplicates: removed,
      measurements: measurements,
    );
  }

  static int _count(BoundaryParts parts) => parts.fold(
    0,
    (sum, part) => sum + part.fold(0, (s, ring) => s + ring.length),
  );
}

/// Convenience for tests and callers holding plain vertex lists.
BoundaryParts singleRing(List<Vertex> ring) => [
  [ring],
];
