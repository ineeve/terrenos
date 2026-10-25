/// Offline map tiles (SPEC.md §5, §8.1).
///
/// Tiles are plain files, `tiles/<source>/<z>/<x>/<y>.jpg`, and the list of
/// offline areas is `tiles/areas.json`. There is no database (D2).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path/path.dart' as p;
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/offline_area.dart';
import 'package:terrenos/core/storage/atomic_file.dart';

/// Where offline tiles are kept. [FileTileStore] writes files; tests use
/// [MemoryTileStore].
abstract interface class TileStorage {
  /// The stored image for a tile, or `null` if it wasn't downloaded.
  ImageProvider? image(ImagerySource source, TileCoordinates tile);

  /// Size of a stored tile in bytes, or `null` if it wasn't downloaded.
  int? sizeOf(ImagerySource source, TileCoordinates tile);

  Future<void> write(
    ImagerySource source,
    TileCoordinates tile,
    Uint8List bytes,
  );

  Future<void> delete(ImagerySource source, Iterable<TileCoordinates> tiles);

  /// Space used by all tiles and the area list.
  Future<int> totalBytes();

  /// Deletes every tile and area.
  Future<void> clear();

  List<OfflineArea> loadAreas();
  Future<void> saveAreas(List<OfflineArea> areas);
}

class FileTileStore implements TileStorage {
  new(this.directory)
    : _areas = AtomicFile(p.join(directory.path, 'areas.json'));

  final Directory directory;
  final AtomicFile _areas;

  File _file(ImagerySource source, TileCoordinates tile) => File(
    p.join(
      directory.path,
      source.name,
      '${tile.z}',
      '${tile.x}',
      '${tile.y}.jpg',
    ),
  );

  @override
  ImageProvider? image(ImagerySource source, TileCoordinates tile) {
    final file = _file(source, tile);
    return file.existsSync() ? FileImage(file) : null;
  }

  @override
  int? sizeOf(ImagerySource source, TileCoordinates tile) {
    final stat = _file(source, tile).statSync();
    return stat.type == FileSystemEntityType.file ? stat.size : null;
  }

  /// Writes to a temporary file first, so a download stopped half-way never
  /// leaves a truncated tile for the map to show.
  @override
  Future<void> write(
    ImagerySource source,
    TileCoordinates tile,
    Uint8List bytes,
  ) async {
    final file = _file(source, tile);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> delete(
    ImagerySource source,
    Iterable<TileCoordinates> tiles,
  ) async {
    final columns = <String>{};
    for (final tile in tiles) {
      final file = _file(source, tile);
      if (file.existsSync()) await file.delete();
      columns.add(file.parent.path);
    }
    // Remove directories left empty, deepest first.
    for (final column in columns) {
      for (final dir in [Directory(column), Directory(column).parent]) {
        try {
          await dir.delete();
        } on FileSystemException {
          // Not empty (or already gone).
        }
      }
    }
  }

  @override
  Future<int> totalBytes() async {
    if (!directory.existsSync()) return 0;
    var total = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  @override
  Future<void> clear() async {
    if (!directory.existsSync()) return;
    await for (final entity in directory.list()) {
      await entity.delete(recursive: true);
    }
  }

  /// Unreadable entries are skipped: the tiles stay usable on the map even
  /// if their area can't be listed.
  @override
  List<OfflineArea> loadAreas() {
    final result = _areas.read((text) {
      final json = jsonDecode(text) as Map<String, Object?>;
      return json['areas']! as List<Object?>;
    });
    if (result == null) return [];
    return [for (final entry in result.value) ?_tryParse(entry)];
  }

  @override
  Future<void> saveAreas(List<OfflineArea> areas) async {
    await directory.create(recursive: true);
    await _areas.write(
      jsonEncode({
        'schema': 1,
        'areas': [for (final area in areas) area.toJson()],
      }),
    );
  }

  static OfflineArea? _tryParse(Object? json) {
    try {
      return OfflineArea.fromJson(json! as Map<String, Object?>);
    } on Object {
      return null;
    }
  }
}

class MemoryTileStore implements TileStorage {
  final tiles = <String, Uint8List>{};
  final areas = <OfflineArea>[];

  static String _key(ImagerySource source, TileCoordinates tile) =>
      '${source.name}/${tile.z}/${tile.x}/${tile.y}';

  @override
  ImageProvider? image(ImagerySource source, TileCoordinates tile) {
    final bytes = tiles[_key(source, tile)];
    return bytes == null ? null : MemoryImage(bytes);
  }

  @override
  int? sizeOf(ImagerySource source, TileCoordinates tile) =>
      tiles[_key(source, tile)]?.length;

  @override
  Future<void> write(
    ImagerySource source,
    TileCoordinates tile,
    Uint8List bytes,
  ) async => tiles[_key(source, tile)] = bytes;

  @override
  Future<void> delete(
    ImagerySource source,
    Iterable<TileCoordinates> tiles,
  ) async {
    for (final tile in tiles) {
      this.tiles.remove(_key(source, tile));
    }
  }

  @override
  Future<int> totalBytes() async =>
      tiles.values.fold<int>(0, (sum, t) => sum + t.length);

  @override
  Future<void> clear() async {
    tiles.clear();
    areas.clear();
  }

  @override
  List<OfflineArea> loadAreas() => List.of(areas);

  @override
  Future<void> saveAreas(List<OfflineArea> areas) async {
    this.areas
      ..clear()
      ..addAll(areas);
  }
}
