/// A rectangle of imagery downloaded for offline use (MAP-7, MAP-8).
library;

import 'package:flutter_map/flutter_map.dart';
import 'package:meta/meta.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/tile_math.dart';

/// How far in the download goes (MAP-7).
enum OfflineDetail {
  /// Up to z17, about 1.2 m per pixel: enough to find the parcel.
  normal(maxZoom: 17),

  /// Up to z19, the full 25 cm resolution of the imagery.
  high(maxZoom: ImagerySource.maxNativeZoom);

  new({required this.maxZoom});

  final int maxZoom;
}

@immutable
class OfflineArea {
  const new({
    required this.id,
    required this.name,
    required this.source,
    required this.bounds,
    required this.detail,
    required this.downloadedAt,
    this.savedTiles = 0,
    this.savedBytes = 0,
    this.complete = false,
  });

  factory fromJson(Map<String, Object?> json) {
    final source = ImagerySource.byName(json['source']);
    final detail = OfflineDetail.values
        .where((d) => d.name == json['detail'])
        .firstOrNull;
    if (source == null || detail == null) {
      throw FormatException('Unknown imagery or detail in offline area', json);
    }
    double number(String key) => (json[key]! as num).toDouble();
    return OfflineArea(
      id: json['id']! as String,
      name: json['name']! as String,
      source: source,
      bounds: LatLngBounds.unsafe(
        north: number('north'),
        south: number('south'),
        east: number('east'),
        west: number('west'),
      ),
      detail: detail,
      downloadedAt: DateTime.parse(json['downloadedAt']! as String),
      savedTiles: json['savedTiles']! as int,
      savedBytes: json['savedBytes']! as int,
      complete: json['complete'] == true,
    );
  }

  /// Largest area that can be downloaded at once (ADR 0006).
  static const maxAreaSquareMetres = 4e6;

  /// Below z10 the area is only a few pixels wide on screen.
  static const minZoom = 10;

  final String id;
  final String name;
  final ImagerySource source;
  final LatLngBounds bounds;
  final OfflineDetail detail;

  /// When the last download or refresh of this area started.
  final DateTime downloadedAt;

  /// Tiles on disk so far, and their total size.
  final int savedTiles;
  final int savedBytes;

  /// Every tile was saved. Incomplete areas can be resumed.
  final bool complete;

  int get maxZoom => detail.maxZoom;

  List<TileRange> get ranges => tileRanges(bounds, maxZoom);

  int get tileCount => ranges.fold(0, (sum, r) => sum + r.count);

  Iterable<TileCoordinates> get tiles => ranges.expand((r) => r.tiles);

  bool covers(ImagerySource source, TileCoordinates tile) =>
      source == this.source &&
      tile.z >= minZoom &&
      tile.z <= maxZoom &&
      TileRange.covering(bounds, tile.z).contains(tile);

  /// The tile ranges from [minZoom] to [maxZoom] that cover [bounds].
  static List<TileRange> tileRanges(LatLngBounds bounds, int maxZoom) => [
    for (var z = minZoom; z <= maxZoom; z++) TileRange.covering(bounds, z),
  ];

  /// Tile count and expected size of a download, shown before it starts.
  static ({int tiles, int bytes}) estimate(
    LatLngBounds bounds,
    OfflineDetail detail,
  ) {
    var tiles = 0;
    var bytes = 0;
    for (final range in tileRanges(bounds, detail.maxZoom)) {
      tiles += range.count;
      bytes += range.count * estimatedTileBytes(range.z);
    }
    return (tiles: tiles, bytes: bytes);
  }

  OfflineArea copyWith({
    String? name,
    DateTime? downloadedAt,
    int? savedTiles,
    int? savedBytes,
    bool? complete,
  }) => OfflineArea(
    id: id,
    name: name ?? this.name,
    source: source,
    bounds: bounds,
    detail: detail,
    downloadedAt: downloadedAt ?? this.downloadedAt,
    savedTiles: savedTiles ?? this.savedTiles,
    savedBytes: savedBytes ?? this.savedBytes,
    complete: complete ?? this.complete,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'source': source.name,
    'north': bounds.north,
    'south': bounds.south,
    'east': bounds.east,
    'west': bounds.west,
    'detail': detail.name,
    'downloadedAt': downloadedAt.toUtc().toIso8601String(),
    'savedTiles': savedTiles,
    'savedBytes': savedBytes,
    'complete': complete,
  };

  @override
  bool operator ==(Object other) =>
      other is OfflineArea &&
      other.id == id &&
      other.name == name &&
      other.source == source &&
      other.bounds == bounds &&
      other.detail == detail &&
      other.downloadedAt == downloadedAt &&
      other.savedTiles == savedTiles &&
      other.savedBytes == savedBytes &&
      other.complete == complete;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    source,
    bounds,
    detail,
    downloadedAt,
    savedTiles,
    savedBytes,
    complete,
  );
}
