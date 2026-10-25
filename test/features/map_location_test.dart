import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/location/location_source.dart';

import '../helpers/harness.dart';

MapController _controller(WidgetTester tester) =>
    tester.widget<FlutterMap>(find.byType(FlutterMap).first).mapController!;

void main() {
  testWidgets('shows the position and centres on the first fix (MAP-4)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show my location'));
    await tester.pumpAndSettle();
    h.location.emit(40.2005, -8.4295, accuracy: 4.6);
    await tester.pumpAndSettle();

    final camera = _controller(tester).camera;
    expect(camera.center.latitude, closeTo(40.2005, 1e-6));
    expect(camera.zoom, greaterThanOrEqualTo(17));
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Your location (±5 m)',
      ),
      findsOneWidget,
    );
    final circle = tester.widget<CircleLayer>(find.byType(CircleLayer));
    expect(circle.circles.single.radius, 4.6);
    expect(circle.circles.single.useRadiusInMeter, isTrue);

    // Later fixes update the dot without moving the map.
    _controller(tester).move(_controller(tester).camera.center, 12);
    h.location.emit(40.3, -8.5);
    await tester.pumpAndSettle();
    expect(_controller(tester).camera.zoom, 12);
  });

  testWidgets('explains why the position is unavailable', (tester) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();

    h.location.availability = LocationAvailability.serviceDisabled;
    await tester.tap(find.byTooltip('Show my location'));
    await tester.pumpAndSettle();
    expect(
      find.text('Turn on location (GPS) in the phone settings.'),
      findsOneWidget,
    );
    ScaffoldMessenger.of(tester.element(find.byType(FlutterMap)))
        .clearSnackBars();
    await tester.pumpAndSettle();

    h.location.availability = LocationAvailability.deniedForever;
    await tester.tap(find.byTooltip('Show my location'));
    await tester.pumpAndSettle();
    expect(
      find.text('Allow location access to see where you are on the map.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(h.location.settingsOpened, 1);
    expect(find.byType(CircleLayer), findsNothing);
  });

  testWidgets('goes to typed coordinates and marks them (MAP-10)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Go to coordinates'));
    await tester.pumpAndSettle();
    expect(find.text('Go to coordinates'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '41.15835');
    await tester.enterText(find.byType(TextField).at(1), '-8.6285');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final camera = _controller(tester).camera;
    expect(camera.center.latitude, closeTo(41.15835, 1e-6));
    expect(camera.center.longitude, closeTo(-8.6285, 1e-6));
    expect(camera.zoom, greaterThanOrEqualTo(18));
    expect(find.byIcon(Icons.location_on), findsOneWidget);
  });
}
