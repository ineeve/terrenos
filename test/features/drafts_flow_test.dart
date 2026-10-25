import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/editing/drafts.dart';
import 'package:terrenos/core/model/vertex.dart';

import '../helpers/harness.dart';

Future<void> _startNewProperty(WidgetTester tester) async {
  await tester.tap(find.text('Properties'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('New property'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Type coordinates'));
  await tester.pumpAndSettle();
}

Future<void> _typeVertex(WidgetTester tester, String lat, String lon) async {
  await tester.tap(find.text('Add vertex').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), lat);
  await tester.enterText(find.byType(TextField).at(1), lon);
  await tester.pump();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every edit is saved as a draft; leaving asks first (REG-12)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _startNewProperty(tester);

    await _typeVertex(tester, '40.2', '-8.43');
    expect(h.drafts.drafts.values.single.vertexCount, 1);
    await _typeVertex(tester, '40.2', '-8.429');
    expect(h.drafts.drafts.values.single.vertexCount, 2);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard this boundary?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('V2'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(h.drafts.drafts, isEmpty);
    expect(find.text('Properties'), findsWidgets);
  });

  testWidgets('a draft left by a crash is offered, resumed and cleared', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    h.drafts.drafts['d1'] = BoundaryDraft(
      id: 'd1',
      updatedAt: DateTime.utc(2026, 10, 25),
      parts: [
        [
          [
            for (final (i, (lon, lat)) in [
              (-8.43, 40.2),
              (-8.429, 40.2),
              (-8.429, 40.201),
            ].indexed)
              Vertex(id: 'v$i', lon: lon, lat: lat, source: VertexSource.typed),
          ],
        ],
      ],
    );
    await h.pump(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('You have an unfinished boundary (3 vertices).'),
      findsOneWidget,
    );
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(find.text('New property'), findsOneWidget);
    expect(find.text('V3'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Retomado');
    await tester.tap(find.text('Property type *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rustic').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Land use *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pasture').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save property'));
    await tester.pumpAndSettle();

    expect(h.properties.documents.values.single.name, 'Retomado');
    expect(h.drafts.drafts, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('unfinished boundary'), findsNothing);
  });

  testWidgets('a draft can be discarded from the banner', (tester) async {
    final h = Harness(settings: onboarded);
    h.drafts.drafts['d1'] = BoundaryDraft(
      id: 'd1',
      updatedAt: DateTime.utc(2026),
      parts: const [
        [[]],
      ],
    );
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(h.drafts.drafts, isEmpty);
    expect(find.textContaining('unfinished boundary'), findsNothing);
  });
}
