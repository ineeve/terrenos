/// Web Mercator (EPSG:3857) tile maths for offline areas (SPEC.md §6.1,
/// ADR 0004).
library;

import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:meta/meta.dart';

/// Mean Earth radius (IUGG), as used for spherical areas.
const _earthRadiusMetres = 6371008.8;

/// The area of a latitude/longitude rectangle on the sphere. Accurate to
/// about 0.3 % for the small rectangles framed for offline use.
double rectangleAreaSquareMetres(LatLngBounds bounds) =>
    _earthRadiusMetres *
    _earthRadiusMetres *
    _rad(bounds.east - bounds.west).abs() *
    (sin(_rad(bounds.north)) - sin(_rad(bounds.south))).abs();

/// The columns and rows of tiles that cover a rectangle at one zoom level,
/// inclusive at both ends.
@immutable
class TileRange {
  const new({
    required this.z,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  factory covering(LatLngBounds bounds, int z) {
    final last = (1 << z) - 1;
    int column(double lon) =>
        ((lon + 180) / 360 * (1 << z)).floor().clamp(0, last);
    int row(double lat) {
      final phi = _rad(lat.clamp(-85.05112878, 85.05112878));
      final y = (1 - log(tan(phi) + 1 / cos(phi)) / pi) / 2 * (1 << z);
      return y.floor().clamp(0, last);
    }

    return TileRange(
      z: z,
      minX: column(bounds.west),
      maxX: column(bounds.east),
      minY: row(bounds.north),
      maxY: row(bounds.south),
    );
  }

  final int z;
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  int get count => (maxX - minX + 1) * (maxY - minY + 1);

  bool contains(TileCoordinates tile) =>
      tile.z == z &&
      tile.x >= minX &&
      tile.x <= maxX &&
      tile.y >= minY &&
      tile.y <= maxY;

  Iterable<TileCoordinates> get tiles sync* {
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        yield TileCoordinates(x, y, z);
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TileRange &&
      other.z == z &&
      other.minX == minX &&
      other.maxX == maxX &&
      other.minY == minY &&
      other.maxY == maxY;

  @override
  int get hashCode => Object.hash(z, minX, maxX, minY, maxY);
}

/// Typical size of one 256 px JPEG tile at zoom [z], measured in spike S1
/// (ADR 0004): ≈ 10 KB at z19 and ≈ 20 KB at z17 and below. The z18 value is
/// in between; it wasn't measured.
int estimatedTileBytes(int z) => switch (z) {
  >= 19 => 10 * 1024,
  18 => 15 * 1024,
  _ => 20 * 1024,
};

double _rad(double degrees) => degrees * pi / 180;
