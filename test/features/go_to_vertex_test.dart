import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/features/vertices/go_to_vertex_page.dart';

import '../helpers/harness.dart';

/// V1, V2 and V3 typed at home, none surveyed yet.
PropertyDocument _planned() =>
    PropertyDocument.create(
      id: 'p1',
      name: 'Olival',
      timestamp: const Hlc(1, 0, 'dev'),
    ).withGeometry([
      [
        [
          for (final (id, lat, lon) in const [
            ('a', 40.2, -8.43),
            ('b', 40.2, -8.429),
            ('c', 40.201, -8.429),
          ])
            Vertex(id: id, lat: lat, lon: lon, source: VertexSource.typed),
        ],
      ],
    ], const Hlc(2, 0, 'dev'));

Future<Harness> _openEditor(WidgetTester tester) async {
  usePhoneScreen(tester);
  final h = Harness(settings: onboarded);
  h.properties.documents['p1'] = _planned();
  h.location.current = LocationAccess.granted;
  await h.pump(tester);
  await tester.pumpAndSettle();
  unawaited(
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .push(Routes.propertyBoundary('p1')),
  );
  await tester.pumpAndSettle();
  return h;
}

Future<void> _at(
  WidgetTester tester,
  Harness h,
  double lat,
  double lon, {
  double accuracy = 3,
}) async {
  h.location.emit(
    LocationFix(
      lat: lat,
      lon: lon,
      accuracyMetres: accuracy,
      at: DateTime.utc(2026, 10, 26, 12),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

double _arrow(WidgetTester tester) =>
    tester.widget<DirectionArrow>(find.byType(DirectionArrow)).degrees;

void main() {
  testWidgets('the next planned vertex leads there and buzzes on arrival', (
    tester,
  ) async {
    final h = await _openEditor(tester);
    await tester.tap(find.text('Survey next vertex (V1)'));
    await tester.pumpAndSettle();
    expect(find.text('Go to V1'), findsOneWidget);
    expect(find.text('Waiting for a GPS position…'), findsOneWidget);
    expect(h.compass.listening, isTrue);

    // 30 m south of V1, facing north: the arrow points straight ahead.
    h.compass.point(0);
    await _at(tester, h, 40.19973, -8.43);
    expect(find.text('30 m'), findsOneWidget);
    expect(find.text('to the north'), findsOneWidget);
    expect(_arrow(tester), closeTo(0, 0.5));
    // Turned to face east, the arrow points left.
    h.compass.point(90);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_arrow(tester), closeTo(-90, 0.5));
    expect(h.arrivalSignals, 0);

    // Within the ±3 m accuracy: one buzz, however much the GPS jitters.
    await _at(tester, h, 40.199985, -8.43);
    expect(find.text('You are at V1'), findsOneWidget);
    expect(h.arrivalSignals, 1);
    await _at(tester, h, 40.199992, -8.43);
    expect(h.arrivalSignals, 1);
    // Away and back again buzzes again.
    await _at(tester, h, 40.1999, -8.43);
    expect(find.text('You are at V1'), findsNothing);
    await _at(tester, h, 40.2, -8.43);
    expect(h.arrivalSignals, 2);

    // Survey from here; the result comes back to the editor.
    await tester.tap(find.widgetWithText(FilledButton, 'Survey V1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measure'));
    await tester.pump();
    for (var s = 0; s < 6; s++) {
      await _at(tester, h, 40.2, -8.43);
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    expect(find.text('V1 confirmed on site.'), findsOneWidget);
    expect(find.text('1/3 vertices surveyed'), findsOneWidget);
    expect(find.text('Survey next vertex (V2)'), findsOneWidget);
    expect(h.compass.listening, isFalse);
  });

  testWidgets('without a compass the arrow is relative to north', (
    tester,
  ) async {
    final h = await _openEditor(tester);
    await scrollToVertex(tester, 'V2');
    await tester.tap(find.text('V2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to vertex'));
    await tester.pumpAndSettle();
    expect(find.text('Go to V2'), findsOneWidget);

    // 50 m west of V2.
    await _at(tester, h, 40.2, -8.429588);
    expect(find.text('50 m'), findsOneWidget);
    expect(find.text('to the east'), findsOneWidget);
    expect(_arrow(tester), closeTo(90, 0.5));
    expect(find.textContaining('No compass'), findsOneWidget);

    // An unreliable compass asks for calibration.
    h.compass.point(0, accuracyDegrees: null);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('figure of eight'), findsOneWidget);
    h.compass.point(0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('figure of eight'), findsNothing);

    // Leaving changes nothing.
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('0/3 vertices surveyed'), findsOneWidget);
  });

  testWidgets('the next vertex follows the selected one, round the ring', (
    tester,
  ) async {
    await _openEditor(tester);
    await scrollToVertex(tester, 'V3');
    await tester.tap(find.text('V3'));
    await tester.pumpAndSettle();
    // Closing the sheet keeps V3 selected.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Survey next vertex (V1)'), findsOneWidget);
    await scrollToVertex(tester, 'V1');
    await tester.tap(find.text('V1'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Survey next vertex (V2)'), findsOneWidget);
  });

  testWidgets('not offered while drawing a new property', (tester) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Properties'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New property'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draw on the map'));
    await tester.pumpAndSettle();
    for (final offset in const [Offset(-60, 40), Offset(60, 40)]) {
      await tester.tapAt(tester.getCenter(find.byType(Scaffold).last) + offset);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('Survey next vertex'), findsNothing);
  });
}
