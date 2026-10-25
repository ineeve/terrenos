import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/core/map/tile_math.dart';

void main() {
  group('rectangleAreaSquareMetres', () {
    test('1° × 1° at the equator', () {
      final bounds = LatLngBounds(const LatLng(0, 0), const LatLng(1, 1));
      expect(rectangleAreaSquareMetres(bounds), closeTo(12363718145, 1));
    });

    test('a 2 km square near Coimbra is about 4 km²', () {
      // 2 km is 0.017986° of latitude and 0.023532° of longitude at 40.2° N.
      final bounds = LatLngBounds(
        const LatLng(40.2, -8.43),
        const LatLng(40.217986, -8.406468),
      );
      expect(rectangleAreaSquareMetres(bounds), closeTo(4e6, 4e6 * 0.005));
    });
  });

  group('TileRange', () {
    test('finds the tile containing a point', () {
      const lisbon = LatLng(38.7223, -9.1393);
      final range = TileRange.covering(LatLngBounds(lisbon, lisbon), 19);
      expect(range.count, 1);
      expect(range.tiles.single, const TileCoordinates(248833, 200891, 19));
    });

    test('matches flutter_map’s Web Mercator projection', () {
      const crs = Epsg3857();
      for (final point in const [
        LatLng(41.1579, -8.6291),
        LatLng(37.0194, -7.9304),
        LatLng(42.15, -6.19),
      ]) {
        for (final z in [10, 15, 17, 19]) {
          final pixel = crs.latLngToOffset(point, z.toDouble());
          final tile = TileRange.covering(
            LatLngBounds(point, point),
            z,
          ).tiles.single;
          expect(tile.x, (pixel.dx / 256).floor(), reason: '$point z$z');
          expect(tile.y, (pixel.dy / 256).floor(), reason: '$point z$z');
        }
      }
    });

    test('counts, lists and contains the tiles of a rectangle', () {
      final range = TileRange.covering(
        LatLngBounds(const LatLng(40.2, -8.43), const LatLng(40.21, -8.41)),
        17,
      );
      // 0.02° × 0.01° is about 1.7 km × 1.1 km; a z17 tile is about 230 m.
      expect(range.maxX - range.minX + 1, inInclusiveRange(7, 9));
      expect(range.maxY - range.minY + 1, inInclusiveRange(4, 6));
      expect(range.tiles.toSet(), hasLength(range.count));
      expect(range.tiles.every(range.contains), isTrue);
      expect(
        range.contains(TileCoordinates(range.maxX + 1, range.minY, 17)),
        isFalse,
      );
      expect(
        range.contains(TileCoordinates(range.minX, range.minY, 16)),
        isFalse,
      );
      expect(
        range,
        TileRange.covering(
          LatLngBounds(const LatLng(40.21, -8.41), const LatLng(40.2, -8.43)),
          17,
        ),
      );
    });

    test('stays inside the world at the edges', () {
      final range = TileRange.covering(
        LatLngBounds(const LatLng(-90, -180), const LatLng(90, 180)),
        2,
      );
      expect(range.count, 16);
    });
  });

  test('tile sizes follow the spike S1 measurements', () {
    expect(estimatedTileBytes(19), 10 * 1024);
    expect(estimatedTileBytes(18), 15 * 1024);
    expect(estimatedTileBytes(17), 20 * 1024);
    expect(estimatedTileBytes(10), 20 * 1024);
  });
}
