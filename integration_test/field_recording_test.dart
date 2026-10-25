// Runs on a device or emulator, with real GPS and Android services:
//   flutter test integration_test/field_recording_test.dart --flavor dev
// Location and notification permissions must be granted beforehand, and
// the device must be receiving fixes (on an emulator: `adb emu geo fix`).
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:terrenos/core/location/gps_averaging.dart';
import 'package:terrenos/core/location/location_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records and averages fixes as a foreground service (T2.1)', (
    tester,
  ) async {
    final source = GeolocatorLocationSource();
    expect(await source.access(), LocationAccess.granted);
    expect(await source.requestNotifications(), isTrue);

    const notice = RecordingNotice(
      title: 'Terrenos: integration test',
      text: 'Recording a boundary',
      channelName: 'Field recording',
    );
    final errors = <Object>[];
    final averaged = await tester.runAsync(
      () => GpsSampler(
        source.fixes(notice: notice).handleError((Object e, StackTrace s) {
          errors.add(e);
          Error.throwWithStackTrace(e, s);
        }),
      ).sample(duration: const Duration(seconds: 10)),
    );

    expect(errors, isEmpty);
    expect(averaged, isNotNull);
    expect(averaged!.samples, greaterThanOrEqualTo(3));
    expect(averaged.lat, closeTo(40.2, 1e-4));
    expect(averaged.lon, closeTo(-8.43, 1e-4));
    expect(averaged.mocked, isFalse);
  });
}
