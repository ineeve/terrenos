/// Shows downloaded tiles from disk and fetches the rest from the network
/// (SPEC.md §5.1: a TileProvider that checks files first).
library;

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/tile_store.dart';

class OfflineFirstTileProvider extends NetworkTileProvider {
  new({required this.storage})
    : super(headers: {'User-Agent': imageryUserAgent});

  final TileStorage storage;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final source = ImagerySource.of(options);
    final stored = source == null ? null : storage.image(source, coordinates);
    return stored ??
        super.getImageWithCancelLoadingSupport(
          coordinates,
          options,
          cancelLoading,
        );
  }

  /// One provider is shared by every map in the app, but each [TileLayer]
  /// disposes its provider when it goes away. Ignore that, so the HTTP
  /// client stays open for the other maps; [close] releases it.
  @override
  Future<void> dispose() async {}

  Future<void> close() => super.dispose();
}
