import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';

/// A ring from (lon, lat) offsets in 0.001° steps from a point near
/// Coimbra (0.001° ≈ 85 m east-west and 111 m north-south).
List<Vertex> _ring(List<(double, double)> steps, {String prefix = 'v'}) => [
  for (final (i, (dx, dy)) in steps.indexed)
    Vertex(
      id: '$prefix$i',
      lon: -8.43 + dx / 1000,
      lat: 40.2 + dy / 1000,
      source: VertexSource.typed,
    ),
];

List<Vertex> _rect(
  double x0,
  double y0,
  double x1,
  double y1, [
  String p = 'v',
]) => _ring([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], prefix: p);

BoundaryParts _one(List<Vertex> outer, [List<List<Vertex>> holes = const []]) =>
    [
      [outer, ...holes],
    ];

double _area(BoundaryParts parts) =>
    GeometryService.measure(parts).areaSquareMetres;

/// Checks both orders against the area of the overlap drawn out by hand.
///
/// The two are computed on planes centred in slightly different places, so
/// they can differ by a few parts per 100 000; SPEC.md §7.2 allows 0.05 %.
void _expectOverlap(BoundaryParts a, BoundaryParts b, double expected) {
  final tolerance = max(0.01, expected * 1e-4);
  expect(GeometryService.overlapArea(a, b), closeTo(expected, tolerance));
  expect(GeometryService.overlapArea(b, a), closeTo(expected, tolerance));
}

void main() {
  final square = _one(_rect(0, 0, 2, 2));

  group('overlap area (VAL-7)', () {
    test('half-overlapping squares share a rectangle', () {
      _expectOverlap(
        square,
        _one(_rect(1, 0, 3, 2, 'b')),
        _area(_one(_rect(1, 0, 2, 2))),
      );
    });

    test('a corner overlap', () {
      _expectOverlap(
        square,
        _one(_rect(1, 1, 3, 3, 'b')),
        _area(_one(_rect(1, 1, 2, 2))),
      );
    });

    test('a parcel inside another overlaps by its own area', () {
      final inner = _one(_rect(0.5, 0.5, 1.5, 1.5, 'b'));
      _expectOverlap(square, inner, _area(inner));
    });

    test('identical boundaries overlap completely', () {
      _expectOverlap(square, _one(_rect(0, 0, 2, 2, 'b')), _area(square));
    });

    test('neighbours sharing a border, or a corner, do not overlap', () {
      _expectOverlap(square, _one(_rect(2, 0, 4, 2, 'b')), 0);
      _expectOverlap(square, _one(_rect(2, 1, 4, 3, 'b')), 0);
      _expectOverlap(square, _one(_rect(2, 2, 4, 4, 'b')), 0);
    });

    test('disjoint parcels do not overlap', () {
      _expectOverlap(square, _one(_rect(5, 5, 6, 6, 'b')), 0);
    });

    test('either orientation gives the same answer', () {
      final clockwise = _one(_rect(1, 0, 3, 2, 'b').reversed.toList());
      _expectOverlap(square, clockwise, _area(_one(_rect(1, 0, 2, 2))));
    });

    test('a concave L-shape against a square', () {
      final l = _one(
        _ring([(0, 0), (3, 0), (3, 1), (1, 1), (1, 3), (0, 3)], prefix: 'l'),
      );
      // The square covers the L's corner (0..2, 0..1) and (0..1, 1..2).
      _expectOverlap(
        l,
        square,
        _area(_one(_ring([(0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)]))),
      );
    });

    test('holes are not part of the overlap', () {
      final withHole = _one(_rect(0, 0, 4, 4), [_rect(1, 1, 3, 3, 'h')]);
      // Entirely inside the hole.
      _expectOverlap(withHole, _one(_rect(1.5, 1.5, 2.5, 2.5, 'b')), 0);
      // Across the hole's edge: only the part outside the hole counts.
      _expectOverlap(
        withHole,
        _one(_rect(0.5, 1.5, 1.5, 2.5, 'b')),
        _area(_one(_rect(0.5, 1.5, 1, 2.5))),
      );
    });

    test('every part of a multi-part property counts', () {
      final twoParts = [
        [_rect(0, 0, 1, 1, 'p')],
        [_rect(2, 0, 3, 1, 'q')],
      ];
      _expectOverlap(
        twoParts,
        _one(_rect(0.5, 0, 2.5, 1, 'b')),
        _area(_one(_rect(0.5, 0, 1, 1))) + _area(_one(_rect(2, 0, 2.5, 1))),
      );
    });

    test('random rectangles match the measured intersection', () {
      final random = Random(7);
      double coordinate() => (random.nextDouble() * 40).roundToDouble() / 10;
      for (var i = 0; i < 200; i++) {
        final ax = [coordinate(), coordinate()]..sort();
        final ay = [coordinate(), coordinate()]..sort();
        final bx = [coordinate(), coordinate()]..sort();
        final by = [coordinate(), coordinate()]..sort();
        if (ax[0] == ax[1] || ay[0] == ay[1]) continue;
        if (bx[0] == bx[1] || by[0] == by[1]) continue;
        final a = _one(_rect(ax[0], ay[0], ax[1], ay[1]));
        final b = _one(_rect(bx[0], by[0], bx[1], by[1], 'b'));
        final x0 = max(ax[0], bx[0]);
        final x1 = min(ax[1], bx[1]);
        final y0 = max(ay[0], by[0]);
        final y1 = min(ay[1], by[1]);
        final expected = x0 < x1 && y0 < y1
            ? _area(_one(_rect(x0, y0, x1, y1, 'x')))
            : 0.0;
        _expectOverlap(a, b, expected);
      }
    });
  });

  group('validation', () {
    test('warns about each property it overlaps, with the area', () {
      final result = GeometryValidator.validate(
        square,
        others: [
          (id: 'p1', name: 'Olival', parts: _one(_rect(1, 0, 3, 2, 'b'))),
          (id: 'p2', name: 'Vizinho', parts: _one(_rect(2, 0, 4, 2, 'c'))),
          (id: 'p3', name: 'Longe', parts: _one(_rect(8, 8, 9, 9, 'd'))),
        ],
      );
      expect(result.canSave, isTrue);
      final issue = result.issues.whereType<OverlapsProperties>().single;
      expect(issue.severity, Severity.warning);
      expect(issue.overlaps.map((o) => o.id), ['p1']);
      expect(
        issue.overlaps.single.areaSquareMetres,
        closeTo(_area(_one(_rect(1, 0, 2, 2))), 0.5),
      );
    });

    test('ignores overlaps under 1 m²', () {
      // A sliver 0.00000001° (≈ 1 mm) wide and 222 m long: about 0.2 m².
      final result = GeometryValidator.validate(
        square,
        others: [
          (id: 'p1', name: 'Sliver', parts: _one(_rect(1.99999, 0, 4, 2, 'b'))),
        ],
      );
      expect(result.issues.whereType<OverlapsProperties>(), isEmpty);
    });
  });
}
