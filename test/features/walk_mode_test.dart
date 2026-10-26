import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/editing/boundary_draft.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/features/editor/draw_map.dart';
import 'package:terrenos/features/editor/gps_capture.dart';

import '../helpers/harness.dart';

LocationFix _fix(double lat, double lon, {double accuracy = 3}) => LocationFix(
  lat: lat,
  lon: lon,
  accuracyMetres: accuracy,
  at: DateTime.utc(2026, 10, 25, 12),
);

Future<void> _openWalk(WidgetTester tester) async {
  await tester.tap(find.text('Properties'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('New property'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Walk it with GPS'));
  await tester.pumpAndSettle();
}

/// Taps "Add point" and stands still for the 5 s average, one fix a second.
Future<void> _addPoint(
  WidgetTester tester,
  Harness h,
  double lat,
  double lon, {
  double accuracy = 3,
}) async {
  await tester.tap(find.text('Add point'));
  await tester.pump();
  for (var s = 0; s < 6; s++) {
    h.location.emit(_fix(lat, lon, accuracy: accuracy));
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpAndSettle();
}

Color? _indicatorColour(WidgetTester tester) => tester
    .widget<Icon>(
      find.descendant(
        of: find.byType(AccuracyIndicator),
        matching: find.byIcon(Icons.gps_fixed),
      ),
    )
    .color;

List<Vertex> _ring(Harness h) =>
    h.drafts.load(BoundaryDraft.newProperty)!.parts.single.single;

void main() {
  testWidgets('walk the corners and save (REG-2, VTX-8)', (tester) async {
    final h = Harness(settings: onboarded);
    h.location
      ..current = LocationAccess.denied
      ..afterRequest = LocationAccess.granted;
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openWalk(tester);

    // Permission is asked for, then recording runs with a notice (REG-13).
    expect(h.location.requests, 1);
    expect(h.location.notificationRequests, 1);
    expect(h.location.notice?.title, 'Recording a boundary');
    expect(find.text('No GPS'), findsOneWidget);

    h.location.emit(_fix(40.2, -8.43, accuracy: 4));
    await tester.pumpAndSettle();
    expect(find.text('±4 m'), findsOneWidget);
    // Green under 5 m; the number is shown too (§4.1).
    expect(_indicatorColour(tester), Colors.green.shade700);

    await tester.tap(find.text('Add point'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.textContaining('seconds left'), findsOneWidget);
    for (var s = 0; s < 4; s++) {
      h.location.emit(_fix(40.2, -8.43));
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('V1 added: ±3 m from'), findsOneWidget);

    await _addPoint(tester, h, 40.2, -8.429);
    await _addPoint(tester, h, 40.201, -8.429);
    final ring = _ring(h);
    expect(ring, hasLength(3));
    expect(ring.every((v) => v.source == VertexSource.gps), isTrue);
    expect(ring.every((v) => v.isSurveyed), isTrue);
    expect(ring.first.gps!.samples, 3);
    expect(ring.first.gps!.deviceId, h.device.identity.deviceId);

    // Leaving walk mode stops the recording notice.
    await tester.tap(find.text('Stop walking'));
    await tester.pumpAndSettle();
    expect(find.text('Add point'), findsNothing);
    expect(h.location.notice, isNull);
  });

  testWidgets('a point can go into the nearest edge or after the selected', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    h.location.current = LocationAccess.granted;
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openWalk(tester);
    // V1 … V4 around a square, then one more in the middle of the south
    // side: "Nearest edge" puts it between V1 and V2.
    for (final (lat, lon) in const [
      (40.2, -8.43),
      (40.2, -8.429),
      (40.201, -8.429),
      (40.201, -8.43),
    ]) {
      await _addPoint(tester, h, lat, lon);
    }
    // The last point added is selected.
    expect(find.text('After V4'), findsOneWidget);

    await tester.tap(find.text('Nearest edge'));
    await tester.pumpAndSettle();
    await _addPoint(tester, h, 40.19999, -8.4295);
    final ring = _ring(h);
    expect(ring, hasLength(5));
    expect(ring[1].lat, closeTo(40.19999, 1e-7));
  });

  testWidgets('an imprecise point is flagged at once (VAL-8)', (tester) async {
    final h = Harness(settings: onboarded);
    h.location.current = LocationAccess.granted;
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openWalk(tester);
    await _addPoint(tester, h, 40.2, -8.43, accuracy: 25);
    expect(
      find.text('V1 added, but imprecise: ±25 m. Consider repeating it.'),
      findsOneWidget,
    );
    expect(find.textContaining('±25 m'), findsWidgets);
    expect(_indicatorColour(tester), Colors.red.shade700);
  });

  testWidgets('no position in time adds nothing', (tester) async {
    final h = Harness(settings: onboarded);
    h.location.current = LocationAccess.granted;
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openWalk(tester);
    await tester.tap(find.text('Add point'));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.textContaining('No GPS position.'), findsOneWidget);
    expect(h.drafts.loadAll(), isEmpty);
  });

  testWidgets('averaging can be cancelled', (tester) async {
    final h = Harness(settings: onboarded);
    h.location.current = LocationAccess.granted;
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openWalk(tester);
    await tester.tap(find.text('Add point'));
    h.location.emit(_fix(40.2, -8.43));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.textContaining('Tap to cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Add point'), findsOneWidget);
    expect(h.drafts.loadAll(), isEmpty);
  });

  testWidgets('warns about a low battery first (§7.3)', (tester) async {
    final h = Harness(settings: onboarded)..battery = 9;
    h.location.current = LocationAccess.granted;
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openWalk(tester);
    expect(find.text('Low battery'), findsOneWidget);
    expect(find.textContaining('9 %'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // Back to drawing, not recording.
    expect(find.text('Add point'), findsNothing);
    expect(h.location.notice, isNull);
  });

  testWidgets('without location permission it explains and stops', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openWalk(tester);
    expect(find.textContaining('Allow location access'), findsOneWidget);
    expect(find.text('Add point'), findsNothing);
  });

  testWidgets('amber between 5 and 15 m', (tester) async {
    final h = Harness(settings: onboarded);
    h.location.current = LocationAccess.granted;
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openWalk(tester);
    for (final (accuracy, colour) in [
      (4.9, Colors.green.shade700),
      (5.0, Colors.amber.shade800),
      (15.0, Colors.amber.shade800),
      (15.4, Colors.red.shade700),
    ]) {
      h.location.emit(_fix(40.2, -8.43, accuracy: accuracy));
      await tester.pumpAndSettle();
      expect(_indicatorColour(tester), colour, reason: '$accuracy m');
    }
  });

  group('continuous (REG-3)', () {
    /// Walks a 20 m square from 40.2 N, 8.43 W, one fix a second, 2.5 m
    /// apart.
    Future<void> walkSquare(WidgetTester tester, Harness h) async {
      for (final (dx, dy) in const [(1, 0), (0, 1), (-1, 0), (0, -1)]) {
        for (var i = 0; i < 8; i++) {
          final east =
              (dx == 0 ? (dy > 0 ? 20 : 0) : (dx > 0 ? 0 : 20)) + dx * 2.5 * i;
          final north =
              (dy == 0 ? (dx > 0 ? 0 : 20) : (dy > 0 ? 0 : 20)) + dy * 2.5 * i;
          h.location.emit(_fix(40.2 + north / 111040, -8.43 + east / 85120));
          await tester.pump(const Duration(seconds: 1));
        }
      }
    }

    Future<Harness> openTrack(WidgetTester tester) async {
      usePhoneScreen(tester);
      final h = Harness(settings: onboarded);
      h.location.current = LocationAccess.granted;
      await h.pump(tester);
      await tester.pumpAndSettle();
      await _openWalk(tester);
      await tester.tap(find.text('Continuous'));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('records a track and adds it simplified', (tester) async {
      final h = await openTrack(tester);
      expect(find.textContaining('every 2 m or 5 seconds'), findsOneWidget);
      await tester.tap(find.text('Start recording'));
      await tester.pump();
      await walkSquare(tester, h);
      expect(find.text('32 points · 78 m'), findsOneWidget);
      expect(find.byType(DrawMap), findsOneWidget);
      // The track is drawn as it grows.
      final map = tester.widget<DrawMap>(find.byType(DrawMap));
      expect(map.track, hasLength(32));
      // Recording can't be left by accident.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.directions_walk),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Stop walking'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Stop walking'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(find.text('32 points recorded → 4 vertices'), findsOneWidget);
      await tester.tap(find.text('0.5 m'));
      await tester.pumpAndSettle();
      expect(find.text('32 points recorded → 4 vertices'), findsOneWidget);
      await tester.tap(find.text('Add vertices'));
      await tester.pumpAndSettle();

      expect(find.text('4 vertices added from the track.'), findsOneWidget);
      final ring = _ring(h);
      expect(ring, hasLength(4));
      expect(ring.every((v) => v.source == VertexSource.gps), isTrue);
      expect(ring.every((v) => v.gps!.samples == 1), isTrue);
      expect(ring.first.lat, closeTo(40.2, 1e-7));
      expect(tester.widget<DrawMap>(find.byType(DrawMap)).track, isNull);

      // One undo step removes the whole track.
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(h.drafts.load(BoundaryDraft.newProperty), isNull);
    });

    testWidgets('imprecise positions are left out and counted', (tester) async {
      final h = await openTrack(tester);
      await tester.tap(find.text('Start recording'));
      await tester.pump();
      h.location.emit(_fix(40.2, -8.43));
      await tester.pump(const Duration(seconds: 1));
      h.location.emit(_fix(40.2001, -8.43, accuracy: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('1 point · 0.0 m · 1 imprecise position left out'),
        findsOneWidget,
      );
    });

    testWidgets('too short a track adds nothing', (tester) async {
      final h = await openTrack(tester);
      await tester.tap(find.text('Start recording'));
      await tester.pump();
      h.location.emit(_fix(40.2, -8.43));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Too few points'), findsOneWidget);
      expect(h.drafts.load(BoundaryDraft.newProperty), isNull);
      expect(find.text('Start recording'), findsOneWidget);
    });

    testWidgets('a track can be discarded', (tester) async {
      final h = await openTrack(tester);
      await tester.tap(find.text('Start recording'));
      await tester.pump();
      await walkSquare(tester, h);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(h.drafts.load(BoundaryDraft.newProperty), isNull);
      expect(tester.widget<DrawMap>(find.byType(DrawMap)).track, isNull);
    });
  });
}
