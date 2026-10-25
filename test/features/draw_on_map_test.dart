import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/features/editor/draw_on_map_page.dart';

import '../helpers/harness.dart';

final _neighbour = Vertex(
  id: 'n1',
  lon: -8.4290,
  lat: 40.2000,
  source: VertexSource.gps,
);

PropertyDocument _vizinho() {
  const t = Hlc(1, 0, 'dev');
  return PropertyDocument.create(
    id: 'p1',
    name: 'Vizinho',
    timestamp: t,
  ).withGeometry([
    [
      [
        Vertex(id: 'n0', lon: -8.4300, lat: 40.2000, source: VertexSource.gps),
        _neighbour,
        Vertex(id: 'n2', lon: -8.4290, lat: 40.2010, source: VertexSource.gps),
      ],
    ],
  ], t);
}

MapController _controller(WidgetTester tester) => tester
    .widget<FlutterMap>(
      find.descendant(
        of: find.byType(DrawOnMapPage),
        matching: find.byType(FlutterMap),
      ),
    )
    .mapController!;

/// Global screen position of a map coordinate.
Offset _onScreen(WidgetTester tester, double lat, double lon) {
  final map = find.descendant(
    of: find.byType(DrawOnMapPage),
    matching: find.byType(FlutterMap),
  );
  final local = _controller(tester).camera
      .latLngToScreenOffset(LatLng(lat, lon));
  return tester.getTopLeft(map) + local;
}

/// flutter_map waits to rule out a double tap before reporting a tap.
Future<void> _tapMap(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openDrawing(WidgetTester tester) async {
  await tester.tap(find.text('Properties'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('New property'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Draw on the map'));
  await tester.pumpAndSettle();
  expect(find.byType(DrawOnMapPage), findsOneWidget);

  // Go to the neighbouring property using the map search.
  await tester.tap(find.byTooltip('Search places and properties'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'vizinho');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Vizinho'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('drawing adds vertices and snaps to neighbours (REG-1, REG-7)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    h.properties.documents['p1'] = _vizinho();
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openDrawing(tester);
    expect(_controller(tester).camera.zoom, greaterThan(15));

    // A tap 5 px from the neighbour's corner snaps onto it exactly.
    await _tapMap(
      tester,
      _onScreen(tester, _neighbour.lat, _neighbour.lon) + const Offset(4, 3),
    );
    // Two more vertices, away from the neighbour's corners, don't snap.
    await _tapMap(tester, _onScreen(tester, 40.2003, -8.4282));
    await _tapMap(tester, _onScreen(tester, 40.2007, -8.4302));
    expect(find.textContaining('Area:'), findsOneWidget);

    // The crosshair adds a fourth vertex at the map centre.
    await tester.tap(find.text('Add here'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('V4'), findsOneWidget);

    final draft = h.drafts.drafts.values.single;
    final vertices = draft.parts.single.single;
    expect(vertices, hasLength(4));
    expect(
      (vertices[0].lon, vertices[0].lat),
      (_neighbour.lon, _neighbour.lat),
    );
    expect(vertices[1].lon, isNot(_neighbour.lon));
    expect(vertices.every((v) => v.source == VertexSource.map), isTrue);
  });

  testWidgets('a selected vertex can be moved to the crosshair or deleted', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    h.properties.documents['p1'] = _vizinho();
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openDrawing(tester);

    await _tapMap(tester, _onScreen(tester, 40.2003, -8.4282));
    await _tapMap(tester, _onScreen(tester, 40.2007, -8.4302));

    // Select V1 (this also centres the map on it), then pan and move it.
    await tester.tap(find.bySemanticsLabel('V1'));
    await tester.pumpAndSettle();
    final before = h.drafts.drafts.values.single.parts.single.single.first;
    await tester.drag(
      find.descendant(
        of: find.byType(DrawOnMapPage),
        matching: find.byType(FlutterMap),
      ),
      const Offset(-60, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move here'));
    await tester.pumpAndSettle();
    final moved = h.drafts.drafts.values.single.parts.single.single.first;
    expect(moved.id, before.id);
    expect(moved.lon, greaterThan(before.lon));

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(h.drafts.drafts.values.single.parts.single.single, hasLength(1));

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(h.drafts.drafts.values.single.parts.single.single, hasLength(2));
  });
}
