import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/location/location_source.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';

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

Future<Harness> _openSurvey(
  WidgetTester tester, {
  Locale phone = const Locale('en'),
  LocationAccess access = LocationAccess.granted,
}) async {
  final h = Harness(settings: onboarded);
  h.properties.documents['p1'] = _planned();
  h.location
    ..current = access
    ..afterRequest = access;
  await h.pump(tester, phone: phone);
  await tester.pumpAndSettle();
  unawaited(
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .push(Routes.propertyBoundary('p1')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('V2'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(
      phone.languageCode == 'pt' ? 'Levantar no local' : 'Survey on site',
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

/// Taps Measure and stands still for the 5 s average, one fix a second.
Future<void> _measure(
  WidgetTester tester,
  Harness h,
  double lat,
  double lon, {
  double accuracy = 3,
  bool mocked = false,
  String button = 'Measure',
}) async {
  await tester.tap(find.text(button));
  await tester.pump();
  for (var s = 0; s < 6; s++) {
    h.location.emit(
      LocationFix(
        lat: lat,
        lon: lon,
        accuracyMetres: accuracy,
        at: DateTime.utc(2026, 10, 26, 12),
        mocked: mocked,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpAndSettle();
}

Vertex _savedV2(Harness h) =>
    h.properties.documents['p1']!.geometry.current!.vertices.elementAt(1);

void main() {
  testWidgets('keep confirms the vertex where it is (VTX-9)', (tester) async {
    final h = await _openSurvey(tester);
    expect(find.text('Survey V2'), findsOneWidget);
    // Recording runs with the notice, as in walk mode (REG-13).
    expect(h.location.notice, isNotNull);

    // 2 m north of the stored position, with ±3 m accuracy.
    await _measure(tester, h, 40.200018, -8.429);
    expect(
      find.text(
        'Measured 2.0 m to the north of the stored position · accuracy ±3 m',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('keeping the stored position'), findsOne);
    // The suggestion is the filled button (§7.3).
    expect(find.widgetWithText(FilledButton, 'Keep'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Replace'), findsOneWidget);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text('V2 confirmed on site.'), findsOneWidget);
    expect(find.text('1/3 vertices surveyed'), findsOneWidget);
    expect(h.location.notice, isNull);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final v2 = _savedV2(h);
    expect((v2.id, v2.lat, v2.lon), ('b', 40.2, -8.429));
    expect(v2.source, VertexSource.typed);
    expect(v2.isSurveyed, isTrue);
    expect(v2.gps!.accuracyMetres, 3);
    expect(v2.gps!.deviceId, h.device.identity.deviceId);
  });

  testWidgets('replace moves it and keeps the old position in the history', (
    tester,
  ) async {
    final h = await _openSurvey(tester);
    // About 10 m north-east: further than the accuracy.
    await _measure(tester, h, 40.2000636, -8.4289169);
    expect(
      find.text(
        'Measured 10.0 m to the north-east of the stored position · '
        'accuracy ±3 m',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('replacing is suggested'), findsOne);
    expect(find.widgetWithText(FilledButton, 'Replace'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Measured position',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(find.textContaining('V2 moved to the measured'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final doc = h.properties.documents['p1']!;
    final v2 = _savedV2(h);
    expect((v2.id, v2.lat, v2.lon), ('b', 40.2000636, -8.4289169));
    expect(v2.source, VertexSource.gps);
    expect(v2.isSurveyed, isTrue);
    // The typed position is still in the earlier version (VTX-9).
    expect(doc.geometry.versions, hasLength(2));
    final earlier = doc.geometry.versions.values.firstWhere(
      (v) => v.hash != doc.geometry.current!.hash,
    );
    final old = earlier.vertices.firstWhere((v) => v.id == 'b');
    expect((old.lat, old.lon, old.isSurveyed), (40.2, -8.429, false));
  });

  testWidgets('repeat measures again', (tester) async {
    final h = await _openSurvey(tester);
    await _measure(tester, h, 40.2000636, -8.4289169);
    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();
    expect(find.text('Measure'), findsOneWidget);
    expect(find.text('Keep'), findsNothing);

    await _measure(tester, h, 40.2, -8.429);
    expect(
      find.text('Measured at the stored position · accuracy ±3 m'),
      findsOneWidget,
    );
  });

  testWidgets('a simulated or imprecise position is warned about', (
    tester,
  ) async {
    final h = await _openSurvey(tester);
    await _measure(tester, h, 40.2, -8.429, mocked: true);
    expect(find.textContaining('simulated location'), findsOneWidget);

    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();
    await _measure(tester, h, 40.2, -8.429, accuracy: 30);
    expect(find.textContaining('imprecise right now (±30 m)'), findsOne);
  });

  testWidgets('leaving without choosing changes nothing', (tester) async {
    final h = await _openSurvey(tester);
    await _measure(tester, h, 40.2000636, -8.4289169);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('0/3 vertices surveyed'), findsOneWidget);
    expect(h.drafts.load('p1'), isNull);
  });

  testWidgets('without location permission it explains and goes back', (
    tester,
  ) async {
    await _openSurvey(tester, access: LocationAccess.denied);
    expect(find.text('Survey V2'), findsNothing);
    expect(find.textContaining('Allow location access'), findsOneWidget);
  });

  testWidgets('in Portuguese, as in the specification (§4.1)', (tester) async {
    final h = await _openSurvey(tester, phone: const Locale('pt', 'PT'));
    expect(find.text('Levantar V2'), findsOneWidget);
    await _measure(
      tester,
      h,
      40.2000204,
      -8.4289734,
      accuracy: 4,
      button: 'Medir',
    );
    expect(
      find.text(
        'Medido a 3,2 m para nordeste da posição guardada · precisão ±4 m',
      ),
      findsOneWidget,
    );
    expect(find.text('Substituir'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Manter'), findsOneWidget);
    expect(find.text('Repetir'), findsOneWidget);
  });
}
