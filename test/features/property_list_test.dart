import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/property_kinds.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/properties/property_query.dart';

import '../helpers/harness.dart';

PropertyDocument _doc(
  String id,
  String name, {
  double size = 1,
  String? number,
  PropertyType type = PropertyType.rustico,
  LandUse use = LandUse.oliveGrove,
  Hlc? deletedAt,
}) {
  var doc = PropertyDocument.create(
    id: id,
    name: name,
    timestamp: const Hlc(1, 0, 'dev'),
  );
  for (final MapEntry(:key, :value) in {
    PropertyField.processNumber: ?number,
    PropertyField.type: type.name,
    PropertyField.landUse: use.code,
  }.entries) {
    doc = doc.withField(key, value, const Hlc(2, 0, 'dev'));
  }
  final d = size / 1000;
  doc = doc.withGeometry([
    [
      [
        for (final (i, (x, y)) in [(0, 0), (d, 0), (d, d), (0, d)].indexed)
          Vertex(
            id: '$id$i',
            lon: -8.43 + x,
            lat: 40.2 + y,
            source: VertexSource.typed,
          ),
      ],
    ],
  ], const Hlc(3, 0, 'dev'));
  if (deletedAt != null) {
    doc = doc.withDeleted(deleted: true, timestamp: deletedAt);
  }
  return doc;
}

Future<void> _openList(WidgetTester tester) async {
  await tester.tap(find.text('Properties'));
  await tester.pumpAndSettle();
}

List<String> _listed(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
    if (tile.title case Text(:final data?)) data,
];

