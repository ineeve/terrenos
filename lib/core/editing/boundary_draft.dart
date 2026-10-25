/// Crash-safe drafts of boundary edits (REG-12, SPEC.md §8.1).
///
/// Every change in the boundary editor is written to `drafts/<key>.json`,
/// where the key is the property's id, or `new` for a property not saved
/// yet. A draft left behind by a crash is offered on the next launch.
library;

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/storage/atomic_file.dart';

@immutable
class BoundaryDraft {
  const new({
    required this.propertyId,
    required this.parts,
    required this.updatedAt,
  });

  factory fromJson(Map<String, Object?> json) => BoundaryDraft(
    propertyId: json['propertyId'] as String?,
    parts: [
      for (final part in json['parts']! as List)
        [
          for (final ring in part as List)
            [
              for (final v in ring as List)
                Vertex.fromJson(v as Map<String, Object?>),
            ],
        ],
    ],
    updatedAt: DateTime.parse(json['updatedAt']! as String),
  );

  /// The key of the draft for a property that hasn't been saved yet.
  static const newProperty = 'new';

  /// `null` while drawing a new property.
  final String? propertyId;
  final BoundaryParts parts;
  final DateTime updatedAt;

  String get key => propertyId ?? newProperty;

  int get vertexCount => parts.fold(
    0,
    (sum, part) => sum + part.fold(0, (s, ring) => s + ring.length),
  );

  Map<String, Object?> toJson() => {
    'schema': 1,
    'propertyId': propertyId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'parts': [
      for (final part in parts)
        [
          for (final ring in part) [for (final v in ring) v.toJson()],
        ],
    ],
  };
}

/// Where drafts are kept. [FileDraftStore] writes files; tests use
/// [MemoryDraftStore].
abstract interface class DraftStorage {
  BoundaryDraft? load(String key);

  /// Every readable draft, newest first.
  List<BoundaryDraft> loadAll();

  Future<void> save(BoundaryDraft draft);
  Future<void> delete(String key);
}

class FileDraftStore implements DraftStorage {
  new(this.directory);

  final Directory directory;

  /// The last write or delete of each draft. The editor saves after every
  /// change without waiting, so writes to one draft run one at a time and
  /// the file always ends with the latest change.
  final _pending = <String, Future<void>>{};

  Future<void> _queue(String key, Future<void> Function() write) {
    final next = (_pending[key] ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) => write());
    _pending[key] = next;
    return next;
  }

  AtomicFile _file(String key) {
    if (!_validKey.hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'Not a safe draft key');
    }
    return AtomicFile(p.join(directory.path, '$key.json'));
  }

  static final _validKey = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// An unreadable draft is treated as absent; its file stays on disk.
  @override
  BoundaryDraft? load(String key) {
    try {
      return _file(key)
          .read(
            (text) => BoundaryDraft.fromJson(
              jsonDecode(text) as Map<String, Object?>,
            ),
          )
          ?.value;
    } on Object {
      return null;
    }
  }

  @override
  List<BoundaryDraft> loadAll() {
    if (!directory.existsSync()) return [];
    final keys = {
      for (final file in directory.listSync().whereType<File>())
        if (p.basename(file.path) case final name when name.endsWith('.json'))
          p.basenameWithoutExtension(name),
    };
    return [
      for (final key in keys)
        if (_validKey.hasMatch(key)) ?load(key),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<void> save(BoundaryDraft draft) {
    final file = _file(draft.key);
    final text = jsonEncode(draft.toJson());
    return _queue(draft.key, () async {
      await directory.create(recursive: true);
      await file.write(text);
    });
  }

  @override
  Future<void> delete(String key) {
    final file = _file(key);
    return _queue(key, file.delete);
  }
}

class MemoryDraftStore implements DraftStorage {
  final drafts = <String, BoundaryDraft>{};

  @override
  BoundaryDraft? load(String key) => drafts[key];

  @override
  List<BoundaryDraft> loadAll() =>
      drafts.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> save(BoundaryDraft draft) async => drafts[draft.key] = draft;

  @override
  Future<void> delete(String key) async => drafts.remove(key);
}
