import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/crs/pt_tm06.dart';
import 'package:terrenos/core/editing/boundary_fixes.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/model/vertex.dart';

Vertex _v(String id, double lon, double lat, {CoordinateInput? input}) =>
    Vertex(
      id: id,
      lon: lon,
      lat: lat,
      source: VertexSource.typed,
      input: input,
    );

/// About 85 m × 111 m near Coimbra, counter-clockwise.
final List<Vertex> _square = [
  _v('a', -8.4300, 40.2000),
  _v('b', -8.4290, 40.2000),
  _v('c', -8.4290, 40.2010),
  _v('d', -8.4300, 40.2010),
];

void main() {
  group('swapping coordinates (VAL-6)', () {
    test('latitude and longitude change places, typed values too', () {
      final swapped = swapCoordinates(
        [
          [
            [
              _v(
                'a',
                40.2,
                -8.43,
                input: const CoordinateInput(
                  crs: 'EPSG:4326',
                  x: 40.2,
                  y: -8.43,
                ),
              ),
              _v('b', -8.429, 40.2),
            ],
          ],
        ],
        {'a'},
      ).single.single;
      expect((swapped[0].lat, swapped[0].lon), (40.2, -8.43));
      expect((swapped[0].input!.x, swapped[0].input!.y), (-8.43, 40.2));
      // Only the listed vertices.
      expect((swapped[1].lat, swapped[1].lon), (40.2, -8.429));
    });

    test('PT-TM06 values swap M and P and are converted again', () {
      final pt = PtTm06.fromLatLon(40.2, -8.43);
      // Typed the wrong way round: P in the M field.
      final wrong = PtTm06.toLatLon(pt.p, pt.m);
      final swapped = swapCoordinates(
        [
          [
            [
              _v(
                'a',
                wrong.lon,
                wrong.lat,
                input: CoordinateInput(crs: PtTm06.epsg, x: pt.p, y: pt.m),
              ),
            ],
          ],
        ],
        {'a'},
      ).single.single.single;
      expect(swapped.lat, closeTo(40.2, 1e-7));
      expect(swapped.lon, closeTo(-8.43, 1e-7));
      expect((swapped.input!.x, swapped.input!.y), (pt.m, pt.p));
    });
  });

  group('simplifying to the vertex limit (VAL-9)', () {
    /// A circle of [n] vertices about 500 m across.
    List<Vertex> circle(int n) => [
      for (var i = 0; i < n; i++)
        _v(
          'c$i',
          -8.43 + 0.003 * cos(2 * pi * i / n),
          40.2 + 0.0023 * sin(2 * pi * i / n),
        ),
    ];

    test('just enough to fit, keeping ids and the shape', () {
      final parts = [
        [circle(6000)],
      ];
      final fit = simplifyToFit(parts);
      final ring = fit.parts.single.single;
      expect(ring.length, lessThanOrEqualTo(TooManyVertices.max));
      expect(ring.length, greaterThan(100));
      expect(fit.toleranceMetres, greaterThan(0));
      final ids = {for (final v in circle(6000)) v.id};
      expect(ring.every((v) => ids.contains(v.id)), isTrue);
      final before = GeometryService.measure(parts).areaSquareMetres;
      final after = GeometryService.measure(fit.parts).areaSquareMetres;
      expect((after - before).abs() / before, lessThan(0.001));
    });

    test('a boundary within the limit is left alone', () {
      final parts = [
        [_square],
      ];
      final fit = simplifyToFit(parts);
      expect(fit.parts, same(parts));
      expect(fit.toleranceMetres, 0);
      expect(
        simplifyToFit([
          [circle(40)],
        ], maxVertices: 10).parts.single.single.length,
        lessThanOrEqualTo(10),
      );
    });
  });

  test('exports orient rings as RFC 7946 asks (VAL-4)', () {
    final clockwise = _square.reversed.toList();
    final hole = [
      _v('h1', -8.4297, 40.2003),
      _v('h2', -8.4293, 40.2003),
      _v('h3', -8.4293, 40.2007),
    ];
    final oriented = orientedForExport([
      [clockwise, hole],
    ]).single;
    expect(GeometryService.isCounterClockwise(oriented[0]), isTrue);
    expect(GeometryService.isCounterClockwise(oriented[1]), isFalse);
    // Already right: unchanged.
    expect(
      orientedForExport([
        [_square],
      ]).single.single,
      same(_square),
    );
  });

  test('low-confidence GPS vertices (VAL-8)', () {
    GpsFix fix(double accuracy, {bool mocked = false}) => GpsFix(
      accuracyMetres: accuracy,
      samples: 5,
      capturedAt: DateTime.utc(2026),
      mocked: mocked,
      deviceId: 'dev',
    );
    Vertex gps(GpsFix f) => Vertex(
      id: 'g',
      lon: -8.43,
      lat: 40.2,
      source: VertexSource.gps,
      gps: f,
    );
    expect(isLowConfidence(_square.first), isFalse);
    expect(isLowConfidence(gps(fix(4))), isFalse);
    expect(isLowConfidence(gps(fix(20))), isTrue);
    expect(isLowConfidence(gps(fix(4, mocked: true))), isTrue);
    expect(isLowConfidence(gps(fix(20)), thresholdMetres: 30), isFalse);
  });
}
