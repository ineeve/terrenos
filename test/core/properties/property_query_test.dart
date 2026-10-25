import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/property_kinds.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/properties/property_query.dart';

/// A square near Coimbra, [size] × 0.001° on each side.
PropertyDocument _doc(
  String id,
  String name, {
  double size = 1,
  int changedAt = 10,
  String? number,
  PropertyType? type,
  LandUse? use,
  PropertyLocation? location,
  bool surveyed = false,
}) {
  var doc = PropertyDocument.create(
    id: id,
    name: name,
    timestamp: const Hlc(1, 0, 'dev'),
  );
  final fields = <String, Object?>{
    PropertyField.processNumber: ?number,
    PropertyField.type: ?type?.name,
    PropertyField.landUse: ?use?.code,
    PropertyField.location: ?location?.toJson(),
  };
  for (final MapEntry(:key, :value) in fields.entries) {
    doc = doc.withField(key, value, const Hlc(2, 0, 'dev'));
  }
  final d = size / 1000;
  return doc.withGeometry([
    [
      [
        for (final (i, (x, y)) in [(0, 0), (d, 0), (d, d), (0, d)].indexed)
          Vertex(
            id: '$id$i',
            lon: -8.43 + x,
            lat: 40.2 + y,
            source: surveyed ? VertexSource.gps : VertexSource.typed,
            gps: surveyed
                ? GpsFix(
                    accuracyMetres: 3,
                    samples: 5,
                    capturedAt: DateTime.utc(2026),
                    mocked: false,
                    deviceId: 'dev',
                  )
                : null,
          ),
      ],
    ],
  ], Hlc(changedAt, 0, 'dev'));
}

const _sao = PropertyLocation(concelho: 'Coimbra', freguesia: 'São Martinho');
const _ega = PropertyLocation(concelho: 'Condeixa', freguesia: 'Ega');

