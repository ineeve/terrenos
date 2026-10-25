/// Tiles kept while browsing the map online (SPEC.md SET-8).
///
/// flutter_map caches every tile it fetches, up to 1 GB, in the app's cache
/// directory (`fm_cache`). Android may clear it at any time, so it isn't
/// counted on for offline use; offline areas are kept in `TileStorage`.
library;

import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class BrowseCache {
  Future<int> totalBytes();
  Future<void> clear();
}

class FlutterMapBrowseCache implements BrowseCache {
  Future<Directory> get _directory async => Directory(
    p.join((await getApplicationCacheDirectory()).path, 'fm_cache'),
  );

  @override
  Future<int> totalBytes() async {
    final dir = await _directory;
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Stops the cache before deleting its files. The cache's own
  /// `deleteCache` option is not used: it fails if called before the cache
  /// has finished starting.
  @override
  Future<void> clear() async {
    await BuiltInMapCachingProvider.getOrCreateInstance().destroy();
    final dir = await _directory;
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

class MemoryBrowseCache implements BrowseCache {
  new([this.bytes = 0]);

  int bytes;

  @override
  Future<int> totalBytes() async => bytes;

  @override
  Future<void> clear() async => bytes = 0;
}
