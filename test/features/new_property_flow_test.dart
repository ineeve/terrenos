import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/crs/coordinates.dart';
import 'package:terrenos/core/crs/pt_tm06.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/settings/app_settings.dart';

import '../helpers/harness.dart';

/// Four corners of a ~85 m × 111 m parcel near Coimbra, in PT-TM06 as they
/// would appear on a survey plan.
final List<PtTm06Point> _corners = [
  for (final (lat, lon) in [
    (40.2000, -8.4300),
    (40.2000, -8.4290),
    (40.2010, -8.4290),
    (40.2010, -8.4300),
  ])
    PtTm06.fromLatLon(lat, lon),
];

String _metres(double v) => v.toStringAsFixed(2);

Future<void> _openNewPropertyByCoordinates(WidgetTester tester) async {
  await tester.tap(find.text('Properties'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('New property'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Type coordinates'));
  await tester.pumpAndSettle();
}

Future<void> _typeVertex(WidgetTester tester, String a, String b) async {
  await tester.tap(find.text('Add vertex').last);
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), a);
  await tester.enterText(fields.at(1), b);
  await tester.pump();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'AC12: a property typed from PT-TM06 coordinates keeps the typed values',
    (tester) async {
      final h = Harness(
        settings: onboarded.copyWith(coordinateFormat: CoordinateFormat.ptTm06),
      );
      await h.pump(tester);
      await tester.pumpAndSettle();

      await _openNewPropertyByCoordinates(tester);
      expect(find.text('Add at least 3 vertices.'), findsOneWidget);

      for (final c in _corners) {
        await _typeVertex(tester, _metres(c.m), _metres(c.p));
      }

      expect(find.textContaining('Area:'), findsOneWidget);
      expect(find.textContaining('ha ('), findsOneWidget);
      expect(find.text('0/4 vertices surveyed'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Property details'), findsOneWidget);

      // Required fields block saving.
      await tester.tap(find.text('Save property'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Olival do Ribeiro',
      );
      await tester.enterText(find.byType(TextFormField).at(1), ' 0012/2023-A ');
      await tester.tap(find.text('Property type *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rustic').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Land use *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Olive grove').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save property'));
      await tester.pumpAndSettle();

      // The detail page shows the new property.
      expect(find.widgetWithText(AppBar, 'Olival do Ribeiro'), findsOneWidget);
      expect(find.text('Proc. no. 0012/2023-A'), findsOneWidget);
      expect(find.text('Rustic · Olive grove'), findsOneWidget);

      final saved = h.properties.documents.values.single;
      expect(saved.name, 'Olival do Ribeiro');
      expect(saved.processNumber, '0012/2023-A');
      expect(saved.field(PropertyField.landUse), 'olive_grove');
      final vertices = saved.geometry.current!.vertices.toList();
      expect(vertices, hasLength(4));
      expect(vertices.every((v) => v.source == VertexSource.typed), isTrue);
      expect(vertices.first.input!.crs, 'EPSG:3763');
      expect(vertices.first.input!.x, double.parse(_metres(_corners.first.m)));

      // The vertex table shows the typed M value exactly.
      expect(
        find.textContaining('M ${formatMetres(_corners.first.m, 'en')}'),
        findsOneWidget,
      );

      // Back in the list, the property is found by its process number.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Olival do Ribeiro'), findsOneWidget);
      await tester.enterText(find.byType(SearchBar), '0012 2023 a');
      await tester.pumpAndSettle();
      expect(find.text('Olival do Ribeiro'), findsOneWidget);
      await tester.enterText(find.byType(SearchBar), 'vinha');
      await tester.pumpAndSettle();
      expect(find.text('No properties match your search.'), findsOneWidget);
    },
  );

  testWidgets('VAL-7: overlapping another property warns with the area', (
    tester,
  ) async {
    final h = Harness(
      settings: onboarded.copyWith(coordinateFormat: CoordinateFormat.ptTm06),
    );
    final existing =
        PropertyDocument.create(
          id: 'p1',
          name: 'Olival',
          timestamp: const Hlc(1, 0, 'dev'),
        ).withGeometry([
          [
            [
              for (final (i, (lat, lon)) in const [
                (40.2000, -8.4300),
                (40.2000, -8.4290),
                (40.2010, -8.4290),
                (40.2010, -8.4300),
              ].indexed)
                Vertex(
                  id: 'o$i',
                  lon: lon,
                  lat: lat,
                  source: VertexSource.typed,
                ),
            ],
          ],
        ], const Hlc(2, 0, 'dev'));
    h.properties.documents['p1'] = existing;
    await h.pump(tester);
    await tester.pumpAndSettle();

    await _openNewPropertyByCoordinates(tester);
    for (final c in _corners) {
      await _typeVertex(tester, _metres(c.m), _metres(c.p));
    }
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Check before continuing'), findsOneWidget);
    // The same corners, typed to the centimetre: about 9 475 m².
    expect(
      find.textContaining(RegExp(r'Overlaps “Olival” by 9,4\d\d m²\.')),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Property details'), findsOneWidget);
  });

  testWidgets('a positive longitude offers the negative one (§7.5)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openNewPropertyByCoordinates(tester);

    await tester.tap(find.text('Add vertex').last);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '40,2');
    await tester.enterText(fields.at(1), '8,43');
    await tester.pump();
    expect(
      find.text('This point is outside mainland Portugal.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Use -8.4300000 (west)'));
    await tester.pump();
    expect(find.text('This point is outside mainland Portugal.'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lon -8.4300000'), findsOneWidget);
  });

  testWidgets('invalid input shows inline errors and is not saved', (
    tester,
  ) async {
    final h = Harness(
      settings: onboarded.copyWith(
        coordinateFormat: CoordinateFormat.degreesMinutesSeconds,
      ),
    );
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openNewPropertyByCoordinates(tester);

    await tester.tap(find.text('Add vertex').last);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '40 75 0 N');
    await tester.enterText(fields.at(1), '8 25 48 N');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Minutes and seconds must be below 60.'), findsOneWidget);
    expect(
      find.text('Wrong hemisphere letter for this value.'),
      findsOneWidget,
    );
    expect(find.text('Add vertex'), findsOneWidget); // still on the form
  });

  testWidgets('a crossing boundary cannot continue; undo fixes it', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openNewPropertyByCoordinates(tester);

    // A bow-tie: corners in the wrong order.
    for (final (lat, lon) in [
      ('40.2000', '-8.4300'),
      ('40.2010', '-8.4290'),
      ('40.2000', '-8.4290'),
      ('40.2010', '-8.4300'),
    ]) {
      await _typeVertex(tester, lat, lon);
    }
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Can’t continue'), findsOneWidget);
    expect(
      find.text('• Some edges of the boundary cross each other.'),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Delete the last vertex, then undo the deletion.
    await scrollToVertex(tester, 'V4');
    await tester.pumpAndSettle();
    await tester.tap(find.text('V4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('V4'), findsNothing);
    expect(find.text('V3'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('V4'), findsOneWidget);
  });
}
