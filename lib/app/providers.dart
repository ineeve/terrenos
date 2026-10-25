/// App-wide state. Repositories are provided at start-up (see bootstrap.dart)
/// through overrides.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:terrenos/core/caop/caop.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/device/device_identity.dart';
import 'package:terrenos/core/editing/drafts.dart';
import 'package:terrenos/core/location/location_source.dart';
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

/// Official administrative boundaries (SPEC.md §6.2), parsed in the
/// background from the bundled asset. Overridden in tests.
final caopProvider = FutureProvider<Caop>((ref) async {
  final json = await rootBundle.loadString('assets/caop/caop.json');
  return await compute(Caop.parse, json);
});

/// CAOP for automatic locations: `null` rather than an error if it can't be
/// loaded, because a missing location is not a failure.
final caopOrNullProvider = FutureProvider<Caop?>((ref) async {
  try {
    return await ref.watch(caopProvider.future);
  } on Object {
    return null;
  }
});

final draftStorageProvider = Provider<DraftStorage>(
  (ref) => throw UnimplementedError('Overridden at start-up'),
);

/// Unfinished boundary edits (REG-12), newest first. Invalidate after
/// saving or deleting a draft.
final draftsProvider = FutureProvider<List<BoundaryDraft>>(
  (ref) => ref.watch(draftStorageProvider).loadAll(),
);

/// The phone's position (MAP-4, §7.3). Overridden in tests.
final locationSourceProvider = Provider<LocationSource>(
  (ref) => const GeolocatorLocationSource(),
);
