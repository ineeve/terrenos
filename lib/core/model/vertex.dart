/// Boundary vertices (SPEC.md §3.4, §7.1, §9.5.1).
library;

import 'package:meta/meta.dart';
import 'package:terrenos/core/crdt/canonical_json.dart';

/// How a vertex's coordinates were obtained.
enum VertexSource {
  gps('gps'),
  typed('typed'),
  map('map'),
  import('import');

  new(this.code);

  static VertexSource fromCode(String code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => throw FormatException('Unknown vertex source', code),
  );

  final String code;
}

/// Coordinates exactly as the user typed them, so they can be shown back
/// without rounding drift (SPEC.md §7.1).
@immutable
class CoordinateInput {
  const new({required this.crs, required this.x, required this.y});

  factory fromJson(Map<String, Object?> json) => CoordinateInput(
    crs: json['crs']! as String,
    x: (json['x']! as num).toDouble(),
    y: (json['y']! as num).toDouble(),
  );

  /// `EPSG:4326` or `EPSG:3763`.
  final String crs;
  final double x;
  final double y;

  Map<String, Object?> toJson() => {'crs': crs, 'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      other is CoordinateInput &&
      other.crs == crs &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(crs, x, y);
}

/// The GPS measurement that captured or confirmed a vertex (SPEC.md §7.3).
@immutable
class GpsFix {
  const new({
    required this.accuracyMetres,
    required this.samples,
    required this.capturedAt,
    required this.mocked,
    required this.deviceId,
  });

  factory fromJson(Map<String, Object?> json) => GpsFix(
    accuracyMetres: (json['acc']! as num).toDouble(),
    samples: json['n']! as int,
    capturedAt: DateTime.parse(json['at']! as String),
    mocked: json['mocked']! as bool,
    deviceId: json['dev']! as String,
  );

  final double accuracyMetres;
  final int samples;
  final DateTime capturedAt;
  final bool mocked;
  final String deviceId;

  Map<String, Object?> toJson() => {
    'acc': accuracyMetres,
    'n': samples,
    'at': capturedAt.toUtc().toIso8601String(),
    'mocked': mocked,
    'dev': deviceId,
  };

  @override
  bool operator ==(Object other) =>
      other is GpsFix &&
      canonicalJson(other.toJson()) == canonicalJson(toJson());

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;
}

@immutable
class Vertex {
  /// Coordinates are rounded to 7 decimal places (~1 cm), the stored
  /// precision, so that equal positions always serialise identically.
  new({
    required this.id,
    required double lon,
    required double lat,
    required this.source,
    this.input,
    this.gps,
  }) : lon = roundCoordinate(lon),
       lat = roundCoordinate(lat);

  factory fromJson(Map<String, Object?> json) => Vertex(
    id: json['id']! as String,
    lon: (json['lon']! as num).toDouble(),
    lat: (json['lat']! as num).toDouble(),
    source: VertexSource.fromCode(json['src']! as String),
    input: switch (json['input']) {
      final Map<String, Object?> m => CoordinateInput.fromJson(m),
      _ => null,
    },
    gps: switch (json['gps']) {
      final Map<String, Object?> m => GpsFix.fromJson(m),
      _ => null,
    },
  );

  /// Unique within its property; kept when the vertex is moved or
  /// re-surveyed, never reused after deletion.
  final String id;
  final double lon;
  final double lat;
  final VertexSource source;
  final CoordinateInput? input;
  final GpsFix? gps;

  /// Surveyed vertices have been captured or confirmed with GPS on site;
  /// all others are planned (VTX-11).
  bool get isSurveyed => gps != null;

  static double roundCoordinate(double value) =>
      (value * 1e7).roundToDouble() / 1e7;

  Map<String, Object?> toJson() => {
    'id': id,
    'lon': lon,
    'lat': lat,
    'src': source.code,
    if (input != null) 'input': input!.toJson(),
    if (gps != null) 'gps': gps!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Vertex &&
      canonicalJson(other.toJson()) == canonicalJson(toJson());

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;
}
