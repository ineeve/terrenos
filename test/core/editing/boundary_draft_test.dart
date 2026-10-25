import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:terrenos/core/editing/boundary_draft.dart';
import 'package:terrenos/core/model/vertex.dart';

BoundaryDraft _draft(String? propertyId, DateTime at, {int vertices = 3}) =>
    BoundaryDraft(
      propertyId: propertyId,
      parts: [
        [
          [
            for (var i = 0; i < vertices; i++)
              Vertex(
                id: 'v$i',
                lon: -8.43 + i / 1000,
                lat: 40.2 + (i.isEven ? 0 : 0.001),
                source: VertexSource.map,
              ),
          ],
        ],
      ],
      updatedAt: at,
    );

void main() {
  late Directory root;
  late FileDraftStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('terrenos_drafts_');
    store = FileDraftStore(Directory(p.join(root.path, 'drafts')));
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('a new property and each edited property have their own draft', () {
    expect(_draft(null, DateTime.utc(2026)).key, BoundaryDraft.newProperty);
    expect(_draft('abc', DateTime.utc(2026)).key, 'abc');
    expect(_draft(null, DateTime.utc(2026), vertices: 4).vertexCount, 4);
  });

  test('round-trips through a file', () async {
    final draft = _draft('p1', DateTime.utc(2026, 10, 25, 12));
    await store.save(draft);
    final loaded = store.load('p1')!;
    expect(loaded.propertyId, 'p1');
    expect(loaded.updatedAt, draft.updatedAt);
    expect(loaded.parts.single.single.map((v) => v.toJson()), [
      for (final v in draft.parts.single.single) v.toJson(),
    ]);
    expect(File(p.join(store.directory.path, 'p1.json')).existsSync(), isTrue);
  });

  test('lists drafts newest first and deletes them', () async {
    expect(store.loadAll(), isEmpty);
    await store.save(_draft(null, DateTime.utc(2026)));
    await store.save(_draft('p1', DateTime.utc(2026, 3)));
    await store.save(_draft('p2', DateTime.utc(2026, 2)));
    // A second save replaces the draft; the backup isn't listed.
    await store.save(_draft('p2', DateTime.utc(2026, 4)));
    expect(store.loadAll().map((d) => d.key), ['p2', 'p1', 'new']);

    await store.delete('p2');
    await store.delete('missing');
    expect(store.loadAll().map((d) => d.key), ['p1', 'new']);
  });

  test('quick saves without waiting end with the latest', () async {
    final saves = [
      for (var n = 3; n <= 12; n++)
        store.save(_draft('p1', DateTime.utc(2026, 1, n), vertices: n)),
    ];
    final deleting = store.delete('p1');
    final last = store.save(_draft('p1', DateTime.utc(2026, 2), vertices: 5));
    await Future.wait([...saves, deleting, last]);
    expect(store.load('p1')!.vertexCount, 5);
    expect(
      store.directory.listSync().map((f) => p.basename(f.path)),
      isNot(contains('p1.json.tmp')),
    );
  });

  test('an unreadable draft is ignored, not fatal', () async {
    await store.directory.create(recursive: true);
    File(p.join(store.directory.path, 'p9.json')).writeAsStringSync('{oops');
    expect(store.load('p9'), isNull);
    expect(store.loadAll(), isEmpty);
  });

  test('keys must be safe file names', () {
    expect(
      () => store.save(_draft('../escape', DateTime.utc(2026))),
      throwsArgumentError,
    );
    expect(store.load('../escape'), isNull);
  });

  test('the memory store behaves the same', () async {
    final memory = MemoryDraftStore();
    await memory.save(_draft(null, DateTime.utc(2026)));
    await memory.save(_draft('p1', DateTime.utc(2026, 2)));
    expect(memory.loadAll().map((d) => d.key), ['p1', 'new']);
    expect(memory.load('new'), isNotNull);
    await memory.delete('new');
    expect(memory.load('new'), isNull);
  });
}
