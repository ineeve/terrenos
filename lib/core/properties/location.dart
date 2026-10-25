/// The `location` field: distrito, concelho and freguesia (PROP-9).
///
/// Filled in automatically from CAOP using the boundary's interior point,
/// and editable. Automatic values are marked so that editing the boundary
/// can refresh them without overwriting a location the user chose.
library;

import 'package:terrenos/core/caop/caop.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/geometry_history.dart';

/// The field value for [parts], or `null` if it can't be determined.
Map<String, Object?>? autoLocation(Caop? caop, BoundaryParts parts) {
  if (caop == null) return null;
  final vertexCount = parts.fold(0, (n, p) => n + p.first.length);
  if (vertexCount < 3) return null;
  final point = GeometryService.measure(parts).interiorPoint;
  final location = caop.locate(point.lat, point.lon);
  if (location == null) return null;
  return {
    'distrito': location.distrito,
    'concelho': location.concelho,
    'freguesia': location.freguesia,
    'auto': true,
  };
}

AdminLocation? readLocation(PropertyDocument doc) {
  final value = doc.field(PropertyField.location);
  if (value is! Map) return null;
  final distrito = value['distrito'];
  final concelho = value['concelho'];
  final freguesia = value['freguesia'];
  if (distrito is! String || concelho is! String || freguesia is! String) {
    return null;
  }
  return (distrito: distrito, concelho: concelho, freguesia: freguesia);
}

/// Whether the stored location was filled in automatically (or is missing),
/// so it may be recomputed when the boundary changes.
bool isAutoLocation(PropertyDocument doc) {
  final value = doc.field(PropertyField.location);
  return value is! Map || value['auto'] == true;
}

/// "Freguesia, Concelho" for display.
String formatLocation(AdminLocation l) =>
    l.freguesia == l.concelho ? l.freguesia : '${l.freguesia}, ${l.concelho}';