void main() {
  late AdminBoundaries caop;

  setUpAll(() {
    caop = AdminBoundaries.parse(File(caopAsset).readAsStringSync());
  });

  group('details form (T1.9)', () {
    Future<void> newPropertyByCoordinates(WidgetTester tester) async {
      await _openList(tester);
      await tester.tap(find.byTooltip('New property'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type coordinates'));
      await tester.pumpAndSettle();
      for (final (lat, lon) in const [
        ('40.2000', '-8.4300'),
        ('40.2000', '-8.4290'),
        ('40.2010', '-8.4290'),
        ('40.2010', '-8.4300'),
      ]) {
        await tester.tap(find.text('Add vertex').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), lat);
        await tester.enterText(find.byType(TextField).at(1), lon);
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // VAL-7 when it overlaps a property the test set up.
      if (find.text('Continue anyway').evaluate().isNotEmpty) {
        await tester.tap(find.text('Continue anyway'));
        await tester.pumpAndSettle();
      }
    }

    Future<void> chooseRequired(WidgetTester tester) async {
      await tester.tap(find.text('Property type *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rustic').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Land use *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Olive grove').last);
      await tester.pumpAndSettle();
    }

    testWidgets('location comes from the map; Registo is optional', (
      tester,
    ) async {
      final h = Harness(settings: onboarded, caop: caop);
      await h.pump(tester);
      await tester.pumpAndSettle();
      await newPropertyByCoordinates(tester);

      // PROP-9: filled in from CAOP, still editable.
      expect(find.text('Filled in from the map (CAOP)'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Coimbra'),
        findsNWidgets(2), // concelho and distrito
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'Olival');
      await chooseRequired(tester);
      // D16: the official references are optional and collapsed.
      expect(find.text('Matrix article (artigo matricial)'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Registry references (optional)'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(Form),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // Clear of the Save button at the bottom.
      await tester.drag(find.byType(Form), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registry references (optional)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Matrix article (artigo matricial)'),
        ' 1234 ',
      );
      await tester.tap(find.text('Save property'));
      await tester.pumpAndSettle();

      final saved = h.properties.documents.values.single;
      final location = locationOf(saved)!;
      expect(location.concelho, 'Coimbra');
      expect(location.dicofre, startsWith('0603'));
      expect(saved.field(PropertyField.matrixArticle), '1234');
      // Empty optional fields aren't stored.
      expect(saved.fields.containsKey(PropertyField.cadastralSection), isFalse);
      expect(saved.processNumber, isNull);

      // The detail page shows them.
      expect(find.text('Matrix article (artigo matricial)'), findsOneWidget);
      expect(find.text('1234'), findsOneWidget);
      expect(find.text('Concelho'), findsOneWidget);
    });

    testWidgets('details can be edited later (IDN-8)', (tester) async {
      final h = Harness(settings: onboarded, caop: caop);
      h.properties.documents['p1'] = _doc('p1', 'Olival', number: '0012');
      await h.pump(tester);
      await tester.pumpAndSettle();
      await _openList(tester);
      await tester.tap(find.text('Olival'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit details'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Olival'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '0012'), findsOneWidget);
      // An older property gets its location filled in too.
      expect(find.text('Filled in from the map (CAOP)'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Olival Novo');
      await tester.enterText(find.byType(TextFormField).at(1), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final doc = h.properties.documents['p1']!;
      expect(doc.name, 'Olival Novo');
      expect(doc.processNumber, isNull);
      expect(locationOf(doc)!.concelho, 'Coimbra');
      expect(find.widgetWithText(AppBar, 'Olival Novo'), findsOneWidget);
    });

    testWidgets(
      'a repeated process number warns and offers the other (IDN-4)',
      (tester) async {
        final h = Harness(settings: onboarded);
        h.properties.documents['p1'] = _doc(
          'p1',
          'Olival',
          number: '0012/2023-A',
        );
        await h.pump(tester);
        await tester.pumpAndSettle();
        await newPropertyByCoordinates(tester);

        await tester.enterText(find.byType(TextFormField).at(0), 'Vinha');
        await tester.enterText(find.byType(TextFormField).at(1), '0012 2023 a');
        await chooseRequired(tester);
        await tester.tap(find.text('Save property'));
        await tester.pumpAndSettle();
        expect(find.text('Process number already used'), findsOneWidget);

        await tester.tap(find.text('Open “Olival”'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, 'Olival'), findsOneWidget);
        expect(h.properties.documents, hasLength(1));

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save property'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save anyway'));
        await tester.pumpAndSettle();
        expect(h.properties.documents, hasLength(2));
      },
    );
  });

  group('list (T1.10)', () {
    testWidgets('sorts, filters and totals what it shows (MGT-1, MGT-2)', (
      tester,
    ) async {
      final h = Harness(settings: onboarded);
      h.properties.documents
        ..['a'] = _doc('a', 'Olival', size: 2, number: '1')
        ..['b'] = _doc(
          'b',
          'Casa',
          type: PropertyType.urbano,
          use: LandUse.builtUp,
        )
        ..['c'] = _doc('c', 'Vinha', size: 3, use: LandUse.vineyard);
      await h.pump(tester);
      await tester.pumpAndSettle();
      await _openList(tester);
      expect(_listed(tester), ['Casa', 'Olival', 'Vinha']);
      expect(find.textContaining('3 properties · '), findsOneWidget);

      await tester.tap(find.byTooltip('Sort by'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<PropertySort>,
          'Area, largest first',
        ),
      );
      await tester.pumpAndSettle();
      expect(_listed(tester), ['Vinha', 'Olival', 'Casa']);

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Rustic'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('With'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('With'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Filters').last)).pop();
      await tester.pumpAndSettle();

      expect(_listed(tester), ['Olival']);
      expect(find.textContaining('1 property · '), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // the filter badge

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(_listed(tester), ['Vinha', 'Olival', 'Casa']);
    });

    testWidgets('the recycle bin restores for 30 days (MGT-3)', (tester) async {
      final h = Harness(settings: onboarded);
      final now = DateTime.now().millisecondsSinceEpoch;
      const day = 24 * 60 * 60 * 1000;
      h.properties.documents
        ..['a'] = _doc('a', 'Olival')
        ..['b'] = _doc('b', 'Horta', deletedAt: Hlc(now - 2 * day, 0, 'dev'))
        ..['c'] = _doc('c', 'Pinhal', deletedAt: Hlc(now - 31 * day, 0, 'dev'));
      await h.pump(tester);
      await tester.pumpAndSettle();
      await _openList(tester);
      expect(_listed(tester), ['Olival']);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recycle bin'));
      await tester.pumpAndSettle();
      expect(find.text('Horta'), findsOneWidget);
      expect(find.text('28 days left to restore'), findsOneWidget);
      // Past 30 days it stays a tombstone, out of the list.
      expect(find.text('Pinhal'), findsNothing);

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(find.text('Property restored.'), findsOneWidget);
      expect(h.properties.documents['b']!.isDeleted, isFalse);
      expect(find.textContaining('Nothing here'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_listed(tester), ['Horta', 'Olival']);
    });
  });
}
