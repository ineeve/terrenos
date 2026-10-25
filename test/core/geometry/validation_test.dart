import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/model/vertex.dart';

Vertex _v(String id, double lon, double lat, {GpsFix? gps}) => Vertex(
  id: id,
  lon: lon,
  lat: lat,
  source: gps == null ? VertexSource.map : VertexSource.gps,
  gps: gps,
);

GpsFix _fix(double accuracy, {bool mocked = false}) => GpsFix(
  accuracyMetres: accuracy,
  samples: 5,
  capturedAt: DateTime.utc(2026, 10, 25),
  mocked: mocked,
  deviceId: 'dev',
);

/// About 85 m × 111 m near Coimbra.
List<Vertex> _square({String prefix = 'v'}) => [
  _v('${prefix}1', -8.4300, 40.2000),
  _v('${prefix}2', -8.4290, 40.2000),
  _v('${prefix}3', -8.4290, 40.2010),
  _v('${prefix}4', -8.4300, 40.2010),
];

void main() {
  test('a normal parcel passes with measurements', () {
    final result = GeometryValidator.validate(singleRing(_square()));
    expect(result.issues, isEmpty);
    expect(result.canSave, isTrue);
    expect(result.measurements!.areaSquareMetres, closeTo(9475, 25));
  });

  test('VAL-1: fewer than 3 distinct vertices blocks saving', () {
    final result = GeometryValidator.validate(
      singleRing([
        _v('a', -8.43, 40.2),
        _v('b', -8.43, 40.2),
        _v('c', -8.429, 40.2),
      ]),
    );
    expect(result.issues.single, isA<TooFewVertices>());
    expect(result.canSave, isFalse);
    expect(result.measurements, isNull);
  });

  test('VAL-2: a bow-tie blocks saving', () {
    final s = _square();
    final result = GeometryValidator.validate(
      singleRing([s[0], s[2], s[1], s[3]]),
    );
    expect(result.issues.whereType<SelfIntersection>(), hasLength(1));
    expect(result.canSave, isFalse);
  });

  test('VAL-3: a parcel under 1 m² blocks saving', () {
    final result = GeometryValidator.validate(
      singleRing([
        _v('a', -8.43, 40.2),
        _v('b', -8.429995, 40.2),
        _v('c', -8.429995, 40.200005),
      ]),
    );
    expect(result.issues.single, isA<AreaOutOfRange>());
  });

  test('VAL-3: more than 10 000 ha blocks saving', () {
    final result = GeometryValidator.validate(
      singleRing([
        _v('a', -8.5, 40),
        _v('b', -8.3, 40),
        _v('c', -8.3, 40.2),
        _v('d', -8.5, 40.2),
      ]),
    );
    expect(result.issues.single, isA<AreaOutOfRange>());
  });

  test('VAL-5: duplicates are removed automatically and counted', () {
    final s = _square();
    final result = GeometryValidator.validate(
      singleRing([s[0], _v('dup', s[0].lon, s[0].lat), s[1], s[2], s[3]]),
    );
    expect(result.removedDuplicates, 1);
    expect(result.parts.single.single.map((v) => v.id), [
      'v1',
      'v2',
      'v3',
      'v4',
    ]);
    expect(result.canSave, isTrue);
  });

  test('VAL-6: swapped coordinates are detected and a swap is suggested', () {
    final swapped = [for (final v in _square()) _v(v.id, v.lat, v.lon)];
    final result = GeometryValidator.validate(singleRing(swapped));
    final issue = result.issues.whereType<OutsidePortugal>().single;
    expect(issue.vertexIds, hasLength(4));
    expect(issue.swapLooksRight, isTrue);
    expect(issue.severity, Severity.warning);
  });

  test('VAL-6: a point in Spain is outside without a swap suggestion', () {
    final ring = [..._square().take(3), _v('madrid', -3.70, 40.42)];
    final issue = GeometryValidator.validate(singleRing(ring)).issues
        .whereType<OutsidePortugal>()
        .single;
    expect(issue.vertexIds, ['madrid']);
    expect(issue.swapLooksRight, isFalse);
  });

  test('VAL-6: the 50 km tolerance keeps border parcels quiet', () {
    expect(MainlandPortugal.contains(42.5, -8, withBuffer: true), isTrue);
    expect(MainlandPortugal.contains(42.5, -8), isFalse);
  });

  test('VAL-8: imprecise and mocked GPS vertices are flagged', () {
    final s = _square();
    final result = GeometryValidator.validate(
      singleRing([
        _v(s[0].id, s[0].lon, s[0].lat, gps: _fix(4)),
        _v(s[1].id, s[1].lon, s[1].lat, gps: _fix(22)),
        _v(s[2].id, s[2].lon, s[2].lat, gps: _fix(3, mocked: true)),
        s[3],
      ]),
    );
    final issue = result.issues.whereType<LowConfidenceVertices>().single;
    expect(issue.imprecise, ['v2']);
    expect(issue.mocked, ['v3']);
    expect(result.canSave, isTrue);
  });

  test('VAL-9: more than 5 000 vertices blocks saving', () {
    final ring = [
      for (var i = 0; i < 5001; i++)
        _v('v$i', -8.43 + 0.001 * (i / 5001), 40.2 + (i.isEven ? 0 : 0.0001)),
    ];
    final result = GeometryValidator.validate(singleRing(ring));
    expect(result.issues.whereType<TooManyVertices>().single.count, 5001);
    expect(result.canSave, isFalse);
  });

  test('an empty boundary is not savable', () {
    expect(GeometryValidator.validate(const []).canSave, isTrue);
    expect(GeometryValidator.validate(const []).measurements, isNull);
  });
}
