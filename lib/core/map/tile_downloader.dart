/// Downloads offline areas (MAP-7, SPEC.md §6.1).
///
/// This is the only code that makes network requests of its own; the map
/// widget fetches the tiles it shows through flutter_map.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/offline_area.dart';
import 'package:terrenos/core/map/tile_store.dart';

/// Fetches one tile image, throwing on any failure.
typedef TileFetcher = Future<Uint8List> Function(Uri url);

@immutable
class DownloadProgress {
  const new({required this.total, required this.saved, required this.bytes});

  final int total;
  final int saved;
  final int bytes;

  double get fraction => total == 0 ? 1 : saved / total;
}

enum DownloadOutcome {
  complete,
  cancelled,

  /// A tile still failed after every retry, most likely because the
  /// connection was lost. Tiles saved so far are kept for a later resume.
  failed,
}

class TileDownloader {
  new({
    required this.fetch,
    required this.storage,
    this.parallel = maxParallel,
    this.maxAttempts = 5,
    this.sleep = _sleep,
  });

  /// At most 8 requests at a time (SPEC.md §6.1). Measured against DGT,
  /// throughput stops improving at about 8.
  static const maxParallel = 8;

  final TileFetcher fetch;
  final TileStorage storage;
  final int parallel;
  final int maxAttempts;
  final Future<void> Function(Duration) sleep;

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);

  /// Waits 1, 2, 4, 8… seconds between attempts, at most 30 s.
  static Duration backoff(int attempt) =>
      Duration(seconds: min(30, 1 << (attempt - 1)));

  /// Saves every tile of [area]. Tiles already on disk are kept unless
  /// [refresh] is set, so calling this again resumes a stopped download.
  Future<DownloadOutcome> download(
    OfflineArea area, {
    bool refresh = false,
    void Function(DownloadProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final options = area.source.wmsOptions;
    final pending = area.tiles.iterator;
    final total = area.tileCount;
    var saved = 0;
    var bytes = 0;
    var failed = false;
    bool stopped() => failed || (isCancelled?.call() ?? false);

    Future<void> worker() async {
      // Workers share one iterator; the event loop runs one at a time, so
      // each tile is taken exactly once.
      while (!stopped() && pending.moveNext()) {
        final tile = pending.current;
        var size = refresh ? null : storage.sizeOf(area.source, tile);
        if (size == null) {
          final url = Uri.parse(options.getUrl(tile, 256, false));
          final data = await _fetchWithRetry(url, stopped);
          if (data == null) {
            if (!stopped()) failed = true;
            return;
          }
          await storage.write(area.source, tile, data);
          size = data.length;
        }
        saved++;
        bytes += size;
        onProgress?.call(
          DownloadProgress(total: total, saved: saved, bytes: bytes),
        );
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
    if (failed) return DownloadOutcome.failed;
    if (saved < total) return DownloadOutcome.cancelled;
    return DownloadOutcome.complete;
  }

  Future<Uint8List?> _fetchWithRetry(Uri url, bool Function() stopped) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fetch(url);
      } on Object {
        if (attempt == maxAttempts || stopped()) return null;
        await sleep(backoff(attempt));
        if (stopped()) return null;
      }
    }
    return null;
  }
}

class TileFetchException implements Exception {
  new(this.message);

  final String message;

  @override
  String toString() => 'TileFetchException: $message';
}

/// Fetches tiles over HTTP with the app's identifying User-Agent.
class HttpTileFetcher {
  new()
    : _client = HttpClient()
        ..userAgent = imageryUserAgent
        ..connectionTimeout = const Duration(seconds: 20);

  final HttpClient _client;

  Future<Uint8List> call(Uri url) async {
    final request = await _client.getUrl(url);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = await consolidateHttpClientResponseBytes(response)
        .timeout(const Duration(seconds: 30));
    // A WMS server reports errors as XML with status 200.
    final type = response.headers.contentType?.primaryType;
    if (response.statusCode != HttpStatus.ok || type != 'image') {
      throw TileFetchException('HTTP ${response.statusCode}, $type for $url');
    }
    return bytes;
  }

  void close() => _client.close(force: true);
}
