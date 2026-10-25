import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/core/format/size_format.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/offline_area.dart';

import '../helpers/harness.dart';

OfflineArea _area({bool complete = true}) {
  final area = OfflineArea(
    id: 'a1',
    name: 'Olival',
    source: ImagerySource.ortos2025,
    bounds: LatLngBounds(
      const LatLng(40.2, -8.43),
      const LatLng(40.2027, -8.4265),
    ),
    detail: OfflineDetail.high,
    downloadedAt: DateTime.utc(2026, 10, 25),
  );
  return area.copyWith(
    complete: complete,
    savedTiles: complete ? area.tileCount : 3,
    savedBytes: complete ? 1234567 : 300,
  );
}

Future<void> _openOfflineMaps(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Offline maps'));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String action) async {
  await tester.tap(
    find.descendant(
      of: find.byType(ListTile),
      matching: find.byIcon(Icons.more_vert),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(action).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('frame an area and download it (MAP-7)', (tester) async {
    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openOfflineMaps(tester);
    expect(find.textContaining('No areas downloaded yet'), findsOneWidget);

    await tester.tap(find.text('Download an area'));
    await tester.pumpAndSettle();
    expect(find.text('Frame the area'), findsOneWidget);
    expect(find.textContaining('km²'), findsOneWidget);
    expect(find.textContaining('tiles, about'), findsOneWidget);
    final highTiles = find.textContaining('tiles, about').evaluate().single;
    final highText = (highTiles.widget as Text).data!;

    await tester.tap(find.text('Normal detail'));
    await tester.pumpAndSettle();
    final normalText = tester
        .widget<Text>(find.textContaining('tiles, about'))
        .data!;
    expect(normalText, isNot(highText));
    await tester.tap(find.text('High detail'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();
    expect(find.text('Name this area'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Olival do Ribeiro');
    await tester.tap(find.widgetWithText(TextButton, 'Download'));
    await tester.pumpAndSettle();

    expect(find.text('Offline maps'), findsOneWidget);
    expect(find.text('Olival do Ribeiro'), findsOneWidget);
    final area = h.offlineTiles.areas.single;
    expect(area.complete, isTrue);
    expect(area.detail, OfflineDetail.high);
    expect(area.source, ImagerySource.ortos2025);
    expect(h.fetchedUrls, hasLength(area.tileCount));
    expect(h.offlineTiles.tiles, hasLength(area.tileCount));
    expect(
      find.textContaining(
        '${formatCount(area.tileCount, languageCode: 'en')} tiles',
      ),
      findsOneWidget,
    );
  });

  testWidgets('areas larger than 4 km² cannot be downloaded', (tester) async {
    // A large screen frames far more than 4 km² at the opening zoom.
    tester.view.physicalSize = const Size(2400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final h = Harness(settings: onboarded);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openOfflineMaps(tester);
    await tester.tap(find.text('Download an area'));
    await tester.pumpAndSettle();

    expect(
      find.text('Too large: the maximum is 4.00 km². Zoom in.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Download'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('list, delete and clear offline maps (MAP-8)', (tester) async {
    final h = Harness(settings: onboarded);
    h.browseCache.bytes = 45000000;
    final area = _area();
    h.offlineTiles.areas.add(area);
    for (final tile in area.tiles) {
      h.offlineTiles.tiles['ortos2025/${tile.z}/${tile.x}/${tile.y}'] =
          Uint8List(10);
    }
    await h.pump(tester);
    await tester.pumpAndSettle();

    // Reached from Settings as well as from the map.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline maps'));
    await tester.pumpAndSettle();

    expect(find.text('Olival'), findsOneWidget);
    expect(find.textContaining('1.2 MB'), findsOneWidget);
    expect(find.textContaining('45 MB.'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(h.browseCache.bytes, 0);
    expect(find.textContaining('0 B.'), findsOneWidget);

    await _choose(tester, 'Delete');
    expect(find.text('Delete “Olival”?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Olival'), findsNothing);
    expect(h.offlineTiles.tiles, isEmpty);
    expect(find.textContaining('No areas downloaded yet'), findsOneWidget);
  });

  testWidgets('an incomplete area can be resumed', (tester) async {
    final h = Harness(settings: onboarded);
    h.offlineTiles.areas.add(_area(complete: false));
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openOfflineMaps(tester);
    expect(find.textContaining('Incomplete: 3 of'), findsOneWidget);

    await _choose(tester, 'Resume');
    expect(h.offlineTiles.areas.single.complete, isTrue);
    expect(find.textContaining('Incomplete'), findsNothing);

    await _choose(tester, 'Download again');
    expect(h.fetchedUrls, hasLength(2 * _area().tileCount));
  });

  testWidgets('delete all asks first', (tester) async {
    final h = Harness(settings: onboarded);
    h.offlineTiles.areas.add(_area());
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _openOfflineMaps(tester);

    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all offline maps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.offlineTiles.areas, hasLength(1));

    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all offline maps'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(h.offlineTiles.areas, isEmpty);
    expect(find.text('Olival'), findsNothing);
  });

  testWidgets('the screens are translated into Portuguese', (tester) async {
    final h = Harness(settings: onboarded);
    h.offlineTiles.areas.add(_area(complete: false));
    await h.pump(tester, phone: const Locale('pt', 'PT'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mapas offline'));
    await tester.pumpAndSettle();
    expect(find.text('Áreas transferidas'), findsOneWidget);
    expect(find.textContaining('Incompleta: 3 de'), findsOneWidget);
    await tester.tap(find.text('Transferir uma área'));
    await tester.pumpAndSettle();
    expect(find.text('Enquadre a área'), findsOneWidget);
    expect(find.textContaining('mosaicos, cerca de'), findsOneWidget);
  });
}
