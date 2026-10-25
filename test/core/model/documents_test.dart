import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/crdt/canonical_json.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/crdt/lww.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';

const _maria = 'maria';
const _joao = 'joao';

Hlc _t(int millis, [String device = _maria]) => Hlc(millis, 0, device);

BoundaryParts _square({double shift = 0, String idPrefix = 'v'}) => [
  [
    [
      Vertex(
        id: '${idPrefix}1',
        lon: -8.6291 + shift,
        lat: 41.1579,
        source: VertexSource.gps,
        gps: GpsFix(
          accuracyMetres: 3.8,
          samples: 5,
          capturedAt: DateTime.utc(2026, 10, 25, 10, 12, 44),
          mocked: false,
          deviceId: _maria,
        ),
      ),
      Vertex(
        id: '${idPrefix}2',
        lon: -8.628,
        lat: 41.1579,
        source: VertexSource.typed,
        input: const CoordinateInput(
          crs: 'EPSG:3763',
          x: -41234.56,
          y: 164321.78,
        ),
      ),
      Vertex(
        id: '${idPrefix}3',
        lon: -8.628,
        lat: 41.1588,
        source: VertexSource.map,
      ),
      Vertex(
        id: '${idPrefix}4',
        lon: -8.6291,
        lat: 41.1588,
        source: VertexSource.import,
      ),
    ],
  ],
];

/// Encodes and decodes through real JSON text, the way the file store does.
Map<String, Object?> _viaText(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('Vertex', () {
    test('rounds coordinates to 7 decimal places', () {
      final v = Vertex(
        id: 'a',
        lon: -8.62910004,
        lat: 41.15790006,
        source: VertexSource.map,
      );
      expect(v.lon, -8.6291);
      expect(v.lat, 41.1579001);
    });

    test('is surveyed only with a GPS fix', () {
      final parts = _square();
      expect(parts[0][0][0].isSurveyed, isTrue);
      expect(parts[0][0][1].isSurveyed, isFalse);
    });

    test('rejects unknown sources', () {
      expect(() => VertexSource.fromCode('laser'), throwsFormatException);
    });
  });

  group('GeometryHistory', () {
    test('a single line of edits has one head', () {
      var history = const GeometryHistory();
      expect(history.current, isNull);
      history = history.commit(_square(), _t(1));
      final first = history.current!;
      history = history.commit(_square(shift: 0.0001), _t(2));
      expect(history.versions, hasLength(2));
      expect(history.heads, hasLength(1));
      expect(history.current!.parents, [first.hash]);
      expect(history.hasConflict, isFalse);
    });

    test('concurrent edits on two phones become a conflict', () {
      final base = const GeometryHistory().commit(_square(), _t(1));
      final onMaria = base.commit(_square(shift: 0.0001), _t(5));
      final onJoao = base.commit(_square(shift: -0.0001), _t(3, _joao));

      final merged = onMaria.merge(onJoao);
      expect(merged.hasConflict, isTrue);
      expect(merged.heads, hasLength(2));
      // The latest head is shown until someone resolves the conflict.
      expect(merged.current, onMaria.current);
      expect(onJoao.merge(onMaria).current, onMaria.current);

      final resolved = merged.commit(_square(), _t(6, _joao));
      expect(resolved.hasConflict, isFalse);
      expect(resolved.current!.parents, hasLength(2));
    });

    test('version keys are recomputed when reading', () {
      final history = const GeometryHistory().commit(_square(), _t(1));
      final json = history.toJson();
      final versions = json['versions']! as Map<String, Object?>;
      final tampered = {
        'versions': {'not-the-hash': versions.values.single},
      };
      expect(
        GeometryHistory.fromJson(_viaText(tampered)).versions.keys,
        history.versions.keys,
      );
    });
  });

  group('PropertyDocument', () {
    PropertyDocument sample() =>
        PropertyDocument.create(
              id: '01929f3a-7c1e-7b2a-9d4e-3f5a6b7c8d9e',
              name: 'Olival do Ribeiro',
              timestamp: _t(1),
            )
            .withField(PropertyField.processNumber, '0012/2023-A', _t(2))
            .withField(PropertyField.confrontations, {
              'n': 'Caminho público',
              's': 'José Silva',
            }, _t(3))
            .withField(PropertyField.owners, [
              {'name': 'Maria Fernandes', 'share': 100},
            ], _t(4))
            .withGeometry(_square(), _t(5))
            .withVertexInfo('v1', {'label': 'Marco Norte'}, _t(6))
            .withAttachment('att1', {'kind': 'photo', 'sha256': 'abc'}, _t(7));

    test('round-trips through JSON text without changing its hash', () {
      final doc = sample();
      final restored = PropertyDocument.fromJson(_viaText(doc.toJson()));
      expect(restored, doc);
      expect(restored.docHash, doc.docHash);
      expect(canonicalJson(restored.toJson()), canonicalJson(doc.toJson()));
    });

    test('exposes name, process number, group and deletion', () {
      final doc = sample();
      expect(doc.name, 'Olival do Ribeiro');
      expect(doc.processNumber, '0012/2023-A');
      expect(doc.groupId, isNull);
      expect(doc.isDeleted, isFalse);
      expect(doc.geometry.current!.vertices, hasLength(4));

      final moved = doc
          .withGroup('g1', _t(8))
          .withDeleted(deleted: true, timestamp: _t(9));
      expect(moved.groupId, 'g1');
      expect(moved.isDeleted, isTrue);
    });

    test('process numbers are stored exactly as typed', () {
      final doc = sample().withField(
        PropertyField.processNumber,
        '000123/A',
        _t(10),
      );
      final restored = PropertyDocument.fromJson(_viaText(doc.toJson()));
      expect(restored.processNumber, '000123/A');
    });

    test('latestTimestamp finds the newest write anywhere', () {
      expect(sample().latestTimestamp, _t(7));
    });

    test('rejects documents from a newer app version', () {
      final json = sample().toJson()..['schema'] = 99;
      expect(
        () => PropertyDocument.fromJson(json),
        throwsA(isA<UnsupportedSchemaException>()),
      );
      json['schema'] = null;
      expect(() => PropertyDocument.fromJson(json), throwsFormatException);
    });
  });

  group('GroupDocument', () {
    test('round-trips through JSON text', () {
      final group = GroupDocument(
        id: 'g1',
        name: LwwRegister('Família Fernandes', _t(1)),
        colour: LwwRegister('#2E7D32', _t(1)),
        members: const LwwMap<Map<String, Object?>>().put(_maria, {
          'name': 'Telemóvel da Maria',
        }, _t(1)),
        removedProperties: {'p1': _t(2)},
      );
      expect(GroupDocument.fromJson(_viaText(group.toJson())), group);
    });
  });
}
