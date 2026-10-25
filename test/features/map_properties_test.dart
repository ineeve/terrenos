import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/features/map/map_page.dart';

import '../helpers/harness.dart';

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
              Vertex(
                id: 'a',
                lon: -8.43,
                lat: 40.2,
                source: VertexSource.typed,
              ),
              Vertex(
                id: 'b',
                lon: -8.429,
                lat: 40.2,
                source: VertexSource.typed,
              ),
              Vertex(
                id: 'c',
                lon: -8.429,
                lat: 40.201,
                source: VertexSource.typed,
              ),
              Vertex(
                id: 'd',
                lon: -8.43,
                lat: 40.201,
                source: VertexSource.typed,
              ),
            ],
          ],
        ], const Hlc(3, 0, 'dev'));

void main() {
  testWidgets('properties are drawn on the map with their names (MAP-5)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    h.properties.documents['p1'] = _olival();
    await h.pump(tester);
    await tester.pumpAndSettle();

    final layer = tester.widget<PolygonLayer<String>>(
      find.byType(PolygonLayer<String>),
    );
    expect(layer.polygons, hasLength(1));
    expect(layer.polygons.single.label, 'Olival do Ribeiro');
    expect(layer.polygons.single.hitValue, 'p1');
    expect(layer.polygons.single.points, hasLength(4));
  });

  testWidgets('the summary opens the property details (MAP-6)', (tester) async {
    final h = Harness(settings: onboarded);
    h.properties.documents['p1'] = _olival();
    await h.pump(tester);
    await tester.pumpAndSettle();

    // The sheet's future completes only when it closes, so don't await it.
    unawaited(
      showPropertySummary(tester.element(find.byType(PropertiesLayer)), 'p1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Olival do Ribeiro'), findsOneWidget);
    expect(find.text('Proc. no. 0012/2023-A'), findsOneWidget);
    expect(find.textContaining('ha ('), findsOneWidget);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Olival do Ribeiro'), findsOneWidget);
    expect(find.text('V1'), findsOneWidget);
  });

  testWidgets('deleting from the detail page can be undone (MGT-3)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    h.properties.documents['p1'] = _olival();
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Properties'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Olival do Ribeiro'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Property moved to the recycle bin.'), findsOneWidget);
    expect(h.properties.documents['p1']!.isDeleted, isTrue);
    expect(find.text('Olival do Ribeiro'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(h.properties.documents['p1']!.isDeleted, isFalse);
    expect(find.text('Olival do Ribeiro'), findsOneWidget);
  });
}
