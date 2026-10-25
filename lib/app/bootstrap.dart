import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/device/device_identity.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/core/storage/app_directories.dart';

/// Prepares storage and returns the provider overrides for the app.
Future<List<Override>> bootstrap() async {
  final dirs = AppDirectories(await getApplicationSupportDirectory());
  await dirs.ensureCreated();
  _installCrashLog(File(p.join(dirs.logs.path, 'crash.log')));
  return [
    appDirectoriesProvider.overrideWithValue(dirs),
    settingsRepositoryProvider.overrideWithValue(
      FileSettingsRepository(dirs.settingsFile),
    ),
    deviceRepositoryProvider.overrideWithValue(
      FileDeviceRepository(dirs.deviceFile),
    ),
  ];
}

/// Crashes are written to a local file only; the app has no crash reporting
/// service (SPEC.md §5.1). The user can choose to share the file.
void _installCrashLog(File log) {
  const maxBytes = 512 * 1024;

  void write(Object error, StackTrace? stack) {
    try {
      if (log.existsSync() && log.lengthSync() > maxBytes) {
        log.renameSync('${log.path}.1');
      }
      log.writeAsStringSync(
        '--- ${DateTime.now().toUtc().toIso8601String()}\n$error\n$stack\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // Never let logging itself crash the app.
    }
  }

  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    write(details.exception, details.stack);
    previousFlutterHandler?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    write(error, stack);
    return false;
  };
}
