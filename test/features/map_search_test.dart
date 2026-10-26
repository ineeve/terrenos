import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/places/place_search.dart';
import 'package:terrenos/features/map/map_search.dart';
import 'package:terrenos/features/map/my_location.dart';
import 'package:terrenos/features/map/place_labels.dart';

import '../helpers/harness.dart';
import '../helpers/place_fixtures.dart';

PropertyDocument _olival() =>
    PropertyDocument.create(
          id: 'p1',
          name: 'Olival do Ribeiro',
          timestamp: const Hlc(1, 0, 'dev'),
        )
        .withField(
          PropertyField.processNumber,
          '0012/2023-A',
          const Hlc(2, 0, 'dev'),
        )
        .withGeometry([
          [
            [
              for (final (i, (lon, lat)) in const [
                (-8.43, 40.2),
                (-8.429, 40.2),
                (-8.429, 40.201),
              ].indexed)
                Vertex(
                  id: '$i',
                  lon: lon,
                  lat: lat,
                  source: VertexSource.typed,
                ),
            ],
          ],
        ], const Hlc(3, 0, 'dev'));

MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(MyLocationLayer)));

final Finder _pin = find.bySemanticsLabel('Search result. Tap to remove.');

Future<Harness> _open(WidgetTester tester) async {
  final h = Harness(settings: onboarded, caop: testCaop, places: testPlaces);
  h.properties.documents['p1'] = _olival();
  await h.pump(tester);
  await tester.pumpAndSettle();
  return h;
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.tap(find.text('Search places and properties'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

void main() {
  group('place names (MAP-15)', () {
    MapCamera camera(double zoom, LatLng center) => MapCamera(
      crs: const Epsg3857(),
      center: center,
      zoom: zoom,
      rotation: 0,
      nonRotatedSize: const Size(400, 800),
    );
    const piodao = LatLng(40.22955, -7.82476);
    List<String> names(MapCamera camera) => [
      for (final l in PlaceLabelsLayer.layout(
        camera,
        testPlaces.places,
        (_) => const Size(80, 16),
      ))
        l.place.name,
    ];

    test('shows smaller places as the map zooms in', () {
      expect(names(camera(7, piodao)), ['Coimbra']);
      expect(names(camera(11, piodao)), ['Piódão']);
      expect(names(camera(14, piodao)), [
        'Piódão',
        'Foz de Piódão',
        'Chãs de Piódão',
      ]);
    });

    test('leaves out a name that would overlap a bigger place', () {
      // Malhadapiodao is on the same spot as Piódão.
      expect(names(camera(18, piodao)), isNot(contains('Malhadapiodao')));
    });

    test('labels only what is on screen, at the place', () {
      final c = camera(11, piodao);
      final labels = PlaceLabelsLayer.layout(
        c,
        testPlaces.places,
        (_) => const Size(80, 16),
      );
      expect(labels.single.box.center.dx, closeTo(200, 0.5));
      expect(labels.single.box.center.dy, closeTo(400, 0.5));
    });

    testWidgets('can be turned off in the layers sheet', (tester) async {
      await _open(tester);
      final paint = find.descendant(
        of: find.byType(PlaceLabelsLayer),
        matching: find.byType(CustomPaint),
      );
      expect(paint, findsOneWidget);

      await tester.tap(find.byTooltip('Map imagery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Place names'));
      await tester.pumpAndSettle();
      expect(paint, findsNothing);
    });
  });

  group('map search (MAP-9)', () {
    testWidgets('asks for a name until two letters are typed', (tester) async {
      await _open(tester);
      await _search(tester, 'p');
      expect(find.textContaining('Type the name of a town'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing found for “zzzz”.'), findsOneWidget);
    });

    testWidgets('goes to a village and marks it with a pin', (tester) async {
      await _open(tester);
      await _search(tester, 'piodao');
      expect(find.text('Places'), findsOneWidget);
      expect(find.text('My properties'), findsNothing);
      expect(find.text('Freguesia · Arganil'), findsOneWidget);
      await tester.tap(find.text('Village · Arganil'));
      await tester.pumpAndSettle();

      final camera = _camera(tester);
      expect(camera.center.latitude, closeTo(40.22955, 1e-6));
      expect(camera.center.longitude, closeTo(-7.82476, 1e-6));
      expect(camera.zoom, MapSearchBar.pointZoom[PlaceResultKind.village]);
      expect(_pin, findsOneWidget);

      await tester.tap(_pin);
      await tester.pumpAndSettle();
      expect(_pin, findsNothing);
    });

    testWidgets('frames a concelho without a pin', (tester) async {
      await _open(tester);
      await _search(tester, 'arganil');
      await tester.tap(find.text('Concelho · Coimbra'));
      await tester.pumpAndSettle();

      final camera = _camera(tester);
      expect(camera.center.latitude, closeTo(40.225, 0.01));
      expect(camera.center.longitude, closeTo(-7.825, 0.01));
      expect(camera.zoom, greaterThan(10));
      expect(_pin, findsNothing);
    });

    testWidgets('finds a property by its process number', (tester) async {
      await _open(tester);
      await _search(tester, '0012/2023');
      expect(find.text('My properties'), findsOneWidget);
      expect(find.text('Places'), findsNothing);
      await tester.tap(find.text('Olival do Ribeiro'));
      await tester.pumpAndSettle();

      final camera = _camera(tester);
      expect(camera.center.latitude, closeTo(40.2005, 1e-4));
      expect(camera.center.longitude, closeTo(-8.4295, 1e-4));
      expect(camera.zoom, 18);
    });

    testWidgets('lists properties before places', (tester) async {
      await _open(tester);
      await _search(tester, 'ol');
      final property = tester.getTopLeft(find.text('Olival do Ribeiro'));
      final place = tester.getTopLeft(find.text('Places'));
      expect(property.dy, lessThan(place.dy));

      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Type the name of a town'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_camera(tester).zoom, 7);
    });
  });
}
