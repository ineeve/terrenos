/// Unfinished boundary edits, saved on every change (REG-12) so a crash or
/// a killed app never loses the work. Stored in `drafts/<id>.json`.
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
    required this.id,
    required this.parts,
    required this.updatedAt,
    this.propertyId,
  });

  factory fromJson(Map<String, Object?> json) => BoundaryDraft(
    id: json['id']! as String,
    propertyId: json['propertyId'] as String?,
    updatedAt: DateTime.parse(json['updatedAt']! as String),
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
  );

  final String id;

  /// The property being edited, or `null` for a new property.
  final String? propertyId;
  final BoundaryParts parts;
  final DateTime updatedAt;

  int get vertexCount =>
      parts.fold(0, (n, part) => n + part.fold(0, (m, r) => m + r.length));

  Map<String, Object?> toJson() => {
    'schema': 1,
    'id': id,
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

abstract interface class DraftStorage {
  Future<List<BoundaryDraft>> loadAll();
  Future<void> save(BoundaryDraft draft);
  Future<void> delete(String id);
}

class FileDraftStorage implements DraftStorage {
  new(this.directory);

  final Directory directory;

  static final _validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  AtomicFile _file(String id) {
    if (!_validId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Not a safe draft id');
    }
    return AtomicFile(p.join(directory.path, '$id.json'));
  }

  @override
  Future<List<BoundaryDraft>> loadAll() async {
    if (!directory.existsSync()) return const [];
    final drafts = <BoundaryDraft>[];
    for (final entity in directory.listSync().whereType<File>()) {
      final name = p.basename(entity.path);
      if (!name.endsWith('.json')) continue;
      try {
        final result = _file(name.substring(0, name.length - 5)).read(
          (text) =>
              BoundaryDraft.fromJson(jsonDecode(text) as Map<String, Object?>),
        );
        if (result != null) drafts.add(result.value);
      } on Object {
        // An unreadable draft is not worth blocking anything for.
      }
    }
    return drafts..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<void> save(BoundaryDraft draft) async {
    await directory.create(recursive: true);
    await _file(draft.id).write(jsonEncode(draft.toJson()));
  }

  @override
  Future<void> delete(String id) => _file(id).delete();
}

class MemoryDraftStorage implements DraftStorage {
  final drafts = <String, BoundaryDraft>{};

  @override
  Future<List<BoundaryDraft>> loadAll() async =>
      drafts.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> save(BoundaryDraft draft) async => drafts[draft.id] = draft;

  @override
  Future<void> delete(String id) async => drafts.remove(id);
}
