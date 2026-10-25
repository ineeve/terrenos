import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/location/location_hub.dart';
import 'package:terrenos/core/location/location_source.dart';

import '../../helpers/fake_location.dart';

LocationFix _fix(double lat) => LocationFix(
  lat: lat,
  lon: -8.43,
  accuracyMetres: 4,
  at: DateTime.utc(2026),
);

const _notice = RecordingNotice(
  title: 'Recording',
  text: 'Walking the boundary',
  channelName: 'Field recording',
);

/// Lets the hub's serialised restarts run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeLocationSource source;
  late LocationHub hub;

  setUp(() {
    source = FakeLocationSource(current: LocationAccess.granted);
    hub = LocationHub(source);
  });

  test('runs only while someone listens', () async {
    expect(hub.isRunning, isFalse);
    final fixes = <LocationFix>[];
    final sub = hub.fixes().listen(fixes.add);
    await _settle();
    expect(hub.isRunning, isTrue);
    source.emit(_fix(40.2));
    await _settle();
    expect(fixes.single.lat, 40.2);

    await sub.cancel();
    await _settle();
    expect(hub.isRunning, isFalse);
    expect(source.listening, isFalse);
  });

  test('one GPS stream feeds every listener', () async {
    final a = <LocationFix>[];
    final b = <LocationFix>[];
    final subA = hub.fixes().listen(a.add);
    final subB = hub.fixes().listen(b.add);
    await _settle();
    source.emit(_fix(40.2));
    await _settle();
    expect((a.length, b.length), (1, 1));
    await subA.cancel();
    await subB.cancel();
  });

  test('restarts with the notice while anything records (REG-13)', () async {
    final map = hub.fixes().listen((_) {});
    await _settle();
    expect(hub.notice, isNull);
    expect(source.notice, isNull);

    final walk = hub.fixes(notice: _notice).listen((_) {});
    await _settle();
    expect(hub.notice, _notice);
    // The stream geolocator runs now carries the notice.
    expect(source.notice, _notice);

    // The map's listener still gets fixes from the restarted stream.
    final seen = <LocationFix>[];
    map.onData(seen.add);
    source.emit(_fix(40.3));
    await _settle();
    expect(seen.single.lat, 40.3);

    await walk.cancel();
    await _settle();
    expect(hub.notice, isNull);
    expect(source.notice, isNull);
    expect(hub.isRunning, isTrue);
    await map.cancel();
  });

  test('errors reach listeners and a later listener starts again', () async {
    final errors = <Object>[];
    final sub = hub.fixes().listen((_) {}, onError: errors.add);
    await _settle();
    source.fail(StateError('location off'));
    await _settle();
    expect(errors, hasLength(1));
    expect(hub.isRunning, isFalse);
    await sub.cancel();

    final again = hub.fixes().listen((_) {});
    await _settle();
    expect(hub.isRunning, isTrue);
    await again.cancel();
  });

  test('dispose stops the stream', () async {
    final done = Completer<void>();
    hub.fixes().listen((_) {}, onDone: done.complete);
    await _settle();
    await hub.dispose();
    expect(source.listening, isFalse);
  });
}
