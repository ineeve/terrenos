import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/editing/boundary_editor.dart';
import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/identifiers.dart';
import 'package:terrenos/core/model/vertex.dart';

GpsFix _fix({double accuracy = 4}) => GpsFix(
  accuracyMetres: accuracy,
  samples: 5,
  capturedAt: DateTime.utc(2026, 10, 25, 10),
  mocked: false,
  deviceId: 'dev',
);

BoundaryEditor _square() {
  final editor = BoundaryEditor(random: Random(7));
  for (final (lon, lat) in [
    (-8.4300, 40.2000),
    (-8.4290, 40.2000),
    (-8.4290, 40.2010),
    (-8.4300, 40.2010),
  ]) {
    editor.add((lon: lon, lat: lat), source: VertexSource.map);
  }
  return editor;
}

List<String> _ids(BoundaryEditor e) => e.ring().map((v) => v.id).toList();

void main() {
  group('BoundaryEditor', () {
    test('adds vertices with unique 8-hex ids', () {
      final e = _square();
      final ids = _ids(e);
      expect(ids.toSet(), hasLength(4));
      expect(ids.every((id) => RegExp(r'^[0-9a-f]{8}$').hasMatch(id)), isTrue);
    });

    test('never reuses an id from history, even with a repeating random', () {
      // Random(0) always starts with the same value; the editor must skip it.
      final first = BoundaryEditor(random: Random(0))
          .add((lon: -8, lat: 40), source: VertexSource.map)
          .id;
      final editor = BoundaryEditor(random: Random(0), usedIds: [first]);
      expect(
        editor.add((lon: -8, lat: 40), source: VertexSource.map).id,
        isNot(first),
      );
    });

    test('adds after a given vertex', () {
      final e = _square();
      final second = e.ring()[1].id;
      final added = e.add(
        (lon: -8.4285, lat: 40.2005),
        source: VertexSource.typed,
        afterId: second,
      );
      expect(_ids(e).indexOf(added.id), 2);
      expect(
        () => e.add((lon: 0, lat: 0), source: VertexSource.map, afterId: 'x'),
        throwsArgumentError,
      );
    });

    test('adds a whole track as one undo step (REG-3)', () {
      final e = _square();
      final added = e.addAll([
        (position: (lon: -8.4310, lat: 40.2010), gps: _fix()),
        (position: (lon: -8.4310, lat: 40.2000), gps: _fix(accuracy: 6)),
      ], source: VertexSource.gps);
      expect(e.ring(), hasLength(6));
      expect(e.ring().sublist(4), added);
      expect(added.map((v) => v.source), everyElement(VertexSource.gps));
      expect(added.last.gps!.accuracyMetres, 6);
      expect(
        added.map((v) => v.id).toSet().intersection(_ids(e).take(4).toSet()),
        isEmpty,
      );
      e.undo();
      expect(e.ring(), hasLength(4));
    });

    test('inserts into the nearest edge', () {
      final e = _square();
      final ids = _ids(e);
      // Just outside the east edge (between vertices 2 and 3).
      final added = e.insertIntoNearestEdge(
        (lon: -8.42895, lat: 40.2005),
        source: VertexSource.gps,
        gps: _fix(),
      );
      expect(_ids(e), [ids[0], ids[1], added.id, ids[2], ids[3]]);
    });

    test('inserting with fewer than 3 vertices appends', () {
      final e = BoundaryEditor(random: Random(1))
        ..add((lon: -8, lat: 40), source: VertexSource.map);
      final v = e.insertIntoNearestEdge((
        lon: -8.001,
        lat: 40,
      ), source: VertexSource.map);
      expect(_ids(e).last, v.id);
    });

    test('moving keeps the id; typed input is kept, other moves clear it', () {
      final e = _square();
      final id = e.ring().first.id;
      const input = CoordinateInput(crs: 'EPSG:3763', x: -26000, y: 58000);
      e.move(
        id,
        (lon: -8.431, lat: 40.2),
        source: VertexSource.typed,
        input: input,
      );
      expect(e.byId(id)!.input, input);
      expect(e.byId(id)!.source, VertexSource.typed);

      e.move(id, (lon: -8.4305, lat: 40.2), source: VertexSource.map);
      expect(e.byId(id)!.input, isNull);
      expect(e.byId(id)!.id, id);
    });

    test('survey: confirm keeps the position and marks it surveyed', () {
      final e = _square();
      final v = e.ring().first;
      expect(v.isSurveyed, isFalse);
      e.confirm(v.id, _fix());
      final confirmed = e.byId(v.id)!;
      expect(confirmed.isSurveyed, isTrue);
      expect((confirmed.lon, confirmed.lat), (v.lon, v.lat));
    });

    test('delete, reorder, reverse and start at', () {
      final e = _square();
      final [a, b, c, d] = _ids(e);
      e.reorder(0, 2);
      expect(_ids(e), [b, c, a, d]);
      e.reverse();
      expect(_ids(e), [b, d, a, c]);
      e.startAt(a);
      expect(_ids(e), [a, c, b, d]);
      e.delete(c);
      expect(_ids(e), [a, b, d]);
      expect(() => e.delete('missing'), throwsArgumentError);
      expect(() => e.startAt('missing'), throwsArgumentError);
    });

    test('undo and redo walk the history; a new edit clears redo', () {
      final e = _square();
      final before = _ids(e);
      final last = before.last;
      e.delete(last);
      expect(e.canUndo, isTrue);
      e.undo();
      expect(_ids(e), before);
      expect(e.canRedo, isTrue);
      e.redo();
      expect(_ids(e), before.sublist(0, 3));
      e
        ..undo()
        ..reverse();
      expect(e.canRedo, isFalse);
    });

    test('keeps at least 50 undo steps', () {
      final e = BoundaryEditor(random: Random(3));
      for (var i = 0; i < 60; i++) {
        e.add((lon: -8 + i * 1e-4, lat: 40), source: VertexSource.map);
      }
      var steps = 0;
      while (e.canUndo) {
        e.undo();
        steps++;
      }
      expect(steps, greaterThanOrEqualTo(50));
    });

    test('replaceAll is undoable and remembers the new ids', () {
      final e = _square();
      final original = e.parts;
      e.replaceAll([
        [
          [
            Vertex(
              id: 'aaaaaaaa',
              lon: -8,
              lat: 40,
              source: VertexSource.import,
            ),
          ],
        ],
      ]);
      expect(_ids(e), ['aaaaaaaa']);
      e.undo();
      expect(e.parts, original);
    });
  });

  group('compareSurvey (VTX-9)', () {
    final stored = Vertex(
      id: 'a',
      lon: -8.43,
      lat: 40.2,
      source: VertexSource.typed,
    );

    test('reports distance and direction', () {
      // ~3.2 m north-east.
      final result = compareSurvey(stored, (
        lon: -8.42997,
        lat: 40.20002,
      ), _fix());
      expect(result.distanceMetres, closeTo(3.45, 0.1));
      expect(result.direction, CompassDirection.northEast);
      expect(result.suggestKeep, isTrue);
    });

    test('suggests replacing when the offset exceeds the accuracy', () {
      final result = compareSurvey(stored, (
        lon: -8.43,
        lat: 40.2001,
      ), _fix(accuracy: 5));
      expect(result.distanceMetres, closeTo(11.1, 0.1));
      expect(result.direction, CompassDirection.north);
      expect(result.suggestKeep, isFalse);
    });
  });

  group('Identifiers', () {
    test('names (IDN-1)', () {
      expect(Identifiers.validateName('  Olival  '), isNull);
      expect(Identifiers.validateName('   '), NameError.empty);
      expect(Identifiers.validateName('x' * 81), NameError.tooLong);
      expect(Identifiers.validateName('Quinta n.º 3 — Cão'), isNull);
    });

    test('process numbers (IDN-3)', () {
      expect(Identifiers.validateProcessNumber('0012/2023-A'), isNull);
      expect(Identifiers.validateProcessNumber(''), isNull);
      expect(Identifiers.validateProcessNumber('P.º 12_3'), isNull);
      expect(
        Identifiers.validateProcessNumber('12#3'),
        ProcessNumberError.invalidCharacters,
      );
      expect(
        Identifiers.validateProcessNumber('1' * 41),
        ProcessNumberError.tooLong,
      );
      expect(Identifiers.storedProcessNumber('  000123/A '), '000123/A');
      expect(Identifiers.storedProcessNumber('   '), isNull);
    });

    test('duplicates by normalised process number and name (IDN-2, IDN-4)', () {
      PropertyDocument doc(
        String id,
        String name,
        String? number, {
        bool deleted = false,
      }) {
        var d = PropertyDocument.create(
          id: id,
          name: name,
          timestamp: const Hlc(1, 0, 'd'),
        );
        if (number != null) {
          d = d.withField(
            PropertyField.processNumber,
            number,
            const Hlc(2, 0, 'd'),
          );
        }
        return deleted
            ? d.withDeleted(deleted: true, timestamp: const Hlc(3, 0, 'd'))
            : d;
      }

      final docs = [
        doc('p1', 'Olival do Ribeiro', '0012/2023-A'),
        doc('p2', 'Vinha', '0099/2023'),
        doc('p3', 'Olival  do ribeiro', null),
        doc('p4', 'Mato', '0012-2023-a', deleted: true),
      ];
      expect(
        Identifiers.sameProcessNumber('0012 / 2023-a', docs).map((d) => d.id),
        ['p1'],
      );
      expect(
        Identifiers.sameProcessNumber('0012/2023-A', docs, exceptId: 'p1'),
        isEmpty,
      );
      expect(Identifiers.sameProcessNumber('  ', docs), isEmpty);
      expect(
        Identifiers.sameName(' olival do RIBEIRO', docs).map((d) => d.id),
        ['p1', 'p3'],
      );
      expect(Identifiers.normalizeProcessNumber('0012 / 2023-A'), '00122023a');
    });
  });
}
