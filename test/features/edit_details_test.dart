import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';

import '../helpers/harness.dart';

PropertyDocument _olival() {
  const t = Hlc(1, 0, 'dev');
  return PropertyDocument.create(id: 'p1', name: 'Olival', timestamp: t)
      .withField(PropertyField.type, 'rustico', t)
      .withField(PropertyField.landUse, 'olive_grove', t)
      .withField(PropertyField.location, {
        'distrito': 'Coimbra',
        'concelho': 'Coimbra',
        'freguesia': 'Santa Clara e Castelo Viegas',
        'auto': true,
      }, t)
      .withGeometry([
        [
          [
            Vertex(id: 'a', lon: -8.43, lat: 40.2, source: VertexSource.typed),
            Vertex(id: 'b', lon: -8.429, lat: 40.2, source: VertexSource.typed),
            Vertex(
              id: 'c',
              lon: -8.429,
              lat: 40.201,
              source: VertexSource.typed,
            ),
          ],
        ],
      ], t);
}

Future<void> _openSection(WidgetTester tester, String title) async {
  // The form is a lazy list: scroll until the section is built.
  await tester.scrollUntilVisible(
    find.text(title),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

void main() {
  testWidgets('details can be edited after saving (IDN-8, §3.6)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    h.properties.documents['p1'] = _olival();
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Properties'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Olival'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit details'));
    await tester.pumpAndSettle();
    expect(find.text('Edit details'), findsOneWidget);

    await _enter(tester, 'Identifier name *', 'Olival do Ribeiro');
    await _enter(tester, 'Process number', '000123/A');

    await _openSection(tester, 'Location');
    expect(
      find.text(
        'Filled in from the official boundaries (CAOP). You can change it.',
      ),
      findsOneWidget,
    );
    await _enter(tester, 'Place name (lugar / sítio)', 'Vale da Fonte');
    await _enter(tester, 'Parish', 'Castelo Viegas');

    await _openSection(tester, 'Official references');
    await _enter(tester, 'Matrix article (artigo matricial)', '1234');

    await _openSection(tester, 'Neighbouring properties');
    await _enter(tester, 'North', 'Caminho público');
    await _enter(tester, 'West (Poente)', 'Herdeiros de A. Costa');

    await _openSection(tester, 'Owners');
    await tester.tap(find.text('Add owner'));
    await tester.pumpAndSettle();
    await _enter(tester, 'Owner’s name', 'Maria Fernandes');
    await _enter(tester, 'Share (%)', '150');

    // An invalid share blocks saving.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a percentage from 0 to 100.'), findsOneWidget);
    await _enter(tester, 'Share (%)', '50,5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final doc = h.properties.documents['p1']!;
    expect(doc.name, 'Olival do Ribeiro');
    expect(doc.processNumber, '000123/A');
    expect(doc.field(PropertyField.placeName), 'Vale da Fonte');
    expect(doc.field(PropertyField.matrixArticle), '1234');
    expect(doc.field(PropertyField.confrontations), {
      'n': 'Caminho público',
      'w': 'Herdeiros de A. Costa',
    });
    expect(doc.field(PropertyField.owners), [
      {'name': 'Maria Fernandes', 'share': 50.5},
    ]);
    // Editing the location by hand stops automatic updates (PROP-9).
    expect(doc.field(PropertyField.location), {
      'distrito': 'Coimbra',
      'concelho': 'Coimbra',
      'freguesia': 'Castelo Viegas',
      'auto': false,
    });
    expect(doc.field(PropertyField.type), 'rustico');

    // Back on the detail page, the new values are shown.
    expect(find.widgetWithText(AppBar, 'Olival do Ribeiro'), findsOneWidget);
    expect(find.text('Castelo Viegas, Coimbra (Coimbra)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Caminho público'), 200);
    expect(find.text('Maria Fernandes (50.5 %)'), findsOneWidget);
    expect(find.text('Vale da Fonte'), findsOneWidget);
  });

  testWidgets('clearing an optional field removes it', (tester) async {
    final h = Harness(settings: onboarded);
    h.properties.documents['p1'] = _olival().withField(
      PropertyField.notes,
      'Old note',
      const Hlc(2, 0, 'dev'),
    );
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Properties'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Olival'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit details'));
    await tester.pumpAndSettle();

    await _openSection(tester, 'Other');
    await _enter(tester, 'Notes', '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(h.properties.documents['p1']!.field(PropertyField.notes), isNull);
  });
}
