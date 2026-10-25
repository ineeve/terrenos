import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/map/browse_cache.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/offline_area.dart';
import 'package:terrenos/core/map/tile_store.dart';
import 'package:terrenos/features/offline_areas/offline_areas_controller.dart';

final _west = LatLngBounds(
  const LatLng(40.2, -8.43),
  const LatLng(40.2027, -8.4265),
);

/// Overlaps the east half of [_west].
final _east = LatLngBounds(
  const LatLng(40.2, -8.4282),
  const LatLng(40.2027, -8.4247),
);

void main() {
  late MemoryTileStore storage;
  late MemoryBrowseCache browsing;
  late ProviderContainer container;
  late Future<Uint8List> Function(Uri) fetch;
  late int fetches;

  setUp(() {
    storage = MemoryTileStore();
    browsing = MemoryBrowseCache(5000);
    fetches = 0;
    fetch = (url) async {
      fetches++;
      return Uint8List(10);
    };
    container = ProviderContainer(
      overrides: [
        tileStorageProvider.overrideWithValue(storage),
        tileFetcherProvider.overrideWithValue((url) => fetch(url)),
        tileRetryWaitProvider.overrideWithValue((_) async {}),
        browseCacheProvider.overrideWithValue(browsing),
      ],
    );
    addTearDown(container.dispose);
  });

  OfflineAreasController controller() =>
      container.read(offlineAreasProvider.notifier);
  OfflineAreasState state() => container.read(offlineAreasProvider);

  /// Waits until no download is running or queued.
  Future<void> idle() async {
    while (state().activeId != null || state().queued.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<OfflineArea> add(String name, LatLngBounds bounds) => controller().add(
    name: name,
    source: ImagerySource.ortos2025,
    bounds: bounds,
    detail: OfflineDetail.high,
  );

  test('adding an area downloads it and saves the result', () async {
    final area = await add('  Quinta  ', _west);
    expect(state().isBusy(area.id), isTrue);
    await idle();

    final saved = state().areas.single;
    expect(saved.name, 'Quinta');
    expect(saved.complete, isTrue);
    expect(saved.savedTiles, area.tileCount);
    expect(saved.savedBytes, area.tileCount * 10);
    expect(storage.loadAreas(), [saved]);
    expect(storage.tiles, hasLength(area.tileCount));
  });

  test('downloads run one after another', () async {
    final a = await add('A', _west);
    final b = await add('B', _east);
    expect(state().activeId, a.id);
    expect(state().queued, [b.id]);
    await idle();
    expect(state().areas.every((x) => x.complete), isTrue);
    // Newest first.
    expect(state().areas.map((x) => x.name), ['B', 'A']);
  });

  test('a failed download can be resumed without refetching', () async {
    var calls = 0;
    fetch = (url) async {
      calls++;
      if (calls > 15) throw const SocketException('offline');
      return Uint8List(10);
    };
    final area = await add('A', _west);
    await idle();
    expect(state().areas.single.complete, isFalse);
    expect(state().areas.single.savedTiles, inInclusiveRange(1, 15));
    final saved = storage.tiles.length;

    fetch = (url) async {
      fetches++;
      return Uint8List(10);
    };
    controller().resume(area.id);
    await idle();
    expect(state().areas.single.complete, isTrue);
    expect(fetches, area.tileCount - saved);
  });

  test('refresh downloads every tile again', () async {
    final area = await add('A', _west);
    await idle();
    fetches = 0;
    controller().refresh(area.id);
    await idle();
    expect(fetches, area.tileCount);
  });

  test('deleting keeps tiles another area still needs', () async {
    final west = await add('W', _west);
    final east = await add('E', _east);
    await idle();
    final shared = west.tiles
        .where((t) => east.covers(ImagerySource.ortos2025, t))
        .toList();
    expect(shared, isNotEmpty);

    await controller().delete(west.id);
    expect(state().areas.map((a) => a.id), [east.id]);
    expect(storage.tiles, hasLength(east.tileCount));
    for (final t in shared) {
      expect(storage.sizeOf(ImagerySource.ortos2025, t), isNotNull);
    }
  });

  test('deleting an area while it downloads stops it', () async {
    final gate = Completer<void>();
    fetch = (url) async {
      await gate.future;
      return Uint8List(10);
    };
    final area = await add('A', _west);
    await Future<void>.delayed(Duration.zero);
    final deleting = controller().delete(area.id);
    gate.complete();
    await deleting;
    await idle();
    expect(state().areas, isEmpty);
    expect(storage.loadAreas(), isEmpty);
    expect(storage.tiles, isEmpty);
  });

  test('stop cancels queued and running downloads', () async {
    final gate = Completer<void>();
    fetch = (url) async {
      await gate.future;
      return Uint8List(10);
    };
    final a = await add('A', _west);
    final b = await add('B', _east);
    controller()
      ..cancel(b.id)
      ..cancel(a.id);
    expect(state().queued, isEmpty);
    gate.complete();
    await idle();
    expect(state().areas.every((x) => !x.complete), isTrue);
  });

  test('delete all clears every area and tile', () async {
    await add('A', _west);
    await add('B', _east);
    await controller().deleteAll();
    await idle();
    expect(state().areas, isEmpty);
    expect(storage.tiles, isEmpty);
    expect(storage.loadAreas(), isEmpty);
  });

  test('delete all during a download leaves nothing on disk', () async {
    final root = Directory.systemTemp.createTempSync('terrenos_offline_');
    addTearDown(() => root.deleteSync(recursive: true));
    final files = FileTileStore(Directory('${root.path}/tiles'));
    final gate = Completer<void>();
    final disk = ProviderContainer(
      overrides: [
        tileStorageProvider.overrideWithValue(files),
        tileRetryWaitProvider.overrideWithValue((_) async {}),
        tileFetcherProvider.overrideWithValue((url) async {
          await gate.future;
          return Uint8List(10);
        }),
        browseCacheProvider.overrideWithValue(browsing),
      ],
    );
    addTearDown(disk.dispose);
    final controller = disk.read(offlineAreasProvider.notifier);
    await controller.add(
      name: 'A',
      source: ImagerySource.ortos2025,
      bounds: _west,
      detail: OfflineDetail.high,
    );
    await Future<void>.delayed(Duration.zero);

    final clearing = controller.deleteAll();
    gate.complete();
    await clearing;
    expect(disk.read(offlineAreasProvider).areas, isEmpty);
    expect(files.loadAreas(), isEmpty);
    expect(await files.totalBytes(), 0);
  });

  test('reports storage use', () async {
    await add('A', _west);
    await idle();
    final usage = await container.read(offlineStorageUsageProvider.future);
    expect(usage.areas, storage.tiles.length * 10);
    expect(usage.browsing, 5000);
  });

  test('areas saved by an earlier session are listed newest first', () async {
    final older = OfflineArea(
      id: 'old',
      name: 'Old',
      source: ImagerySource.ortos2018,
      bounds: _west,
      detail: OfflineDetail.normal,
      downloadedAt: DateTime.utc(2026),
    );
    final newer = older.copyWith(downloadedAt: DateTime.utc(2026, 6));
    await storage.saveAreas([
      older,
      OfflineArea.fromJson(newer.toJson()..['id'] = 'new'),
    ]);
    expect(state().areas.map((a) => a.id), ['new', 'old']);
  });
}
