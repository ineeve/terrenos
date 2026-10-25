import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/app/app.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/device/device_identity.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/core/storage/app_directories.dart';
import 'package:terrenos/core/storage/document_store.dart';
import 'package:terrenos/features/map/map_page.dart';

import 'fake_tiles.dart';

/// Runs the whole app with in-memory storage and fake map tiles.
class Harness {
  new({AppSettings settings = const AppSettings()})
    : settings = MemorySettingsRepository(settings),
      device = MemoryDeviceRepository();

  final MemorySettingsRepository settings;
  final MemoryDeviceRepository device;
  final tiles = FakeTileProvider();
  final properties = MemoryDocumentStorage<PropertyDocument>((d) => d.id);

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
        ],
        child: const TerrenosApp(),
      ),
    );
  }
}

const onboarded = AppSettings(onboardingComplete: true);
