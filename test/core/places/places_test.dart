import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/places/place_search.dart';
import 'package:terrenos/core/places/places.dart';

import '../../helpers/place_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('search (MAP-9)', () {
    final search = PlaceSearch(testCaop, testPlaces);

    List<String> names(String q) => [
      for (final r in search.search(q)) '${r.kind.name} ${r.name}',
    ];

    test('ignores accents and case', () {
      expect(names('PIODAO'), contains('village Piódão'));
      expect(names('piódão'), names('piodao'));
    });

    test('ranks exact names, then prefixes, word starts, and the rest', () {
      expect(names('piodao'), [
        'freguesia Piódão',
        'village Piódão',
        'hamlet Foz de Piódão',
        'hamlet Chãs de Piódão',
        'hamlet Malhadapiodao',
      ]);
    });

    test('puts bigger kinds of place first among equal matches', () {
      expect(names('coimbra').take(3), [
        'distrito Coimbra',
        'concelho Coimbra',
        'city Coimbra',
      ]);
    });

    test('finds a freguesia by its official name, listed once', () {
      final found = search.search('uniao das freguesias de coimbra');
      expect(found, hasLength(1));
      expect(found.single.name, startsWith('Coimbra (Sé Nova'));
      expect(search.search('santa cruz'), hasLength(1));
    });

    test('says where a place is, without repeating its freguesia', () {
      final byName = {for (final r in search.search('pi')) r.name: r};
      expect(byName['Piódão']!.where, 'Arganil');
      expect(byName['Foz de Piódão']!.where, 'Piódão, Arganil');
      expect(search.search('arganil').single.where, 'Coimbra');
      expect(search.search('coimbra').first.where, isNull);
    });

    test('gives areas a bounding box and places a point', () {
      final concelho = search.search('arganil').single;
      expect(concelho.southWest!.longitude, closeTo(-7.9, 1e-9));
      expect(concelho.northEast!.latitude, closeTo(40.3, 1e-9));
      expect(concelho.centre.latitude, closeTo(40.225, 1e-9));
      final city = search
          .search('coimbra')
          .firstWhere((r) => r.kind == PlaceResultKind.city);
      expect(city.southWest, isNull);
      expect(city.centre.latitude, closeTo(40.21119, 1e-9));
    });

    test('needs at least two letters and stops at the limit', () {
      expect(search.search(' p '), isEmpty);
      expect(search.search('o', limit: 3), isEmpty);
      expect(search.search('o '), isEmpty);
      expect(search.search('pi', limit: 2), hasLength(2));
    });
  });

  group('bundled asset', () {
    late Places places;
    late AdminBoundaries caop;

    setUpAll(() {
      places = Places.parse(File(placesAsset).readAsStringSync());
      caop = AdminBoundaries.parse(File(caopAsset).readAsStringSync());
    });

    test('holds the places of mainland Portugal, biggest first', () {
      expect(places.places.length, greaterThan(15000));
      expect(places.places.take(2).map((p) => p.name), ['Lisboa', 'Porto']);
      for (var i = 1; i < places.places.length; i++) {
        expect(
          places.places[i].kind.index,
          greaterThanOrEqualTo(places.places[i - 1].kind.index),
        );
      }
      final codes = {for (final f in caop.freguesias) f.code};
      expect(places.places.every((p) => codes.contains(p.freguesia)), isTrue);
    });

    test('finds well-known places where they are', () {
      final search = PlaceSearch(caop, places);
      final piodao = search
          .search('piodao')
          .firstWhere((r) => r.kind == PlaceResultKind.village);
      expect(piodao.where, 'Arganil');
      expect(piodao.centre.latitude, closeTo(40.23, 0.01));
      expect(piodao.centre.longitude, closeTo(-7.82, 0.01));
      final sjm = search.search('sao joao da madeira');
      expect(sjm.map((r) => r.kind), contains(PlaceResultKind.city));
    });

    test('rejects an unknown format', () {
      expect(
        () => Places.fromJson({'format': 2}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('the app loads the bundled asset off the UI thread', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final places = await container.read(placesProvider.future);
    expect(places.places.first.name, 'Lisboa');
  });

  test('keeps only the OSM place kinds the app uses', () {
    expect(PlaceKind.fromOsm('town'), PlaceKind.town);
    expect(PlaceKind.fromOsm('isolated_dwelling'), isNull);
  });
}
