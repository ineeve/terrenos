import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/device/device_identity.dart';
import 'package:terrenos/core/settings/app_settings.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('terrenos_test_'));
  tearDown(() => root.deleteSync(recursive: true));

  group('settings', () {
    test('defaults when there is no file', () {
      final repo = FileSettingsRepository(File(p.join(root.path, 's.json')));
      expect(repo.load(), const AppSettings());
    });

    test('saves and loads', () async {
      final file = File(p.join(root.path, 's.json'));
      const settings = AppSettings(
        language: AppLanguage.pt,
        areaUnit: AreaUnit.squareMetres,
        coordinateFormat: CoordinateFormat.ptTm06,
        entryFormat: CoordinateFormat.degreesMinutesSeconds,
        onboardingComplete: true,
      );
      await FileSettingsRepository(file).save(settings);
      expect(FileSettingsRepository(file).load(), settings);
    });

    test('unknown values and broken files fall back to defaults', () {
      expect(
        AppSettings.fromJson(const {'language': 'fr', 'areaUnit': 'acres'}),
        const AppSettings(),
      );
      final file = File(p.join(root.path, 's.json'))..writeAsStringSync('{');
      expect(FileSettingsRepository(file).load(), const AppSettings());
    });

    test('copyWith can clear the language back to the phone default', () {
      const pt = AppSettings(language: AppLanguage.pt);
      expect(pt.copyWith(language: () => null).language, isNull);
      expect(pt.copyWith(areaUnit: AreaUnit.hectares).language, AppLanguage.pt);
    });
  });

  group('device identity', () {
    test('is created once and then reused', () {
      final file = File(p.join(root.path, 'device.json'));
      final first = FileDeviceRepository(file).loadOrCreate();
      expect(first.deviceId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(first.displayName, isEmpty);
      expect(FileDeviceRepository(file).loadOrCreate(), first);
    });

    test('saves the name and the clock', () async {
      final file = File(p.join(root.path, 'device.json'));
      final repo = FileDeviceRepository(file);
      final created = repo.loadOrCreate();
      final updated = created.copyWith(
        displayName: 'Telemóvel da Maria',
        lastTimestamp: Hlc(1729852920000, 3, created.deviceId),
      );
      await repo.save(updated);
      expect(FileDeviceRepository(file).loadOrCreate(), updated);
    });

    test('a broken file is reported, never replaced by a new id', () {
      final file = File(p.join(root.path, 'device.json'))
        ..writeAsStringSync('{"deviceId": "../../etc"}');
      expect(
        () => FileDeviceRepository(file).loadOrCreate(),
        throwsFormatException,
      );
      expect(file.readAsStringSync(), contains('../../etc'));
    });

    test('generated ids differ', () {
      final rng = Random(1);
      expect(
        DeviceIdentity.generate(rng).deviceId,
        isNot(DeviceIdentity.generate(rng).deviceId),
      );
    });
  });
}
