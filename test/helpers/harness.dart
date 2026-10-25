import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/app/app.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/device/device_identity.dart';
import 'package:terrenos/core/map/browse_cache.dart';
import 'package:terrenos/core/map/tile_downloader.dart';
import 'package:terrenos/core/map/tile_store.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/core/storage/app_directories.dart';
import 'package:terrenos/core/storage/document_store.dart';
import 'package:terrenos/features/map/map_page.dart';

import 'fake_location.dart';
import 'fake_tiles.dart';

/// Runs the whole app with in-memory storage and fake map tiles.
class Harness {
  new({AppSettings settings = const AppSettings(), this.caop})
    : settings = MemorySettingsRepository(settings),
      device = MemoryDeviceRepository();

  /// CAOP boundaries for the map; none unless a test needs them, so tests
  /// don't parse the 2.5 MB asset.
  final AdminBoundaries? caop;
  final location = FakeLocationSource();

  final MemorySettingsRepository settings;
  final MemoryDeviceRepository device;
  final tiles = FakeTileProvider();
  final properties = MemoryDocumentStorage<PropertyDocument>((d) => d.id);
  final offlineTiles = MemoryTileStore();
  final browseCache = MemoryBrowseCache();

  /// Serves a small fake JPEG for every URL and records the requests.
  final fetchedUrls = <Uri>[];
  late TileFetcher fetch = (url) async {
    fetchedUrls.add(url);
    return Uint8List(100);
  };

  Future<void> pump(WidgetTester tester, {Locale phone = const Locale('en')}) {
    tester.platformDispatcher.localeTestValue = phone;
    tester.platformDispatcher.localesTestValue = [phone];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDirectoriesProvider.overrideWithValue(
            AppDirectories(Directory('/nonexistent')),
          ),
          settingsRepositoryProvider.overrideWithValue(settings),
          deviceRepositoryProvider.overrideWithValue(device),
          imageryTileProviderProvider.overrideWithValue(tiles),
          propertyStorageProvider.overrideWithValue(properties),
          tileStorageProvider.overrideWithValue(offlineTiles),
          tileFetcherProvider.overrideWithValue((url) => fetch(url)),
          browseCacheProvider.overrideWithValue(browseCache),
          locationSourceProvider.overrideWithValue(location),
          adminBoundariesProvider.overrideWithValue(
            AsyncData(caop ?? _noBoundaries),
          ),
        ],
        child: const TerrenosApp(),
      ),
    );
  }
}

const onboarded = AppSettings(onboardingComplete: true);

final _noBoundaries = AdminBoundaries(
  edition: caopEdition,
  distritos: const {},
  concelhos: const {},
  freguesias: const [],
  levels: const [],
  arcs: const [],
);
