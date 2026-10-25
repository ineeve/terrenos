import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/editing/vertex_placement.dart';
import 'package:terrenos/core/model/vertex.dart';

/// A ring from (x, y) steps of 0.001° near Coimbra.
List<Vertex> _ring(List<(double, double)> steps) => [
  for (final (i, (x, y)) in steps.indexed)
    Vertex(
      id: 'v${i + 1}',
      lon: -8.43 + x / 1000,
      lat: 40.2 + y / 1000,
      source: VertexSource.typed,
    ),
];

({double lon, double lat}) _at(double x, double y) =>
    (lon: -8.43 + x / 1000, lat: 40.2 + y / 1000);

void main() {
  // An open square, v1 … v4, going counter-clockwise.
  final square = _ring([(0, 0), (1, 0), (1, 1), (0, 1)]);

  test('a good next vertex raises nothing', () {
    final ring = _ring([(0, 0), (1, 0), (1, 1)]);
    final placement = checkPlacement(ring, _at(0, 1));
    expect(placement.ring, hasLength(4));
    expect(placement.vertexId, VertexPlacement.newVertexId);
    expect(placement.sameAsId, isNull);
    expect(placement.crosses, isFalse);
  });

  test('the same position as a neighbour would be removed (VAL-5)', () {
    // The new vertex follows v4 and comes before v1.
    expect(checkPlacement(square, _at(0, 1)).sameAsId, 'v4');
    expect(checkPlacement(square, _at(0, 0)).sameAsId, 'v1');
    // Not a neighbour: no warning.
    expect(checkPlacement(square, _at(1, 0)).sameAsId, isNull);
  });

  test('rounding to the stored 7 decimals counts as the same position', () {
    final placement = checkPlacement(square, (
      lon: -8.43 + 0.00000001,
      lat: 40.2 + 0.001 + 0.00000002,
    ));
    expect(placement.sameAsId, 'v4');
  });

  test('a crossing vertex suggests the nearest edge that works (VAL-2)', () {
    // Past the right side, next to the v2–v3 edge: appended after v4 the
    // new edges would cross the square.
    final placement = checkPlacement(square, _at(1.5, 0.5));
    expect(placement.crosses, isTrue);
    expect(
      placement.crossings.every(
        (c) => [
          c.first.$1,
          c.first.$2,
          c.second.$1,
          c.second.$2,
        ].contains(VertexPlacement.newVertexId),
      ),
      isTrue,
    );
    expect(placement.betterAfterId, 'v2');
  });

  test('moving a vertex is checked in place, with no suggestion', () {
    final placement = checkPlacement(square, _at(1.5, 0.5), replacingId: 'v4');
    expect(placement.ring, hasLength(4));
    expect(placement.ring[3].id, 'v4');
    expect(placement.crosses, isTrue);
    expect(placement.betterAfterId, isNull);

    expect(
      checkPlacement(square, _at(-0.5, 1.5), replacingId: 'v4').crosses,
      isFalse,
    );
  });

  test('crossings the ring already had are not blamed on the vertex', () {
    // A bow-tie: v1–v2 crosses v3–v4.
    final bowTie = _ring([(0, 0), (1, 1), (1, 0), (0, 1)]);
    final placement = checkPlacement(bowTie, _at(-1, 0.5));
    expect(placement.crosses, isFalse);
  });

  test('too few vertices to cross', () {
    final placement = checkPlacement(_ring([(0, 0), (1, 0)]), _at(1, 1));
    expect(placement.crosses, isFalse);
    expect(checkPlacement(const [], _at(0, 0)).ring, hasLength(1));
  });
}
