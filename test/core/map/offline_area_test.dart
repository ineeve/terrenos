import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/offline_area.dart';
import 'package:terrenos/core/map/tile_math.dart';

/// About 1 km × 1 km near Coimbra.
final _squareKilometre = LatLngBounds(
  const LatLng(40.2, -8.43),
  const LatLng(40.208993, -8.418234),
);

OfflineArea _area({
  OfflineDetail detail = OfflineDetail.high,
  ImagerySource source = ImagerySource.ortos2025,
}) => OfflineArea(
  id: 'a1',
  name: 'Quinta',
  source: source,
  bounds: _squareKilometre,
  detail: detail,
  downloadedAt: DateTime.utc(2026, 10, 25, 18),
  savedTiles: 12,
  savedBytes: 3456,
);

void main() {
  test('round-trips through JSON', () {
    final area = _area().copyWith(complete: true);
    expect(OfflineArea.fromJson(area.toJson()), area);
    expect(area.toJson()['source'], 'ortos2025');
    expect(area.toJson()['downloadedAt'], '2026-10-25T18:00:00.000Z');
  });

  test('rejects an unknown imagery source', () {
    final json = _area().toJson()..['source'] = 'ortos1995';
    expect(() => OfflineArea.fromJson(json), throwsFormatException);
  });

  test('1 km² up to z19 is about 400 tiles and 5 MB (ADR 0004)', () {
    final estimate = OfflineArea.estimate(_squareKilometre, OfflineDetail.high);
    expect(estimate.tiles, inInclusiveRange(380, 500));
    expect(estimate.bytes / 1e6, inInclusiveRange(4, 7));
    expect(_area().tileCount, estimate.tiles);
    expect(_area().tiles.toSet(), hasLength(estimate.tiles));
  });

  test('normal detail stops at z17', () {
    final area = _area(detail: OfflineDetail.normal);
    expect(area.maxZoom, 17);
    expect(area.ranges.first.z, OfflineArea.minZoom);
    expect(area.ranges.last.z, 17);
    expect(
      OfflineArea.estimate(_squareKilometre, OfflineDetail.normal).tiles,
      lessThan(80),
    );
  });

  test('covers only its own source and zoom levels', () {
    final area = _area(detail: OfflineDetail.normal);
    final inside = TileRange.covering(_squareKilometre, 17).tiles.first;
    expect(area.covers(ImagerySource.ortos2025, inside), isTrue);
    expect(area.covers(ImagerySource.ortos2018, inside), isFalse);
    final deeper = TileRange.covering(_squareKilometre, 18).tiles.first;
    expect(area.covers(ImagerySource.ortos2025, deeper), isFalse);
    expect(
      area.covers(
        ImagerySource.ortos2025,
        TileCoordinates(inside.x + 50, inside.y, 17),
      ),
      isFalse,
    );
  });

  test('the size limit is 4 km²', () {
    expect(OfflineArea.maxAreaSquareMetres, 4e6);
  });
}
