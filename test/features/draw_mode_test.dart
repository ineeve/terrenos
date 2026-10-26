import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/editing/boundary_draft.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/features/editor/draw_map.dart';
import 'package:terrenos/features/map/map_overlays.dart';
import 'package:terrenos/features/map/place_labels.dart';

import '../helpers/harness.dart';

Future<void> _openDraw(WidgetTester tester) async {
  await tester.tap(find.text('Properties'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('New property'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Draw on the map'));
  await tester.pumpAndSettle();
}

/// A point on the draw map, as an offset from its centre.
Offset _onMap(WidgetTester tester, Offset fromCentre) =>
    tester.getCenter(find.byType(FlutterMap)) + fromCentre;

MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(MarkerLayer).first));

Finder _vertex(String id) => find.byKey(ValueKey('vertex-$id'));

/// Taps the map, then lets flutter_map's 250 ms tap timer run out.
Future<void> _tapMap(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Draws a triangle south of the coordinate card.
Future<void> _drawTriangle(WidgetTester tester) async {
  for (final offset in const [
    Offset(-60, 40),
    Offset(60, 40),
    Offset(0, 120),
  ]) {
    await _tapMap(tester, _onMap(tester, offset));
  }
}

List<Vertex> _draftRing(Harness h) =>
    h.drafts.load(BoundaryDraft.newProperty)!.parts.single.single;

PropertyDocument _neighbour(List<(double, double)> corners) =>
    PropertyDocument.create(
      id: 'p1',
      name: 'Vizinho',
      timestamp: const Hlc(1, 0, 'dev'),
    ).withGeometry([
      [
        [
          for (final (i, (lat, lon)) in corners.indexed)
            Vertex(id: 'n$i', lon: lon, lat: lat, source: VertexSource.typed),
        ],
      ],
    ], const Hlc(2, 0, 'dev'));

void main() {
  testWidgets('tapping the map draws a property, saved as a draft (REG-1)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openDraw(tester);
    expect(find.textContaining('Tap the map to add vertices'), findsOneWidget);
    expect(find.text('Add at least 3 vertices.'), findsOneWidget);

    await _drawTriangle(tester);
    // Live area and perimeter (REG-6), and the last vertex's coordinates.
    expect(find.textContaining('Area:'), findsOneWidget);
    expect(find.textContaining('Perimeter:'), findsOneWidget);
    expect(find.text('V3'), findsOneWidget);
    expect(find.textContaining('Lat '), findsOneWidget);

    // Every change is on disk (REG-12).
    final ring = _draftRing(h);
    expect(ring, hasLength(3));
    expect(ring.every((v) => v.source == VertexSource.map), isTrue);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Property details'), findsOneWidget);
    expect(h.drafts.load(BoundaryDraft.newProperty), isNotNull);

    await tester.enterText(find.byType(TextFormField).at(0), 'Horta');
    await tester.tap(find.text('Property type *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rustic').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Land use *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orchard').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save property'));
    await tester.pumpAndSettle();

    final saved = h.properties.documents.values.single;
    expect(saved.geometry.current!.vertices, hasLength(3));
    // Saved, so there's nothing left to resume.
    expect(h.drafts.loadAll(), isEmpty);
  });

  testWidgets('draws over the same layers as the map tab', (tester) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openDraw(tester);
    Finder inDrawMap(Type type) =>
        find.descendant(of: find.byType(DrawMap), matching: find.byType(type));
    expect(inDrawMap(AdminBoundariesLayer), findsOneWidget);
    expect(inDrawMap(PlaceLabelsLayer), findsOneWidget);
    expect(inDrawMap(Scalebar), findsOneWidget);
    expect(find.text('Ortofotos © DGT 2025'), findsOneWidget);
    expect(find.text('© OpenStreetMap'), findsOneWidget);

    // The layers sheet is the map tab's; its switches apply here too.
    await tester.tap(find.byTooltip('Map imagery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place names'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PlaceLabelsLayer),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    // Tapping the button didn't add a vertex.
    expect(h.drafts.load(BoundaryDraft.newProperty), isNull);
  });

  testWidgets('a finger dragging a vertex moves it, not the map', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openDraw(tester);
    await _drawTriangle(tester);
    final first = _draftRing(h).first;
    final centre = _camera(tester).center;

    // A real finger moves a few pixels per event, so the map's drag
    // (18 px slop) would claim it before a default pan (36 px).
    final gesture = await tester.startGesture(
      tester.getCenter(_vertex(first.id)),
    );
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(3, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_camera(tester).center, centre);
    final moved = _draftRing(h).first;
    expect(moved.id, first.id);
    expect(moved.lon, greaterThan(first.lon));
    expect(moved.lat, closeTo(first.lat, 1e-6));
  });

  testWidgets('a slightly shaky tap still only selects', (tester) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openDraw(tester);
    await _drawTriangle(tester);
    final first = _draftRing(h).first;

    final gesture = await tester.startGesture(
      tester.getCenter(_vertex(first.id)),
    );
    await gesture.moveBy(const Offset(2, 1));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(2, -1));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_draftRing(h).first.lon, first.lon);
    expect(find.text('V1'), findsOneWidget);
  });

  testWidgets('drag, insert at a midpoint, delete and undo', (tester) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openDraw(tester);
    await _drawTriangle(tester);
    final first = _draftRing(h).first;
    final centre = _camera(tester).center;

    // Dragging moves the vertex, shows the loupe (REG-10), not the map.
    final gesture = await tester.startGesture(
      tester.getCenter(_vertex(first.id)),
    );
    await gesture.moveBy(const Offset(10, 0));
    await gesture.moveBy(const Offset(30, -20));
    await tester.pump();
    expect(find.byType(RawMagnifier), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(RawMagnifier), findsNothing);
    final moved = _draftRing(h).first;
    expect(moved.id, first.id);
    expect(moved.lon, greaterThan(first.lon));
    expect(moved.lat, greaterThan(first.lat));
    expect(_camera(tester).center, centre);

    // One drag is one undo step (REG-5).
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(_draftRing(h).first.lon, first.lon);

    // The midpoint after the first vertex inserts a vertex there.
    await tester.tap(find.byKey(ValueKey('mid-${first.id}')));
    await tester.pumpAndSettle();
    final ring = _draftRing(h);
    expect(ring, hasLength(4));
    // Stored to 7 decimals (SPEC.md §7.1).
    expect(ring[1].lon, closeTo((ring[0].lon + ring[2].lon) / 2, 1e-7));

    // Long-press deletes.
    await tester.longPress(_vertex(ring[1].id));
    await tester.pumpAndSettle();
    expect(_draftRing(h), hasLength(3));

    // The toolbar deletes the selected vertex.
    await tester.tap(_vertex(ring[2].id));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete vertex'));
    await tester.pumpAndSettle();
    expect(_draftRing(h).map((v) => v.id), isNot(contains(ring[2].id)));
  });

  testWidgets('a vertex near a neighbour snaps to its corner (REG-7)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    // Where the draw map opens: the map tab's default view.
    h.properties.documents['p1'] = _neighbour(const [
      (39.6, -8.0),
      (39.6, -7.999),
      (39.601, -7.999),
    ]);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openDraw(tester);

    final camera = _camera(tester);
    final corner = camera.latLngToScreenOffset(const LatLng(39.6, -8));
    final mapTopLeft = tester.getTopLeft(find.byType(FlutterMap));
    await _tapMap(tester, mapTopLeft + corner + const Offset(6, -4));
    final snapped = _draftRing(h).single;
    expect((snapped.lat, snapped.lon), (39.6, -8.0));

    // Further away, no snapping.
    await _tapMap(tester, mapTopLeft + corner + const Offset(40, 30));
    expect(_draftRing(h).last.lat, isNot(39.6));
    expect(DrawMap.snapPixels, 10);
  });

  testWidgets('opens on the user’s position when it is known', (tester) async {
    final h = Harness(settings: onboarded);
    h.location.current = LocationAccess.granted;
    await h.pump(tester);
    await tester.pumpAndSettle();
    h.location.emit(
      LocationFix(
        lat: 41.15,
        lon: -8.61,
        accuracyMetres: 5,
        at: DateTime.utc(2026, 10, 25),
      ),
    );
    await tester.pumpAndSettle();
    await _openDraw(tester);
    expect(_camera(tester).center.latitude, closeTo(41.15, 1e-9));
    expect(_camera(tester).zoom, greaterThanOrEqualTo(16));
  });

  testWidgets('leaving with changes asks first', (tester) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openDraw(tester);
    await _drawTriangle(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard this boundary?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawMap), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawMap), findsNothing);
    expect(h.drafts.loadAll(), isEmpty);
  });

  testWidgets('the map and the vertex table are two views of one edit', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openDraw(tester);
    await _drawTriangle(tester);

    await tester.tap(find.byTooltip('Vertex list'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawMap), findsNothing);
    expect(find.text('V1'), findsOneWidget);
    await scrollToVertex(tester, 'V3');
    expect(find.text('V3'), findsOneWidget);
    expect(find.text('0/3 vertices surveyed'), findsOneWidget);

    await tester.tap(find.byTooltip('Draw on the map'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawMap), findsOneWidget);
  });

  group('resuming a draft on launch (REG-12)', () {
    BoundaryDraft draft(String? propertyId) => BoundaryDraft(
      propertyId: propertyId,
      parts: [
        [
          [
            for (final (i, (lat, lon)) in const [
              (39.6, -8.0),
              (39.6, -7.999),
              (39.601, -7.999),
              (39.601, -8.0),
            ].indexed)
              Vertex(id: 'd$i', lon: lon, lat: lat, source: VertexSource.map),
          ],
        ],
      ],
      updatedAt: DateTime.utc(2026, 10, 25),
    );

    testWidgets('a new property continues where it stopped', (tester) async {
      final h = Harness(settings: onboarded);
      await h.drafts.save(draft(null));
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('Unfinished boundary'), findsOneWidget);
      expect(find.textContaining('new property (4 vertices)'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(DrawMap), findsOneWidget);
      expect(find.byKey(const ValueKey('vertex-d3')), findsOneWidget);
      expect(find.textContaining('Area:'), findsOneWidget);
    });

    testWidgets('an edit resumes in that property’s editor', (tester) async {
      final h = Harness(settings: onboarded);
      h.properties.documents['p1'] = _neighbour(const [
        (39.6, -8.0),
        (39.6, -7.999),
        (39.601, -7.999),
      ]);
      await h.drafts.save(draft('p1'));
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('boundary of “Vizinho”'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Edit boundary'), findsOneWidget);
      // The draft's four vertices, not the saved three.
      await scrollToVertex(tester, 'V4');
      expect(find.text('V4'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        h.properties.documents['p1']!.geometry.current!.vertices,
        hasLength(4),
      );
      expect(h.drafts.loadAll(), isEmpty);
    });

    testWidgets('discarding deletes it', (tester) async {
      final h = Harness(settings: onboarded);
      await h.drafts.save(draft(null));
      await h.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(h.drafts.loadAll(), isEmpty);
      expect(find.byType(DrawMap), findsNothing);
    });

    testWidgets('a draft for a deleted property is dropped quietly', (
      tester,
    ) async {
      final h = Harness(settings: onboarded);
      await h.drafts.save(draft('gone'));
      await h.pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('Unfinished boundary'), findsNothing);
      expect(h.drafts.loadAll(), isEmpty);
    });
  });
}
