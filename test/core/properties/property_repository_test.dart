import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/properties/property_repository.dart';
import 'package:terrenos/core/storage/document_store.dart';

class _Setup {
  new({Map<String, PropertyDocument>? existing, int wall = 1000})
    : storage = MemoryDocumentStorage((d) => d.id, existing) {
    var n = 0;
    repo = PropertyRepository(
      storage: storage,
      clock: HlcClock(deviceId: 'dev', wallClock: () => wall),
      onClockAdvanced: (hlc) async => persisted.add(hlc),
      newId: () => 'p${n++}',
    );
  }

  final MemoryDocumentStorage<PropertyDocument> storage;
  late final PropertyRepository repo;
  final persisted = <Hlc>[];
}

final _boundary = [
  [
    [
      Vertex(id: 'a', lon: -8.43, lat: 40.2, source: VertexSource.typed),
      Vertex(id: 'b', lon: -8.429, lat: 40.2, source: VertexSource.typed),
      Vertex(id: 'c', lon: -8.429, lat: 40.201, source: VertexSource.typed),
    ],
  ],
];

void main() {
  test('creates a property with fields and a boundary, and saves it', () async {
    final s = _Setup();
    final doc = await s.repo.create(
      name: '  Olival  ',
      boundary: _boundary,
      fields: {PropertyField.processNumber: '0012/2023-A'},
    );
    expect(doc.id, 'p0');
    expect(doc.name, 'Olival');
    expect(doc.processNumber, '0012/2023-A');
    expect(doc.geometry.current!.vertices, hasLength(3));
    expect(s.storage.documents['p0'], doc);
    expect(s.persisted.last, s.repo.clock.last);
  });

  test('every write gets a later timestamp', () async {
    final s = _Setup();
    final doc = await s.repo.create(name: 'A');
    final updated = await s.repo.setFields(doc.id, {PropertyField.notes: 'x'});
    expect(
      updated.fields[PropertyField.notes]!.timestamp >
          updated.fields[PropertyField.name]!.timestamp,
      isTrue,
    );
  });

  test('unchanged fields are not rewritten', () async {
    final s = _Setup();
    final doc = await s.repo.create(
      name: 'A',
      fields: {PropertyField.notes: 'x'},
    );
    final before = doc.fields[PropertyField.notes]!.timestamp;
    final after = await s.repo.setFields(doc.id, {PropertyField.notes: 'x'});
    expect(after.fields[PropertyField.notes]!.timestamp, before);
  });

  test('equal maps and lists are not rewritten either', () async {
    final s = _Setup();
    final doc = await s.repo.create(
      name: 'A',
      fields: {
        PropertyField.confrontations: {'n': 'Caminho'},
        PropertyField.owners: [
          {'name': 'Maria', 'share': 100},
        ],
      },
    );
    final after = await s.repo.setFields(doc.id, {
      PropertyField.confrontations: {'n': 'Caminho'},
      PropertyField.owners: [
        {'name': 'Maria', 'share': 100},
      ],
    });
    expect(after.docHash, doc.docHash);
  });

  test('lists live properties by name; deleted ones go to the bin', () async {
    final s = _Setup();
    final b = await s.repo.create(name: 'vinha');
    await s.repo.create(name: 'Amendoal');
    await s.repo.create(name: 'Olival');
    expect(s.repo.properties.map((d) => d.name), [
      'Amendoal',
      'Olival',
      'vinha',
    ]);

    await s.repo.delete(b.id);
    expect(s.repo.properties.map((d) => d.name), ['Amendoal', 'Olival']);
    expect(s.repo.deleted.single.id, b.id);

    await s.repo.restore(b.id);
    expect(s.repo.properties, hasLength(3));
  });

  test('saving a boundary adds a version on top of the current one', () async {
    final s = _Setup();
    final doc = await s.repo.create(name: 'A', boundary: _boundary);
    final first = doc.geometry.current!;
    final updated = await s.repo.saveBoundary(doc.id, _boundary);
    expect(updated.geometry.versions, hasLength(2));
    expect(updated.geometry.current!.parents, [first.hash]);
  });

  test('vertex info is stored separately from the boundary', () async {
    final s = _Setup();
    final doc = await s.repo.create(name: 'A', boundary: _boundary);
    final updated = await s.repo.setVertexInfo(doc.id, 'a', {
      'label': 'Marco Norte',
    });
    expect(updated.vertexInfo['a'], {'label': 'Marco Norte'});
    expect(updated.geometry.versions, hasLength(1));
  });

  test('loading restores the clock past the newest stored write', () async {
    final stored = PropertyDocument.create(
      id: 'old',
      name: 'From the future',
      timestamp: const Hlc(999999, 4, 'other'),
    );
    final s = _Setup(existing: {'old': stored});
    final changes = <void>[];
    s.repo.changes.listen(changes.add);
    await s.repo.load();
    expect(s.repo.properties.single.id, 'old');
    final next = await s.repo.create(name: 'New');
    expect(next.createdAt > stored.createdAt, isTrue);
    expect(changes, isNotEmpty);
    await s.repo.dispose();
  });

  test('unknown ids are rejected', () {
    final s = _Setup();
    expect(() => s.repo.delete('nope'), throwsArgumentError);
  });
}
