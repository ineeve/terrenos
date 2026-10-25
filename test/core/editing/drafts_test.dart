import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:terrenos/core/editing/drafts.dart';
import 'package:terrenos/core/model/vertex.dart';

BoundaryDraft _draft(String id, DateTime at, {String? propertyId}) =>
    BoundaryDraft(
      id: id,
      propertyId: propertyId,
      updatedAt: at,
      parts: [
        [
          [
            Vertex(
              id: 'a',
              lon: -8.43,
              lat: 40.2,
              source: VertexSource.typed,
              input: const CoordinateInput(
                crs: 'EPSG:3763',
                x: -26000.12,
                y: 58000.5,
              ),
            ),
            Vertex(id: 'b', lon: -8.429, lat: 40.2, source: VertexSource.map),
          ],
        ],
      ],
    );

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('drafts_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('drafts survive a restart, newest first, with typed input', () async {
    final storage = FileDraftStorage(Directory(p.join(dir.path, 'drafts')));
    await storage.save(_draft('old', DateTime.utc(2026)));
    await storage.save(_draft('new', DateTime.utc(2026, 2), propertyId: 'p1'));

    final loaded = await FileDraftStorage(Directory(p.join(dir.path, 'drafts')))
        .loadAll();
    expect(loaded.map((d) => d.id), ['new', 'old']);
    expect(loaded.first.propertyId, 'p1');
    expect(loaded.first.vertexCount, 2);
    expect(loaded.first.parts.single.single.first.input!.x, -26000.12);
  });

  test('deleting removes the draft; broken files are skipped', () async {
    final storage = FileDraftStorage(dir);
    await storage.save(_draft('a', DateTime.utc(2026)));
    File(p.join(dir.path, 'broken.json')).writeAsStringSync('{');
    expect((await storage.loadAll()).map((d) => d.id), ['a']);
    await storage.delete('a');
    expect(await storage.loadAll(), isEmpty);
  });

  test('a missing directory means no drafts', () async {
    expect(
      await FileDraftStorage(Directory(p.join(dir.path, 'none'))).loadAll(),
      isEmpty,
    );
  });

  test('ids that could escape the directory are rejected', () {
    expect(() => FileDraftStorage(dir).delete('../x'), throwsArgumentError);
  });

  test('memory storage behaves the same', () async {
    final storage = MemoryDraftStorage();
    await storage.save(_draft('a', DateTime.utc(2026)));
    await storage.save(_draft('b', DateTime.utc(2027)));
    expect((await storage.loadAll()).map((d) => d.id), ['b', 'a']);
    await storage.delete('b');
    expect((await storage.loadAll()).single.id, 'a');
  });
}
