import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/offline_area.dart';
import 'package:terrenos/core/map/tile_store.dart';

const ImagerySource _source = ImagerySource.ortos2025;
const TileCoordinates _tile = TileCoordinates(248833, 200891, 19);

OfflineArea _area(String id) => OfflineArea(
  id: id,
  name: 'Area $id',
  source: _source,
  bounds: LatLngBounds(const LatLng(40.2, -8.43), const LatLng(40.21, -8.42)),
  detail: OfflineDetail.normal,
  downloadedAt: DateTime.utc(2026, 10, 25),
);

void main() {
  late Directory root;
  late FileTileStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('terrenos_tiles_');
    store = FileTileStore(Directory(p.join(root.path, 'tiles')));
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('FileTileStore', () {
    test('stores tiles as <source>/<z>/<x>/<y>.jpg', () async {
      expect(store.image(_source, _tile), isNull);
      expect(store.sizeOf(_source, _tile), isNull);

      await store.write(_source, _tile, Uint8List(42));
      final file = File(
        p.join(root.path, 'tiles', 'ortos2025', '19', '248833', '200891.jpg'),
      );
      expect(file.lengthSync(), 42);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      expect(store.sizeOf(_source, _tile), 42);
      expect((store.image(_source, _tile)! as FileImage).file.path, file.path);
      expect(store.image(ImagerySource.ortos2018, _tile), isNull);
    });

    test('delete removes tiles and the directories left empty', () async {
      const neighbour = TileCoordinates(248833, 200892, 19);
      const elsewhere = TileCoordinates(248900, 200892, 19);
      for (final t in [_tile, neighbour, elsewhere]) {
        await store.write(_source, t, Uint8List(10));
      }
      await store.delete(_source, [_tile, neighbour]);
      expect(store.sizeOf(_source, _tile), isNull);
      expect(store.sizeOf(_source, neighbour), isNull);
      expect(store.sizeOf(_source, elsewhere), 10);
      expect(
        Directory(p.join(store.directory.path, 'ortos2025', '19', '248833'))
            .existsSync(),
        isFalse,
      );
      // Deleting tiles that aren't there is fine.
      await store.delete(_source, [_tile]);
    });

    test('totalBytes counts tiles and the area list; clear empties', () async {
      expect(await store.totalBytes(), 0);
      await store.clear();
      await store.write(_source, _tile, Uint8List(1000));
      expect(await store.totalBytes(), 1000);
      await store.saveAreas([_area('a')]);
      expect(await store.totalBytes(), greaterThan(1000));

      await store.clear();
      expect(await store.totalBytes(), 0);
      expect(store.loadAreas(), isEmpty);
      expect(store.directory.existsSync(), isTrue);
    });

    test('saves and loads the area list', () async {
      expect(store.loadAreas(), isEmpty);
      final areas = [_area('a'), _area('b').copyWith(complete: true)];
      await store.saveAreas(areas);
      expect(store.loadAreas(), areas);
    });

    test('skips unreadable areas but keeps the others', () async {
      await store.saveAreas([_area('a')]);
      final file = File(p.join(store.directory.path, 'areas.json'));
      final saved = file.readAsStringSync();
      file.writeAsStringSync(
        saved.replaceFirst('"areas":[', '"areas":[{"id":"x"},'),
      );
      expect(store.loadAreas().map((a) => a.id), ['a']);
    });
  });

  group('MemoryTileStore', () {
    test('behaves like the file store', () async {
      final memory = MemoryTileStore();
      expect(memory.image(_source, _tile), isNull);
      await memory.write(_source, _tile, Uint8List(7));
      expect(memory.sizeOf(_source, _tile), 7);
      expect(memory.image(_source, _tile), isA<MemoryImage>());
      expect(await memory.totalBytes(), 7);
      await memory.saveAreas([_area('a')]);
      expect(memory.loadAreas(), [_area('a')]);
      await memory.delete(_source, [_tile]);
      expect(memory.sizeOf(_source, _tile), isNull);
      await memory.write(_source, _tile, Uint8List(7));
      await memory.clear();
      expect(memory.tiles, isEmpty);
      expect(memory.loadAreas(), isEmpty);
    });
  });
}
