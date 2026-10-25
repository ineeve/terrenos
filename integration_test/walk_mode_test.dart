// Walk mode end to end on a device or emulator (REG-2, REG-13): the real
// app, real GPS and Android's foreground service. Location and
// notification permissions must be granted beforehand, and the device must
// be receiving fixes (on an emulator: `adb emu geo fix`). See
// CONTRIBUTING.md.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:terrenos/main.dart' as app;

/// Pumps until [finder] shows up, in real time.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _tapIfShown(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('walk mode adds a GPS point (REG-2)', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    // First run on a fresh install.
    if (find.text('Choose your language').evaluate().isNotEmpty) {
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Emulator');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
    }
    // A draft left by an earlier run.
    await _tapIfShown(tester, find.text('Discard'));

    await tester.tap(find.text('Properties'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New property'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Walk it with GPS'));
    await _waitFor(tester, find.text('Add point'));

    // A real fix reaches the accuracy indicator.
    await _waitFor(tester, find.textContaining(RegExp(r'^±\d+ m$')));

    await tester.tap(find.text('Add point'));
    await _waitFor(tester, find.textContaining('V1 added'));

    await tester.tap(find.byTooltip('Vertex list'));
    await tester.pumpAndSettle();
    expect(find.text('V1'), findsOneWidget);
    expect(find.text('0/1 vertices surveyed'), findsNothing);
    expect(find.text('1/1 vertices surveyed'), findsOneWidget);
  });
}
