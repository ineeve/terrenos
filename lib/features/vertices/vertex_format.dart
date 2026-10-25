import 'package:terrenos/core/crs/coordinates.dart';
import 'package:terrenos/core/crs/pt_tm06.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/settings/app_settings.dart';

/// A vertex's coordinates as two display lines in the user's format.
///
/// PT-TM06 values the user typed are shown exactly as typed (SPEC.md §7.1),
/// not recomputed from the stored WGS84 position.
(String, String) formatVertex(
  Vertex v,
  CoordinateFormat format,
  String languageCode,
) {
  switch (format) {
    case CoordinateFormat.decimalDegrees:
      return (
        'Lat ${formatDecimalDegrees(v.lat, languageCode)}',
        'Lon ${formatDecimalDegrees(v.lon, languageCode)}',
      );
    case CoordinateFormat.degreesMinutesSeconds:
      return (
        formatDms(v.lat, CoordinateAxis.latitude, languageCode),
        formatDms(v.lon, CoordinateAxis.longitude, languageCode),
      );
    case CoordinateFormat.ptTm06:
      final typed = v.input?.crs == PtTm06.epsg ? v.input : null;
      final (m, p) = typed != null
          ? (typed.x, typed.y)
          : switch (PtTm06.fromLatLon(v.lat, v.lon)) {
              (:final m, :final p) => (m, p),
            };
      return (
        'M ${formatMetres(m, languageCode)}',
        'P ${formatMetres(p, languageCode)}',
      );
  }
}

/// The label shown for a vertex: its own label, or `V1`, `V2`… by position.
String vertexLabel(int index, Map<String, Object?>? info) {
  final label = info?['label'];
  return label is String && label.trim().isNotEmpty ? label : 'V${index + 1}';
}