void main() {
  final olival = _doc(
    'a',
    'Olival',
    size: 2,
    changedAt: 30,
    number: '0012/2023-A',
    type: PropertyType.rustico,
    use: LandUse.oliveGrove,
    location: _sao,
  );
  final eira = _doc(
    'b',
    'Éira Velha',
    changedAt: 50,
    type: PropertyType.urbano,
    use: LandUse.builtUp,
    location: _ega,
    surveyed: true,
  );
  final vinha = _doc(
    'c',
    'vinha',
    size: 3,
    changedAt: 20,
    number: '7',
    type: PropertyType.rustico,
    use: LandUse.vineyard,
  );
  final all = [olival, eira, vinha];
  List<String> names(PropertyQuery q) => [for (final d in q.apply(all)) d.name];

  group('search (IDN-6)', () {
    test('names ignore accents and case', () {
      expect(names(const PropertyQuery(search: 'EIRA')), ['Éira Velha']);
      expect(names(const PropertyQuery(search: ' vinha ')), ['vinha']);
    });

    test('process numbers match normalised and in part', () {
      expect(names(const PropertyQuery(search: '0012 2023 a')), ['Olival']);
      expect(names(const PropertyQuery(search: '2023')), ['Olival']);
    });
  });

  group('sort (MGT-1)', () {
    test('by name, accent-insensitive', () {
      expect(names(const PropertyQuery()), ['Éira Velha', 'Olival', 'vinha']);
    });

    test('by process number, with none last', () {
      expect(names(const PropertyQuery(sort: PropertySort.processNumber)), [
        'Olival',
        'vinha',
        'Éira Velha',
      ]);
    });

    test('by area, largest first', () {
      expect(names(const PropertyQuery(sort: PropertySort.area)), [
        'vinha',
        'Olival',
        'Éira Velha',
      ]);
    });

    test('by freguesia, with none last', () {
      expect(names(const PropertyQuery(sort: PropertySort.freguesia)), [
        'Éira Velha',
        'Olival',
        'vinha',
      ]);
    });

    test('by last change, newest first', () {
      expect(names(const PropertyQuery(sort: PropertySort.lastChange)), [
        'Éira Velha',
        'Olival',
        'vinha',
      ]);
    });
  });

  group('filters (MGT-1, MGT-8)', () {
    test('type and land use', () {
      expect(names(const PropertyQuery(types: {PropertyType.rustico})), [
        'Olival',
        'vinha',
      ]);
      expect(
        names(
          const PropertyQuery(
            types: {PropertyType.rustico},
            landUses: {LandUse.vineyard},
          ),
        ),
        ['vinha'],
      );
    });

    test('concelho and freguesia', () {
      expect(names(const PropertyQuery(concelhos: {'Condeixa'})), [
        'Éira Velha',
      ]);
      expect(names(const PropertyQuery(freguesias: {'São Martinho'})), [
        'Olival',
      ]);
    });

    test('with or without a process number', () {
      expect(names(const PropertyQuery(hasProcessNumber: true)), [
        'Olival',
        'vinha',
      ]);
      expect(names(const PropertyQuery(hasProcessNumber: false)), [
        'Éira Velha',
      ]);
    });

    test('vertices still to survey', () {
      expect(names(const PropertyQuery(plannedOnly: true)), [
        'Olival',
        'vinha',
      ]);
    });

    test('counting and clearing keep the search and sort', () {
      const q = PropertyQuery(
        search: 'o',
        sort: PropertySort.area,
        types: {PropertyType.rustico},
        hasProcessNumber: true,
      );
      expect(q.isFiltered, isTrue);
      expect(q.filterCount, 2);
      final cleared = q.cleared;
      expect(cleared.isFiltered, isFalse);
      expect((cleared.search, cleared.sort), ('o', PropertySort.area));
      expect(q.copyWith(hasProcessNumber: () => null).hasProcessNumber, isNull);
    });
  });

  test('areas are measured once and totalled (MGT-2)', () {
    final area = propertyArea(olival)!;
    // 0.002° × 0.002° near 40° N: about 170 m × 222 m.
    expect(area, closeTo(37900, 300));
    expect(propertyArea(olival), area);
    expect(
      totalArea(all),
      closeTo(area + propertyArea(eira)! + propertyArea(vinha)!, 1e-6),
    );
    expect(
      propertyArea(
        PropertyDocument.create(
          id: 'x',
          name: 'x',
          timestamp: const Hlc(1, 0, 'd'),
        ),
      ),
      isNull,
    );
  });

  group('location (PROP-9)', () {
    late AdminBoundaries caop;

    setUpAll(() {
      caop = AdminBoundaries.parse(File(caopAsset).readAsStringSync());
    });

    test('comes from CAOP at the parcel’s interior point', () {
      final found = locateBoundary(caop, olival.geometry.current!.parts)!;
      expect(found.concelho, 'Coimbra');
      expect(found.distrito, 'Coimbra');
      expect(found.freguesia, isNotEmpty);
      expect(found.dicofre, startsWith('0603'));
      expect(PropertyLocation.fromJson(found.toJson()!), found);
    });

    test('nothing outside Portugal or without a boundary', () {
      expect(locateBoundary(caop, const []), isNull);
      final sea = [
        [
          [
            for (final (i, (x, y)) in [
              (0.0, 0.0),
              (0.01, 0.0),
              (0.0, 0.01),
            ].indexed)
              Vertex(
                id: 's$i',
                lon: -10 + x,
                lat: 39.5 + y,
                source: VertexSource.typed,
              ),
          ],
        ],
      ];
      expect(locateBoundary(caop, sea), isNull);
    });

    test('empty names are not stored', () {
      expect(const PropertyLocation().toJson(), isNull);
      expect(
        PropertyLocation.fromJson(const {'concelho': ' ', 'freguesia': 'Ega'}),
        const PropertyLocation(freguesia: 'Ega'),
      );
    });
  });
}
