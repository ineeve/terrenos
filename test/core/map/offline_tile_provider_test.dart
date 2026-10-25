import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/offline_tile_provider.dart';
import 'package:terrenos/core/map/tile_store.dart';

void main() {
  const tile = TileCoordinates(248833, 200891, 19);
  final never = Future<void>.value();

  TileLayer layer(ImagerySource source) =>
      TileLayer(wmsOptions: source.wmsOptions);

  test('shows a downloaded tile from storage', () async {
    final storage = MemoryTileStore();
    await storage.write(ImagerySource.ortos2025, tile, Uint8List(10));
    final provider = OfflineFirstTileProvider(storage: storage);

    final image = provider.getImageWithCancelLoadingSupport(
      tile,
      layer(ImagerySource.ortos2025),
      never,
    );
    expect(image, isA<MemoryImage>());
    await provider.close();
  });

  test('falls back to the network for other tiles and sources', () async {
    final storage = MemoryTileStore();
    await storage.write(ImagerySource.ortos2025, tile, Uint8List(10));
    final provider = OfflineFirstTileProvider(storage: storage);

    expect(
      provider.getImageWithCancelLoadingSupport(
        tile,
        layer(ImagerySource.ortos2018),
        never,
      ),
      isNot(isA<MemoryImage>()),
    );
    expect(
      provider.getImageWithCancelLoadingSupport(
        const TileCoordinates(1, 1, 19),
        layer(ImagerySource.ortos2025),
        never,
      ),
      isNot(isA<MemoryImage>()),
    );
    expect(provider.headers['User-Agent'], imageryUserAgent);
    await provider.close();
  });

  test('survives a map disposing it, since it is shared', () async {
    final provider = OfflineFirstTileProvider(storage: MemoryTileStore());
    await provider.dispose();
    expect(
      provider.getImageWithCancelLoadingSupport(
        tile,
        layer(ImagerySource.ortos2025),
        never,
      ),
      isNotNull,
    );
    await provider.close();
  });

  test('identifies the imagery of a tile layer', () {
    expect(
      ImagerySource.of(layer(ImagerySource.ortos2018)),
      ImagerySource.ortos2018,
    );
    expect(
      ImagerySource.of(TileLayer(urlTemplate: 'https://x/{z}/{x}/{y}')),
      isNull,
    );
    expect(ImagerySource.byName('ortos2025'), ImagerySource.ortos2025);
    expect(ImagerySource.byName('nope'), isNull);
  });
}
