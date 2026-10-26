import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/app/app.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/device/device_identity.dart';
import 'package:terrenos/core/editing/boundary_draft.dart';
import 'package:terrenos/core/map/browse_cache.dart';
import 'package:terrenos/core/map/tile_downloader.dart';
import 'package:terrenos/core/map/tile_store.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/places/places.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/core/storage/app_directories.dart';
import 'package:terrenos/core/storage/document_store.dart';
import 'package:terrenos/features/map/map_page.dart';

import 'fake_compass.dart';
import 'fake_location.dart';
import 'fake_tiles.dart';

/// Runs the whole app with in-memory storage and fake map tiles.
class Harness {
  new({AppSettings settings = const AppSettings(), this.caop, this.places})
    : settings = MemorySettingsRepository(settings),
      device = MemoryDeviceRepository();

  /// CAOP boundaries for the map; none unless a test needs them, so tests
  /// don't parse the 2.5 MB asset.
  final AdminBoundaries? caop;

  /// Place names for the map and search; none unless a test needs them.
  final Places? places;
  final location = FakeLocationSource();
  final compass = FakeCompass();

  /// How many times the phone buzzed for reaching a vertex (VTX-10).
  int arrivalSignals = 0;

  /// Battery level in %, for the walk mode warning.
  int battery = 80;

  final MemorySettingsRepository settings;
  final MemoryDeviceRepository device;
  final tiles = FakeTileProvider();
  final properties = MemoryDocumentStorage<PropertyDocument>((d) => d.id);
  final offlineTiles = MemoryTileStore();
  final drafts = MemoryDraftStore();
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
          draftStorageProvider.overrideWithValue(drafts),
          tileFetcherProvider.overrideWithValue((url) => fetch(url)),
          tileRetryWaitProvider.overrideWithValue((_) async {}),
          browseCacheProvider.overrideWithValue(browseCache),
          locationSourceProvider.overrideWithValue(location),
          batteryLevelProvider.overrideWithValue(() async => battery),
          compassSourceProvider.overrideWithValue(compass),
          arrivalSignalProvider.overrideWithValue(() async => arrivalSignals++),
          adminBoundariesProvider.overrideWithValue(
            AsyncData(caop ?? _noBoundaries),
          ),
          placesProvider.overrideWithValue(
            AsyncData(places ?? Places(osmTimestamp: '', places: const [])),
          ),
        ],
        child: const TerrenosApp(),
      ),
    );
  }
}

const onboarded = AppSettings(onboardingComplete: true);

/// A tall phone screen, 540 × 1170 dp, for flows that need the editor's
/// list and its bottom bar on screen together. Wider than most phones
/// because the test font draws every character 14 px wide.
void usePhoneScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// Scrolls the vertex table until [label] (e.g. `V5`) is built: the table
/// only builds the rows on screen.
Future<void> scrollToVertex(WidgetTester tester, String label) =>
    tester.scrollUntilVisible(
      find.text(label),
      100,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );

final _noBoundaries = AdminBoundaries(
  edition: caopEdition,
  distritos: const {},
  concelhos: const {},
  freguesias: const [],
  levels: const [],
  arcs: const [],
);
