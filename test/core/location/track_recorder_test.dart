import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/location/track_recorder.dart';

final _start = DateTime.utc(2026, 10, 26, 12);

/// [east] and [north] metres from 40.2 N, 8.43 W, [seconds] after the start.
LocationFix _at(
  double east,
  double north, {
  int seconds = 0,
  double accuracy = 3,
}) => LocationFix(
  lat: 40.2 + north / 111040,
  lon: -8.43 + east / 85120,
  accuracyMetres: accuracy,
  at: _start.add(Duration(seconds: seconds)),
);

/// A 20 m square walked anticlockwise from the south-west corner, a fix
/// every 2 s, 2.5 m apart so each corner is reached, with up to 0.4 m of
/// sideways wobble between the corners.
List<LocationFix> _square() {
  double wobble(int i) => i == 0 ? 0 : (i % 3 - 1) * 0.4;
  final positions = [
    for (var i = 0; i < 8; i++) (2.5 * i, wobble(i)),
    for (var i = 0; i < 8; i++) (20 + wobble(i), 2.5 * i),
    for (var i = 0; i < 8; i++) (20 - 2.5 * i, 20 + wobble(i)),
    for (var i = 0; i < 8; i++) (wobble(i), 20 - 2.5 * i),
  ];
  return [
    for (final (i, (east, north)) in positions.indexed)
      _at(east, north, seconds: 2 * i),
  ];
}

void main() {
  group('recording (REG-3)', () {
    test('keeps a point every 2 m walked', () {
      final track = TrackRecorder();
      final kept = [
        for (var m = 0; m <= 10; m++)
          track.add(_at(m.toDouble(), 0, seconds: m)),
      ];
      expect(kept, [
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
      ]);
      expect(track.points, hasLength(6));
      expect(track.lengthMetres, closeTo(10, 0.05));
    });

    test('and every 5 s when standing still', () {
      final track = TrackRecorder();
      for (var s = 0; s <= 12; s++) {
        track.add(_at(0, 0, seconds: s));
      }
      expect(track.points.map((f) => f.at.second), [0, 5, 10]);
      expect(track.lengthMetres, 0);
    });

    test('leaves out imprecise fixes and counts them', () {
      final track = TrackRecorder()
        ..add(_at(0, 0))
        ..add(_at(30, 0, seconds: 1, accuracy: 25))
        ..add(_at(2, 0, seconds: 2));
      expect(track.points, hasLength(2));
      expect(track.skipped, 1);
      expect(track.lengthMetres, closeTo(2, 0.01));
    });
  });

  group('simplifying (REG-3)', () {
    test('a walked square becomes its 4 corners at 1 m', () {
      // Every fix is 2.5 m from the last, so all are kept.
      final track = TrackRecorder();
      _square().forEach(track.add);
      final corners = simplifyTrack(track.points, 1);
      expect(corners, hasLength(4));
      // The start, then the other corners within a metre.
      expect(corners.first, track.points.first);
      for (final (i, (east, north)) in const [
        (20.0, 0.0),
        (20.0, 20.0),
        (0.0, 20.0),
      ].indexed) {
        final c = corners[i + 1];
        expect((c.lon + 8.43) * 85120, closeTo(east, 0.01));
        expect((c.lat - 40.2) * 111040, closeTo(north, 0.01));
      }
    });

    test('a smaller tolerance keeps more of the wobble', () {
      final track = TrackRecorder();
      _square().forEach(track.add);
      expect(
        simplifyTrack(track.points, 0.1).length,
        greaterThan(simplifyTrack(track.points, 1).length),
      );
    });

    test('three points or fewer are kept as they are', () {
      final three = [_at(0, 0), _at(5, 0), _at(5, 5)];
      expect(simplifyTrack(three, 100), three);
    });
  });
}
