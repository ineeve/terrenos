import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';

import '../helpers/harness.dart';

Future<void> _openCoordinates(WidgetTester tester) async {
  await tester.tap(find.text('Properties'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('New property'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Type coordinates'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String a, String b) async {
  await tester.tap(find.text('Add vertex').last);
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), a);
  await tester.enterText(fields.at(1), b);
  await tester.pump();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

Iterable<Polyline> _red(WidgetTester tester) => tester
    .widgetList<PolylineLayer>(find.byType(PolylineLayer))
    .expand((l) => l.polylines)
    .where((p) => p.color == Colors.redAccent);

PropertyDocument _property(List<Vertex> ring, {String name = 'Grande'}) =>
    PropertyDocument.create(
      id: 'p1',
      name: name,
      timestamp: const Hlc(1, 0, 'dev'),
    ).withGeometry([
      [ring],
    ], const Hlc(2, 0, 'dev'));

void main() {
  testWidgets('VAL-2: crossing edges turn red after a blocked save', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openCoordinates(tester);
    // A bow-tie.
    for (final (a, b) in const [
      ('40.2000', '-8.4300'),
      ('40.2010', '-8.4290'),
      ('40.2000', '-8.4290'),
      ('40.2010', '-8.4300'),
    ]) {
      await _type(tester, a, b);
    }
    expect(_red(tester), isEmpty);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Can’t continue'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_red(tester), hasLength(2));

    // Any change clears the highlight.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(_red(tester), isEmpty);
  });

  testWidgets('VAL-6: swapped coordinates can be swapped back', (tester) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openCoordinates(tester);
    // Longitude typed as latitude and the other way round.
    for (final (lat, lon) in const [
      ('40.2000', '-8.4300'),
      ('40.2000', '-8.4290'),
      ('40.2010', '-8.4290'),
      ('40.2010', '-8.4300'),
    ]) {
      await _type(tester, lon, lat);
    }

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Check before continuing'), findsOneWidget);
    await tester.tap(find.text('Swap the coordinates'));
    await tester.pumpAndSettle();

    // Swapped and checked again: nothing left to warn about.
    expect(find.text('Property details'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Lat 40,20').evaluate().isEmpty, isTrue);
    expect(find.textContaining('Lat 40.2000000'), findsNWidgets(2));
  });

  testWidgets('VAL-9: too many vertices can be simplified', (tester) async {
    final h = Harness(settings: onboarded);
    // 5 001 vertices on a circle about 500 m across.
    const n = TooManyVertices.max + 1;
    h.properties.documents['p1'] = _property([
      for (var i = 0; i < n; i++)
        Vertex(
          id: 'c$i',
          lon: -8.43 + 0.003 * cos(2 * pi * i / n),
          lat: 40.2 + 0.0023 * sin(2 * pi * i / n),
          source: VertexSource.typed,
        ),
    ]);
    await h.pump(tester);
    await tester.pumpAndSettle();
    unawaited(
      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .push(Routes.propertyBoundary('p1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Too many vertices'), findsOneWidget);
    await tester.tap(find.text('Simplify'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Simplified to '), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = h.properties.documents['p1']!.geometry.current!.vertices;
    expect(saved.length, lessThanOrEqualTo(TooManyVertices.max));
    expect(saved.length, greaterThan(100));
  });

  testWidgets('VAL-8: imprecise GPS vertices are marked', (tester) async {
    final h = Harness(settings: onboarded);
    GpsFix fix(double accuracy) => GpsFix(
      accuracyMetres: accuracy,
      samples: 5,
      capturedAt: DateTime.utc(2026),
      mocked: false,
      deviceId: 'dev',
    );
    h.properties.documents['p1'] = _property(name: 'Olival', [
      for (final (i, (lat, lon, accuracy)) in const [
        (40.2000, -8.4300, 4.0),
        (40.2000, -8.4290, 25.0),
        (40.2010, -8.4290, 3.0),
      ].indexed)
        Vertex(
          id: 'g$i',
          lon: lon,
          lat: lat,
          source: VertexSource.gps,
          gps: fix(accuracy),
        ),
    ]);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Properties'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Olival'));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Low confidence: imprecise or simulated GPS'),
      findsOneWidget,
    );
  });
}
