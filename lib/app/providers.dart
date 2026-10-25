/// App-wide state. Repositories are provided at start-up (see bootstrap.dart)
/// through overrides.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/core/device/device_identity.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/core/storage/app_directories.dart';

final appDirectoriesProvider = Provider<AppDirectories>(
  (ref) => throw UnimplementedError('Overridden at start-up'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('Overridden at start-up'),
);

final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => throw UnimplementedError('Overridden at start-up'),
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
}
