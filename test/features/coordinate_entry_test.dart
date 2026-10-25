import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/features/vertices/boundary_preview_map.dart';
import 'package:terrenos/features/vertices/coordinate_entry_page.dart';

import '../helpers/harness.dart';

/// About 85 m × 111 m near Coimbra, counter-clockwise from the south-west.
const _square = [
  ('40.2000', '-8.4300'),
  ('40.2000', '-8.4290'),
  ('40.2010', '-8.4290'),
  ('40.2010', '-8.4300'),
];

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
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(
      finder,
      100,
      scrollable: find
          .descendant(
            of: find.byType(CoordinateEntryPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );

void main() {
  testWidgets('a live pin shows where the typed vertex goes (§4.1)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openCoordinates(tester);
    await _type(tester, _square[0].$1, _square[0].$2);
    await _save(tester);
    await _type(tester, _square[1].$1, _square[1].$2);

    final preview = find.descendant(
      of: find.byType(CoordinateEntryPage),
      matching: find.byType(BoundaryPreviewMap),
    );
    expect(preview, findsOneWidget);
    // The vertex so far and the one being typed.
    expect(
      tester.widget<BoundaryPreviewMap>(preview).parts.single.single,
      hasLength(2),
    );
  });

  testWidgets('warns about a vertex at its neighbour’s position (VAL-5)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openCoordinates(tester);
    for (final (a, b) in _square.take(3)) {
      await _type(tester, a, b);
      await _save(tester);
    }
    await _type(tester, _square[2].$1, _square[2].$2);
    await _scrollTo(tester, find.textContaining('Same position as V3'));
    expect(
      find.text('Same position as V3. It would be removed when saving.'),
      findsOneWidget,
    );
  });

  testWidgets('a crossing vertex can go on the nearest edge instead (VAL-2)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openCoordinates(tester);
    for (final (a, b) in _square) {
      await _type(tester, a, b);
      await _save(tester);
    }

    // East of the V2–V3 side: at the end of the list it would cross it.
    await _type(tester, '40.2005', '-8.4285');
    await _scrollTo(tester, find.textContaining('Insert between'));
    expect(
      find.text('With this vertex, the boundary crosses itself.'),
      findsOneWidget,
    );
    final red = tester
        .widgetList<PolylineLayer>(find.byType(PolylineLayer))
        .expand((l) => l.polylines)
        .where((p) => p.color == Colors.redAccent);
    expect(red, isNotEmpty);

    await tester.tap(find.text('Insert between V2 and V3 instead'));
    await tester.pumpAndSettle();

    // It went in as the third vertex, so the boundary is valid.
    await scrollToVertex(tester, 'V5');
    expect(find.text('V5'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Property details'), findsOneWidget);
  });

  testWidgets('remembers the format last used for typing (VTX-3)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openCoordinates(tester);

    await tester.tap(find.text('Add vertex').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PT-TM06'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '-41234.56');
    await tester.enterText(fields.at(1), '164321.78');
    await tester.pumpAndSettle();
    await _save(tester);

    expect(h.settings.settings.entryFormat, CoordinateFormat.ptTm06);
    // The display format is a separate setting (SET-4).
    expect(
      h.settings.settings.coordinateFormat,
      CoordinateFormat.decimalDegrees,
    );

    await tester.tap(find.text('Add vertex').last);
    await tester.pumpAndSettle();
    expect(find.text('M (easting, metres)'), findsOneWidget);
  });
}
