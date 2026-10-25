import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('About credits the map data with the CAOP edition (§6.2)', (
    tester,
  ) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester, phone: const Locale('pt', 'PT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Definições'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Dados do mapa'), 100);

    expect(
      find.text(
        'Ortofotos © DGT. Limites administrativos: CAOP 2025 © DGT, CC BY.',
      ),
      findsOneWidget,
    );
  });
}
