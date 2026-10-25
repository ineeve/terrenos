/// A directory of JSON documents, one file per document (SPEC.md §8).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:terrenos/core/crdt/canonical_json.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/storage/atomic_file.dart';

/// How to read, write and identify one kind of document.
///
/// [decode] runs in a background isolate, so it must be a top-level or static
/// function (a constructor tear-off such as `PropertyDocument.fromJson`).
class DocumentCodec<T> {
  const new({required this.decode, required this.encode, required this.idOf});

  final T Function(Map<String, Object?> json) decode;
  final Map<String, Object?> Function(T document) encode;
  final String Function(T document) idOf;
}

/// What happened while loading a directory.
class LoadReport<T> {
  new({
    required this.documents,
    required this.quarantined,
    required this.recovered,
    required this.needsNewerApp,
  });

  final Map<String, T> documents;

  /// Files that could not be read, moved to the quarantine directory.
  final List<String> quarantined;

  /// Documents restored from their `.bak` copy.
  final List<String> recovered;

  /// Files written by a newer app version; left untouched.
  final List<String> needsNewerApp;

  bool get hasProblems =>
      quarantined.isNotEmpty ||
      recovered.isNotEmpty ||
      needsNewerApp.isNotEmpty;
}

/// Where documents are kept. [DocumentStore] writes files; tests use
/// [MemoryDocumentStorage].
abstract interface class DocumentStorage<T> {
  Future<LoadReport<T>> loadAll();
  Future<void> save(T document);
  Future<void> delete(String id);
}

class MemoryDocumentStorage<T> implements DocumentStorage<T> {
  new(this.idOf, [Map<String, T>? documents]) : documents = documents ?? {};

  final String Function(T document) idOf;
  final Map<String, T> documents;

  @override
  Future<LoadReport<T>> loadAll() async => LoadReport(
    documents: Map.of(documents),
    quarantined: const [],
    recovered: const [],
    needsNewerApp: const [],
  );

  @override
  Future<void> save(T document) async => documents[idOf(document)] = document;

  @override
  Future<void> delete(String id) async => documents.remove(id);
}

class DocumentStore<T> implements DocumentStorage<T> {
  new({required this.directory, required this.quarantine, required this.codec});

  final Directory directory;
  final Directory quarantine;
  final DocumentCodec<T> codec;

  /// Reads every document in a background isolate, so start-up stays smooth
  /// with many properties (§8.2).
  @override
  Future<LoadReport<T>> loadAll() {
    final dir = directory.path;
    final quarantineDir = quarantine.path;
    final decode = codec.decode;
    return Isolate.run(() => _loadAll(dir, quarantineDir, decode));
  }

  @override
  Future<void> save(T document) =>
      _file(codec.idOf(document)).write(canonicalJson(codec.encode(document)));

  @override
  Future<void> delete(String id) => _file(id).delete();

  AtomicFile _file(String id) {
    if (!_validId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Not a safe document id');
    }
    return AtomicFile(p.join(directory.path, '$id.json'));
  }

  /// Ids become file names, so only allow characters that can't escape the
  /// directory or clash with the `.tmp`/`.bak` suffixes.
  static final _validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
}

LoadReport<T> _loadAll<T>(
  String dirPath,
  String quarantinePath,
  T Function(Map<String, Object?>) decode,
) {
  final documents = <String, T>{};
  final quarantined = <String>[];
  final recovered = <String>[];
  final needsNewerApp = <String>[];

  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    return LoadReport(
      documents: documents,
      quarantined: quarantined,
      recovered: recovered,
      needsNewerApp: needsNewerApp,
    );
  }

  // A document may exist only as `.bak` if a crash happened between the two
  // renames of a write, so collect ids from both kinds of file.
  final ids = <String>{};
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (name.endsWith('.json')) {
      ids.add(name.substring(0, name.length - '.json'.length));
    } else if (name.endsWith('.json.bak')) {
      ids.add(name.substring(0, name.length - '.json.bak'.length));
    }
  }

  for (final id in ids) {
    final file = AtomicFile(p.join(dirPath, '$id.json'));
    try {
      final result = file.read(
        (text) => decode(jsonDecode(text) as Map<String, Object?>),
      );
      if (result == null) continue;
      documents[id] = result.value;
      if (result.recoveredFromBackup) recovered.add(id);
    } on UnsupportedSchemaException {
      needsNewerApp.add(id);
    } on Object {
      _moveToQuarantine(file, quarantinePath);
      quarantined.add(id);
    }
  }

  return LoadReport(
    documents: documents,
    quarantined: quarantined,
    recovered: recovered,
    needsNewerApp: needsNewerApp,
  );
}

/// Bad files are never deleted silently; they are kept for diagnosis.
void _moveToQuarantine(AtomicFile file, String quarantinePath) {
  final target = Directory(quarantinePath)..createSync(recursive: true);
  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  for (final f in [file.file, file.backup]) {
    if (f.existsSync()) {
      f.renameSync(p.join(target.path, '$stamp-${p.basename(f.path)}'));
    }
  }
}
