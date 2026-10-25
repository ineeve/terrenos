import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/geometry/planar.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';

final _reference = jsonDecode(
  File('test_fixtures/geodesy_reference.json').readAsStringSync(),
) as Map<String, Object?>;

BoundaryParts _parts(List<Object?> json) {
  var n = 0;
  return [
    for (final part in json)
      [
        for (final ring in part! as List)
          [
            for (final p in ring as List)
              Vertex(
                id: 'v${n++}',
                lon: ((p as List)[0] as num).toDouble(),
                lat: (p[1] as num).toDouble(),
                source: VertexSource.map,
              ),
          ],
      ],
  ];
}

List<Vertex> _ring(List<(double, double)> lonLats) => [
  for (final (i, (lon, lat)) in lonLats.indexed)
    Vertex(id: 'v$i', lon: lon, lat: lat, source: VertexSource.map),
];

void main() {
  group('measurements match GeographicLib', () {
    for (final polygon
        in (_reference['polygons']! as List).cast<Map<String, Object?>>()) {
      test(polygon['name']! as String, () {
        final m = GeometryService.measure(_parts(polygon['parts']! as List));
        final area = polygon['area_m2']! as double;
        final perimeter = polygon['perimeter_m']! as double;
        // SPEC.md §7.2: within 0.05 %.
        expect(m.areaSquareMetres, closeTo(area, area * 0.0005));
        expect(m.perimeterMetres, closeTo(perimeter, perimeter * 0.0005));
      });
    }
  });

  group('distances match GeographicLib', () {
    for (final pair
        in (_reference['distances']! as List).cast<Map<String, Object?>>()) {
      test(pair['name']! as String, () {
        final from = pair['from']! as List;
        final to = pair['to']! as List;
        final result = inverse(
          (lon: from[0] as double, lat: from[1] as double),
          (lon: to[0] as double, lat: to[1] as double),
        );
        expect(
          result.distanceMetres,
          closeTo(pair['distance_m']! as double, 0.001),
        );
        expect(
          result.bearingDegrees,
          closeTo(pair['initial_bearing_deg']! as double, 1e-6),
        );
      });
    }

    test('identical points are 0 m apart', () {
      expect(inverse((lon: -8, lat: 40), (lon: -8, lat: 40)).distanceMetres, 0);
    });
  });

  test('compass directions', () {
    expect(CompassDirection.fromBearing(0), CompassDirection.north);
    expect(CompassDirection.fromBearing(44), CompassDirection.northEast);
    expect(CompassDirection.fromBearing(181), CompassDirection.south);
    expect(CompassDirection.fromBearing(337.6), CompassDirection.north);
    expect(CompassDirection.fromBearing(270.003), CompassDirection.west);
  });

  group('interior point', () {
    test('lies inside an L-shaped parcel, away from its edges', () {
      // An L whose bounding-box centre and centroid both fall outside it.
      final ring = _ring([
        (-8.0000, 40.0000),
        (-7.9980, 40.0000),
        (-7.9980, 40.0004),
        (-7.9996, 40.0004),
        (-7.9996, 40.0020),
        (-8.0000, 40.0020),
      ]);
      final m = GeometryService.measure([
        [ring],
      ]);
      final plane = LocalPlane.around(
        ring.map((v) => (lon: v.lon, lat: v.lat)),
      );
      final xy = [
        for (final v in ring) plane.project((lon: v.lon, lat: v.lat)),
      ];
      final p = plane.project(m.interiorPoint);
      expect(containsPoint([xy], p), isTrue);
    });

    test('uses the largest part of a multi-part property', () {
      final parts = _parts(
        (_reference['polygons']! as List)
                .cast<Map<String, Object?>>()
                .firstWhere((p) => p['name'] == 'algarve_two_parts')['parts']!
            as List,
      );
      final point = GeometryService.measure(parts).interiorPoint;
      expect(point.lon, inInclusiveRange(-8.0010, -7.9990));
      expect(point.lat, inInclusiveRange(37.1000, 37.1015));
    });
  });

  test('unprojecting the plane centre returns the centre', () {
    final plane = LocalPlane((lon: -8.43, lat: 40.2));
    expect(plane.unproject((x: 0, y: 0)), (lon: -8.43, lat: 40.2));
    final back = plane.unproject(plane.project((lon: -8.42, lat: 40.21)));
    // ~0.1 mm: proj4dart's inverse uses a series expansion.
    expect(back.lon, closeTo(-8.42, 1e-8));
    expect(back.lat, closeTo(40.21, 1e-8));
  });

  test('a symmetric parcel centred on the plane origin can be measured', () {
    final m = GeometryService.measure([
      [
        _ring([
          (-8.43, 40.2),
          (-8.429, 40.2),
          (-8.429, 40.201),
          (-8.43, 40.201),
        ]),
      ],
    ]);
    // In a rectangle every point on the middle line is equally far from
    // the long sides, so only the cross-axis position is unique.
    expect(m.interiorPoint.lon, closeTo(-8.4295, 1e-5));
    expect(m.interiorPoint.lat, inInclusiveRange(40.2003, 40.2007));
  });

  test('bounds cover every vertex', () {
    final m = GeometryService.measure([
      [
        _ring([(-8.1, 40.0), (-8.0, 40.0), (-8.0, 40.2)]),
      ],
    ]);
    expect(m.bounds, (minLon: -8.1, minLat: 40.0, maxLon: -8.0, maxLat: 40.2));
  });

  test('measuring fewer than 3 vertices is an error', () {
    expect(
      () => GeometryService.measure([
        [
          _ring([(-8, 40), (-8, 41)]),
        ],
      ]),
      throwsArgumentError,
    );
  });

  group('crossings (VAL-2)', () {
    test('a simple ring has none', () {
      expect(
        GeometryService.crossings([
          [
            _ring([(-8, 40), (-7.999, 40), (-7.999, 40.001), (-8, 40.001)]),
          ],
        ]),
        isEmpty,
      );
    });

    test('a bow-tie reports its crossing edges by vertex id', () {
      final crossings = GeometryService.crossings([
        [
          _ring([(-8, 40), (-7.999, 40.001), (-7.999, 40), (-8, 40.001)]),
        ],
      ]);
      expect(crossings, hasLength(1));
      expect(crossings.single.first, ('v0', 'v1'));
      expect(crossings.single.second, ('v2', 'v3'));
    });

    test('a vertex touching a non-adjacent edge counts', () {
      final crossings = GeometryService.crossings([
        [
          _ring([
            (-8, 40),
            (-7.998, 40),
            (-7.999, 40.002),
            (-7.999, 40), // lies on the first edge
            (-8, 40.002),
          ]),
        ],
      ]);
      expect(crossings, isNotEmpty);
    });

    test('overlapping parts of one property count', () {
      final a = _ring([(-8, 40), (-7.998, 40), (-7.998, 40.002), (-8, 40.002)]);
      final b = [
        for (final v in _ring([
          (-7.999, 40.001),
          (-7.997, 40.001),
          (-7.997, 40.003),
          (-7.999, 40.003),
        ]))
          Vertex(id: 'b${v.id}', lon: v.lon, lat: v.lat, source: v.source),
      ];
      expect(
        GeometryService.crossings([
          [a],
          [b],
        ]),
        isNotEmpty,
      );
    });
  });

  group('duplicates (VAL-5)', () {
    test('consecutive repeats and a closing repeat are removed', () {
      final ring = _ring([
        (-8, 40),
        (-8, 40),
        (-7.999, 40),
        (-7.999, 40.001),
        (-7.999, 40.001),
        (-8, 40),
      ]);
      final cleaned = GeometryService.withoutDuplicates([
        [ring],
      ]).single.single;
      expect(cleaned.map((v) => v.id), ['v0', 'v2', 'v3']);
    });
  });

  group('orientation (VAL-4)', () {
    test('detects counter-clockwise and clockwise rings', () {
      final ccw = _ring([
        (-8, 40),
        (-7.999, 40),
        (-7.999, 40.001),
        (-8, 40.001),
      ]);
      expect(GeometryService.isCounterClockwise(ccw), isTrue);
      expect(
        GeometryService.isCounterClockwise(ccw.reversed.toList()),
        isFalse,
      );
    });
  });

  group('simplification', () {
    test('drops points closer than the tolerance and keeps corners', () {
      // A square walked with small wobbles along each side.
      final ring = _ring([
        (-8.0000, 40.0000),
        (-7.9995, 40.000002),
        (-7.9990, 40.0000),
        (-7.99899, 40.0005),
        (-7.9990, 40.0010),
        (-7.9995, 40.001003),
        (-8.0000, 40.0010),
        (-8.000002, 40.0005),
      ]);
      final simplified = GeometryService.simplifyRing(ring, 1);
      expect(simplified.map((v) => v.id), ['v0', 'v2', 'v4', 'v6']);
      expect(GeometryService.simplifyRing(ring, 0.01), hasLength(8));
    });

    test('never collapses below a triangle', () {
      final ring = _ring([(-8, 40), (-7.99999, 40), (-7.99999, 40.00001)]);
      expect(GeometryService.simplifyRing(ring, 100), hasLength(3));
    });
  });
}
