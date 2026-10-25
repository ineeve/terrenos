import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/app/app.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/device/device_identity.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/core/storage/app_directories.dart';
import 'package:terrenos/features/map/map_page.dart';

import '../helpers/fake_tiles.dart';

class _Harness {
  new({AppSettings settings = const AppSettings()})
    : settings = MemorySettingsRepository(settings),
      device = MemoryDeviceRepository();

  final MemorySettingsRepository settings;
  final MemoryDeviceRepository device;
  final tiles = FakeTileProvider();

  Future<void> pump(WidgetTester tester, {Locale phone = const Locale('en')}) {
    tester.platformDispatcher.localeTestValue = phone;
    tester.platformDispatcher.localesTestValue = [phone];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDirectoriesProvider.overrideWithValue(
            AppDirectories(Directory('/nonexistent')),
          ),
          settingsRepositoryProvider.overrideWithValue(settings),
          deviceRepositoryProvider.overrideWithValue(device),
          imageryTileProviderProvider.overrideWithValue(tiles),
        ],
        child: const TerrenosApp(),
      ),
    );
  }
}

const _onboarded = AppSettings(onboardingComplete: true);

void main() {
  group('first run', () {
    testWidgets('completes in Portuguese on a Portuguese phone', (
      tester,
    ) async {
      final h = _Harness();
      await h.pump(tester, phone: const Locale('pt', 'PT'));
      await tester.pumpAndSettle();

      expect(find.text('Escolha o idioma'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(h.settings.settings.language, AppLanguage.pt);

      expect(find.text('Dê um nome a este telemóvel'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Escreva um nome.'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField),
        '  Telemóvel da Maria ',
      );
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(h.device.identity.displayName, 'Telemóvel da Maria');

      expect(find.text('Registe os seus terrenos'), findsOneWidget);
      await tester.tap(find.text('Seguinte'));
      await tester.pumpAndSettle();
      expect(find.text('Funciona sem internet'), findsOneWidget);
      await tester.tap(find.text('Seguinte'));
      await tester.pumpAndSettle();
      expect(find.text('Os dados ficam neste telemóvel'), findsOneWidget);
      expect(find.bySemanticsLabel('Página 3 de 3'), findsOneWidget);

      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();
      expect(h.settings.settings.onboardingComplete, isTrue);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Definições'), findsOneWidget);
    });

    testWidgets('choosing a language switches the app immediately', (
      tester,
    ) async {
      final h = _Harness();
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('Choose your language'), findsOneWidget);
      await tester.tap(find.text('Português'));
      await tester.pumpAndSettle();
      expect(find.text('Escolha o idioma'), findsOneWidget);
      expect(h.settings.settings.language, AppLanguage.pt);
    });

    testWidgets('phones in other languages start in English', (tester) async {
      final h = _Harness();
      await h.pump(tester, phone: const Locale('fr', 'FR'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your language'), findsOneWidget);
    });

    testWidgets('rejects names that are too long', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'x' * 41);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Use at most 40 characters.'), findsOneWidget);
      expect(h.device.identity.displayName, isEmpty);
    });
  });

  group('after onboarding', () {
    testWidgets('opens on the map and switches tabs', (tester) async {
      final h = _Harness(settings: _onboarded);
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Map'), findsOneWidget);
      for (final tab in ['Properties', 'Groups', 'Settings']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, tab), findsOneWidget);
      }
    });

    testWidgets('the map shows DGT imagery and can switch series', (
      tester,
    ) async {
      final h = _Harness(settings: _onboarded);
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('Ortofotos © DGT 2025'), findsOneWidget);
      expect(h.tiles.requestedUrls, isNotEmpty);
      expect(
        h.tiles.requestedUrls.every(
          (url) =>
              url.contains('/wms/ortos2025?') &&
              url.contains('layers=Ortos2025-RGB') &&
              url.contains('crs=EPSG%3A3857') &&
              url.contains('format=image%2Fjpeg'),
        ),
        isTrue,
      );

      await tester.tap(find.byTooltip('Map imagery'));
      await tester.pumpAndSettle();
      expect(find.text('Orthophotos 2025 (latest)'), findsOneWidget);
      await tester.tap(find.text('Orthophotos 2018'));
      await tester.pumpAndSettle();

      expect(find.text('Ortofotos © DGT 2018'), findsOneWidget);
      expect(h.tiles.requestedUrls.last, contains('layers=Ortos2018-RGB'));
    });

    testWidgets('settings change language, units and phone name', (
      tester,
    ) async {
      final h = _Harness(settings: _onboarded);
      h.device.identity = h.device.identity.copyWith(displayName: 'Old');
      await h.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Area unit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Square metres (m²)'));
      await tester.pumpAndSettle();
      expect(h.settings.settings.areaUnit, AreaUnit.squareMetres);

      await tester.tap(find.text('Coordinate format'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PT-TM06 (M, P in metres)'));
      await tester.pumpAndSettle();
      expect(h.settings.settings.coordinateFormat, CoordinateFormat.ptTm06);

      await tester.tap(find.text('Phone name'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        'Telemóvel do João',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(h.device.identity.displayName, 'Telemóvel do João');
      expect(find.text('Telemóvel do João'), findsOneWidget);

      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Português').last);
      await tester.pumpAndSettle();
      expect(h.settings.settings.language, AppLanguage.pt);
      expect(find.widgetWithText(AppBar, 'Definições'), findsOneWidget);

      await tester.tap(find.text('Idioma'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Igual ao telemóvel'));
      await tester.pumpAndSettle();
      expect(h.settings.settings.language, isNull);
      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
    });

    testWidgets('cancelling a dialog changes nothing', (tester) async {
      final h = _Harness(settings: _onboarded);
      await h.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Phone name'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      expect(h.settings.settings, _onboarded);
    });
  });
}
