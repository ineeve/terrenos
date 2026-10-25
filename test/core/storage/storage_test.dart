import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/storage/app_directories.dart';
import 'package:terrenos/core/storage/atomic_file.dart';
import 'package:terrenos/core/storage/document_store.dart';

const _codec = DocumentCodec<PropertyDocument>(
  decode: PropertyDocument.fromJson,
  encode: _encode,
  idOf: _idOf,
);

Map<String, Object?> _encode(PropertyDocument d) => d.toJson();
String _idOf(PropertyDocument d) => d.id;

PropertyDocument _doc(String id, String name) => PropertyDocument.create(
  id: id,
  name: name,
  timestamp: const Hlc(1, 0, 'dev'),
);

void main() {
  late Directory root;
  late AppDirectories dirs;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('terrenos_test_');
    dirs = AppDirectories(root);
    await dirs.ensureCreated();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('AtomicFile', () {
    test('keeps the previous version as a backup', () async {
      final file = AtomicFile(p.join(root.path, 'a.json'));
      await file.write('one');
      await file.write('two');
      expect(file.file.readAsStringSync(), 'two');
      expect(file.backup.readAsStringSync(), 'one');
      expect(File('${file.file.path}.tmp').existsSync(), isFalse);
    });

    test('falls back to the backup when the main file is corrupt', () async {
      final file = AtomicFile(p.join(root.path, 'a.json'));
      await file.write('good');
      await file.write('also good');
      file.file.writeAsStringSync('garbage');

      final result = file.read((text) {
        if (text == 'garbage') throw const FormatException();
        return text;
      });
      expect(result!.value, 'good');
      expect(result.recoveredFromBackup, isTrue);
    });

    test('reads the backup if a crash happened between renames', () async {
      final file = AtomicFile(p.join(root.path, 'a.json'));
      await file.write('only backup');
      file.file.renameSync(file.backup.path);
      expect(file.read((t) => t)!.value, 'only backup');
    });

    test('returns null when nothing exists and rethrows bad data', () {
      final file = AtomicFile(p.join(root.path, 'missing.json'));
      expect(file.read((t) => t), isNull);

      file.writeSync('bad');
      expect(
        () => file.read<String>((_) => throw const FormatException('x')),
        throwsFormatException,
      );
    });

    test('delete removes every copy', () async {
      final file = AtomicFile(p.join(root.path, 'a.json'));
      await file.write('1');
      await file.write('2');
      await file.delete();
      expect(root.listSync().whereType<File>(), isEmpty);
    });
  });

  group('DocumentStore', () {
    DocumentStore<PropertyDocument> store() => DocumentStore(
      directory: dirs.properties,
      quarantine: dirs.quarantine,
      codec: _codec,
    );

    test('saves and loads documents', () async {
      final s = store();
      await s.save(_doc('p1', 'Olival'));
      await s.save(_doc('p2', 'Vinha'));
      final report = await s.loadAll();
      expect(report.documents.keys, unorderedEquals(['p1', 'p2']));
      expect(report.documents['p1']!.name, 'Olival');
      expect(report.hasProblems, isFalse);
    });

    test('quarantines unreadable files instead of deleting them', () async {
      final s = store();
      await s.save(_doc('good', 'Olival'));
      File(p.join(dirs.properties.path, 'bad.json')).writeAsStringSync('{');

      final report = await s.loadAll();
      expect(report.documents.keys, ['good']);
      expect(report.quarantined, ['bad']);
      expect(
        dirs.quarantine.listSync().map((f) => p.basename(f.path)).single,
        endsWith('bad.json'),
      );
    });

    test('recovers from the backup and reports it', () async {
      final s = store();
      await s.save(_doc('p1', 'First'));
      await s.save(_doc('p1', 'Second'));
      File(p.join(dirs.properties.path, 'p1.json')).writeAsStringSync('{');

      final report = await s.loadAll();
      expect(report.documents['p1']!.name, 'First');
      expect(report.recovered, ['p1']);
    });

    test('leaves documents from a newer app untouched', () async {
      final file = File(p.join(dirs.properties.path, 'future.json'))
        ..writeAsStringSync('{"schema": 99}');
      final report = await store().loadAll();
      expect(report.needsNewerApp, ['future']);
      expect(report.documents, isEmpty);
      expect(file.existsSync(), isTrue);
    });

    test('rejects ids that could escape the directory', () {
      expect(() => store().delete('../device'), throwsArgumentError);
      expect(() => store().delete('a.json'), throwsArgumentError);
    });

    test('loading a missing directory gives an empty result', () async {
      dirs.properties.deleteSync(recursive: true);
      final report = await store().loadAll();
      expect(report.documents, isEmpty);
    });
  });
}
