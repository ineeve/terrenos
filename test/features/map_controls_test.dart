import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/features/map/map_overlays.dart';
import 'package:terrenos/features/map/my_location.dart';

import '../helpers/harness.dart';

final _coimbra = LocationFix(
  lat: 40.2085,
  lon: -8.4265,
  accuracyMetres: 6,
  at: DateTime.utc(2026, 10, 25, 12),
);

/// The position marker, found by its TalkBack label.
final Finder _dot = find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == 'Your location',
);

MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(MyLocationLayer)));

/// The snack bar sits over the button until it times out.
Future<void> _dismissSnackBar(WidgetTester tester) async {
  ScaffoldMessenger.of(tester.element(find.byType(MyLocationLayer)))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
}

MapController _controller(WidgetTester tester) =>
    MapController.of(tester.element(find.byType(MyLocationLayer)));

void main() {
  group('my location (MAP-4)', () {
    testWidgets('asks only when tapped, then centres on the first fix', (
      tester,
    ) async {
      final h = Harness(settings: onboarded);
      h.location.afterRequest = LocationAccess.granted;
      await h.pump(tester);
      await tester.pumpAndSettle();
      expect(h.location.requests, 0);
      expect(h.location.listening, isFalse);
      expect(find.byIcon(Icons.location_disabled), findsOneWidget);

      await tester.tap(find.byTooltip('Centre on my location'));
      await tester.pumpAndSettle();
      expect(h.location.requests, 1);
      expect(h.location.listening, isTrue);
      expect(find.byIcon(Icons.location_searching), findsOneWidget);

      h.location.emit(_coimbra);
      await tester.pumpAndSettle();
      expect(_dot, findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      final camera = _camera(tester);
      expect(camera.center.latitude, closeTo(_coimbra.lat, 1e-6));
      expect(camera.center.longitude, closeTo(_coimbra.lon, 1e-6));
      expect(camera.zoom, CentreOnMeButton.zoom);

      final circle = tester.widget<CircleLayer>(find.byType(CircleLayer));
      expect(circle.circles.single.radius, 6);
      expect(circle.circles.single.useRadiusInMeter, isTrue);
    });

    testWidgets('shows the position at once if already allowed', (
      tester,
    ) async {
      final h = Harness(settings: onboarded);
      h.location.current = LocationAccess.granted;
      await h.pump(tester);
      await tester.pumpAndSettle();
      expect(h.location.listening, isTrue);
      h.location.emit(_coimbra);
      await tester.pumpAndSettle();
      expect(_dot, findsOneWidget);
      // The map stays where it was until the user asks.
      expect(_camera(tester).zoom, lessThan(10));

      _controller(tester).move(_camera(tester).center, 19);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Centre on my location'));
      await tester.pumpAndSettle();
      expect(_camera(tester).center.latitude, closeTo(_coimbra.lat, 1e-6));
      // Already closer than the default zoom: kept.
      expect(_camera(tester).zoom, 19);
    });

    testWidgets('explains a refusal and offers the settings', (tester) async {
      final h = Harness(settings: onboarded);
      await h.pump(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Centre on my location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Allow location access'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Settings'), findsNothing);

      await _dismissSnackBar(tester);
      h.location.afterRequest = LocationAccess.deniedForever;
      await tester.tap(find.byTooltip('Centre on my location'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
      expect(h.location.openedSettings, [LocationAccess.deniedForever]);

      await _dismissSnackBar(tester);
      h.location.afterRequest = LocationAccess.serviceOff;
      await tester.tap(find.byTooltip('Centre on my location'));
      await tester.pumpAndSettle();
      expect(
        find.text('Location is turned off on this phone.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
      expect(h.location.openedSettings.last, LocationAccess.serviceOff);
    });

    testWidgets('pauses GPS while the app is in the background', (
      tester,
    ) async {
      final h = Harness(settings: onboarded);
      h.location.current = LocationAccess.granted;
      await h.pump(tester);
      await tester.pumpAndSettle();
      h.location.emit(_coimbra);
      await tester.pumpAndSettle();
      expect(h.location.listening, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pumpAndSettle();
      expect(h.location.listening, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.location.listening, isTrue);
      // The old position isn't shown again; only a fresh fix.
      expect(_dot, findsNothing);
      h.location.emit(_coimbra);
      await tester.pumpAndSettle();
      expect(_dot, findsOneWidget);
    });

    testWidgets('hides the dot when location stops working', (tester) async {
      final h = Harness(settings: onboarded);
      h.location.current = LocationAccess.granted;
      await h.pump(tester);
      await tester.pumpAndSettle();
      h.location.emit(_coimbra);
      await tester.pumpAndSettle();
      expect(_dot, findsOneWidget);

      h.location
        ..current = LocationAccess.serviceOff
        ..fail(StateError('location off'));
      await tester.pumpAndSettle();
      expect(_dot, findsNothing);
      expect(find.byIcon(Icons.location_disabled), findsOneWidget);
    });
  });

  testWidgets('the compass appears when rotated and turns north up', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Turn north up'), findsNothing);

    _controller(tester).rotate(45);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Turn north up'), findsOneWidget);

    await tester.tap(find.byTooltip('Turn north up'));
    await tester.pumpAndSettle();
    expect(_camera(tester).rotation, 0);
    expect(find.byTooltip('Turn north up'), findsNothing);
  });

  group('administrative boundaries (MAP-2)', () {
    late AdminBoundaries caop;

    setUpAll(() {
      caop = AdminBoundaries.parse(File(caopAsset).readAsStringSync());
    });

    int count(AdminBoundaries caop, Set<BoundaryLevel> levels) =>
        caop.levels.where(levels.contains).length;

    List<Polyline> drawn(WidgetTester tester) {
      final layers = find.descendant(
        of: find.byType(AdminBoundariesLayer),
        matching: find.byType(PolylineLayer),
      );
      if (layers.evaluate().isEmpty) return const [];
      return tester.widget<PolylineLayer>(layers).polylines;
    }

    testWidgets('show more detail as the map zooms in', (tester) async {
      final h = Harness(settings: onboarded, caop: caop);
      await h.pump(tester);
      await tester.pumpAndSettle();

      final wide = {BoundaryLevel.outer, BoundaryLevel.distrito};
      expect(drawn(tester), hasLength(count(caop, wide)));

      _controller(tester).move(_camera(tester).center, 10);
      await tester.pumpAndSettle();
      expect(
        drawn(tester),
        hasLength(count(caop, {...wide, BoundaryLevel.concelho})),
      );

      _controller(tester).move(_camera(tester).center, 13);
      await tester.pumpAndSettle();
      expect(drawn(tester), hasLength(caop.arcs.length));
    });

    testWidgets('can be switched off in the layers sheet', (tester) async {
      final h = Harness(settings: onboarded, caop: caop);
      await h.pump(tester);
      await tester.pumpAndSettle();
      expect(drawn(tester), isNotEmpty);

      await tester.tap(find.byTooltip('Map imagery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrative boundaries'));
      await tester.pumpAndSettle();
      expect(drawn(tester), isEmpty);
      final toggle = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Administrative boundaries'),
      );
      expect(toggle.value, isFalse);
    });

    test('levels by zoom', () {
      expect(AdminBoundariesLayer.levelsAt(7), [
        BoundaryLevel.distrito,
        BoundaryLevel.outer,
      ]);
      expect(AdminBoundariesLayer.levelsAt(12), BoundaryLevel.values.reversed);
    });
  });
}
