import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/offline_area.dart';
import 'package:terrenos/core/map/tile_downloader.dart';
import 'package:terrenos/core/map/tile_store.dart';

/// About 300 m × 300 m: around 50 tiles up to z19.
final _area = OfflineArea(
  id: 'a',
  name: 'Quinta',
  source: ImagerySource.ortos2025,
  bounds: LatLngBounds(
    const LatLng(40.2, -8.43),
    const LatLng(40.2027, -8.4265),
  ),
  detail: OfflineDetail.high,
  downloadedAt: DateTime.utc(2026, 10, 25),
);

void main() {
  late MemoryTileStore storage;
  late List<Uri> fetched;
  late List<Duration> slept;

  setUp(() {
    storage = MemoryTileStore();
    fetched = [];
    slept = [];
  });

  TileDownloader downloader(TileFetcher fetch, {int maxAttempts = 5}) =>
      TileDownloader(
        fetch: fetch,
        storage: storage,
        maxAttempts: maxAttempts,
        sleep: (d) async => slept.add(d),
      );

  Future<Uint8List> ok(Uri url) async {
    fetched.add(url);
    return Uint8List(100);
  }

  test('saves every tile with the URL the map would request', () async {
    final progress = <DownloadProgress>[];
    final outcome = await downloader(ok)
        .download(_area, onProgress: progress.add);

    expect(outcome, DownloadOutcome.complete);
    expect(fetched, hasLength(_area.tileCount));
    expect(storage.tiles, hasLength(_area.tileCount));
    expect(progress.last.saved, _area.tileCount);
    expect(progress.last.bytes, _area.tileCount * 100);
    expect(progress.last.fraction, 1);

    final options = ImagerySource.ortos2025.wmsOptions;
    final expected = {
      for (final t in _area.tiles) options.getUrl(t, 256, false),
    };
    expect(fetched.map((u) => u.toString()).toSet(), expected);
    expect(fetched.first.toString(), contains('Ortos2025-RGB'));
    expect(fetched.first.toString(), contains('GetMap'));
  });

  test('never has more than 8 requests in flight', () async {
    var inFlight = 0;
    var most = 0;
    Future<Uint8List> slow(Uri url) async {
      inFlight++;
      most = inFlight > most ? inFlight : most;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      inFlight--;
      return Uint8List(1);
    }

    await downloader(slow).download(_area);
    expect(most, TileDownloader.maxParallel);
    expect(TileDownloader.maxParallel, 8);
  });

  test('resumes: tiles already saved are not fetched again', () async {
    final half = _area.tiles.take(_area.tileCount ~/ 2).toList();
    for (final tile in half) {
      await storage.write(_area.source, tile, Uint8List(50));
    }
    final progress = <DownloadProgress>[];
    await downloader(ok).download(_area, onProgress: progress.add);

    expect(fetched, hasLength(_area.tileCount - half.length));
    expect(progress.last.saved, _area.tileCount);
    expect(
      progress.last.bytes,
      half.length * 50 + (_area.tileCount - half.length) * 100,
    );
  });

  test('refresh fetches every tile again', () async {
    for (final tile in _area.tiles) {
      await storage.write(_area.source, tile, Uint8List(50));
    }
    await downloader(ok).download(_area, refresh: true);
    expect(fetched, hasLength(_area.tileCount));
    expect(storage.tiles.values.every((t) => t.length == 100), isTrue);
  });

  test('retries a failing tile with exponential backoff', () async {
    // One worker: with eight, each would back off from its own failure.
    var failures = 0;
    Future<Uint8List> flaky(Uri url) async {
      if (failures < 3) {
        failures++;
        throw const SocketException('offline');
      }
      return await ok(url);
    }

    final outcome = await TileDownloader(
      fetch: flaky,
      storage: storage,
      parallel: 1,
      sleep: (d) async => slept.add(d),
    ).download(_area);
    expect(outcome, DownloadOutcome.complete);
    expect(slept, const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ]);
  });

  test('backoff is capped at 30 seconds', () {
    expect(TileDownloader.backoff(1), const Duration(seconds: 1));
    expect(TileDownloader.backoff(5), const Duration(seconds: 16));
    expect(TileDownloader.backoff(6), const Duration(seconds: 30));
    expect(TileDownloader.backoff(20), const Duration(seconds: 30));
  });

  test('stops when a tile keeps failing, keeping what was saved', () async {
    var calls = 0;
    Future<Uint8List> dies(Uri url) async {
      calls++;
      if (calls > 20) throw const SocketException('offline');
      return Uint8List(1);
    }

    final outcome = await downloader(dies, maxAttempts: 3).download(_area);
    expect(outcome, DownloadOutcome.failed);
    expect(storage.tiles.length, inInclusiveRange(1, 20));
    // It gives up instead of trying every remaining tile.
    expect(calls, lessThan(20 + 8 * 3 + 1));
  });

  test('can be cancelled', () async {
    var cancelled = false;
    final outcome = await downloader(ok).download(
      _area,
      isCancelled: () => cancelled,
      onProgress: (p) => cancelled = p.saved >= 10,
    );
    expect(outcome, DownloadOutcome.cancelled);
    expect(storage.tiles.length, lessThan(_area.tileCount));
  });

  group('HttpTileFetcher', () {
    late HttpServer server;
    late HttpTileFetcher fetcher;
    late List<String?> agents;

    setUp(() async {
      agents = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..listen((request) {
          agents.add(request.headers.value(HttpHeaders.userAgentHeader));
          final response = request.response;
          switch (request.uri.path) {
            case '/tile':
              response.headers.contentType = ContentType('image', 'jpeg');
              response.add(List.filled(64, 1));
            case '/error':
              // How a WMS server reports a bad request.
              response.headers.contentType = ContentType('text', 'xml');
              response.write('<ServiceExceptionReport/>');
            default:
              response.statusCode = HttpStatus.internalServerError;
          }
          unawaited(response.close());
        });
      fetcher = HttpTileFetcher();
    });

    tearDown(() async {
      fetcher.close();
      await server.close(force: true);
    });

    Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test('returns the image bytes and identifies the app', () async {
      expect(await fetcher(url('/tile')), hasLength(64));
      expect(agents.single, imageryUserAgent);
    });

    test('rejects WMS errors and HTTP errors', () async {
      await expectLater(
        fetcher(url('/error')),
        throwsA(isA<TileFetchException>()),
      );
      await expectLater(
        fetcher(url('/broken')),
        throwsA(
          isA<TileFetchException>().having(
            (e) => e.toString(),
            'message',
            contains('HTTP 500'),
          ),
        ),
      );
    });
  });
}
