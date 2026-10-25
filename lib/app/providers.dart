/// App-wide state. Repositories are provided at start-up (see bootstrap.dart)
/// through overrides.
library;

import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/device/device_identity.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/map/browse_cache.dart';
import 'package:terrenos/core/map/tile_downloader.dart';
import 'package:terrenos/core/map/tile_store.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/properties/property_repository.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/core/storage/app_directories.dart';
import 'package:terrenos/core/storage/document_store.dart';

final appDirectoriesProvider = Provider<AppDirectories>(
  (ref) => throw UnimplementedError('Overridden at start-up'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('Overridden at start-up'),
);

final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => throw UnimplementedError('Overridden at start-up'),
);

final propertyStorageProvider = Provider<DocumentStorage<PropertyDocument>>(
  (ref) => throw UnimplementedError('Overridden at start-up'),
);

final tileStorageProvider = Provider<TileStorage>(
  (ref) => throw UnimplementedError('Overridden at start-up'),
);

/// The only HTTP client the app uses itself (SPEC.md §10, Offline).
final tileFetcherProvider = Provider<TileFetcher>((ref) {
  final fetcher = HttpTileFetcher();
  ref.onDispose(fetcher.close);
  return fetcher.call;
});

final browseCacheProvider = Provider<BrowseCache>(
  (ref) => FlutterMapBrowseCache(),
);

final locationSourceProvider = Provider<LocationSource>(
  (ref) => GeolocatorLocationSource(),
);

/// Distritos, concelhos and freguesias from the bundled CAOP asset (§6.2),
/// parsed in a background isolate on first use.
final adminBoundariesProvider = FutureProvider<AdminBoundaries>((ref) async {
  final text = await rootBundle.loadString(caopAsset, cache: false);
  return await Isolate.run(() => AdminBoundaries.parse(text));
});

/// File storage for properties; `decode` runs in a background isolate.
DocumentStore<PropertyDocument> propertyFileStore(AppDirectories dirs) =>
    DocumentStore(
      directory: dirs.properties,
      quarantine: dirs.quarantine,
      codec: const DocumentCodec(
        decode: PropertyDocument.fromJson,
        encode: _encodeProperty,
        idOf: _propertyId,
      ),
    );

Map<String, Object?> _encodeProperty(PropertyDocument d) => d.toJson();
String _propertyId(PropertyDocument d) => d.id;

/// The device clock (§9.1), restored from device.json.
final clockProvider = Provider<HlcClock>((ref) {
  final device = ref.read(deviceProvider);
  return HlcClock(deviceId: device.deviceId, last: device.lastTimestamp);
});

final propertyRepositoryProvider = Provider<PropertyRepository>((ref) {
  final repository = PropertyRepository(
    storage: ref.watch(propertyStorageProvider),
    clock: ref.watch(clockProvider),
    onClockAdvanced: (last) =>
        ref.read(deviceProvider.notifier).recordClock(last),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Live properties, sorted by name; loads from storage on first use.
final propertiesProvider = StreamProvider<List<PropertyDocument>>((ref) async* {
  final repository = ref.watch(propertyRepositoryProvider);
  await repository.load();
  yield repository.properties;
  await for (final _ in repository.changes) {
    yield repository.properties;
  }
});

final ProviderFamily<PropertyDocument?, String> propertyProvider =
    Provider.family<PropertyDocument?, String>(
      (ref, id) => ref
          .watch(propertiesProvider)
          .value
          ?.where((d) => d.id == id)
          .firstOrNull,
    );

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepositoryProvider).load();

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).save(state);
  }
}

final deviceProvider = NotifierProvider<DeviceController, DeviceIdentity>(
  DeviceController.new,
);

class DeviceController extends Notifier<DeviceIdentity> {
  @override
  DeviceIdentity build() => ref.read(deviceRepositoryProvider).loadOrCreate();

  Future<void> rename(String displayName) async {
    state = state.copyWith(displayName: displayName.trim());
    await ref.read(deviceRepositoryProvider).save(state);
  }

  /// Persists the clock so it never goes backwards across restarts.
  Future<void> recordClock(Hlc last) async {
    if (!(last > state.lastTimestamp)) return;
    state = state.copyWith(lastTimestamp: last);
    await ref.read(deviceRepositoryProvider).save(state);
  }
}
