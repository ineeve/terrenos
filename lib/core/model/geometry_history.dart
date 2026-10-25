/// Boundary versions as a grow-only DAG (SPEC.md §9.5.3).
library;

import 'package:meta/meta.dart';
import 'package:terrenos/core/crdt/canonical_json.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/model/vertex.dart';

/// Parts → rings → vertices. Rings are open: the first vertex is not
/// repeated at the end.
typedef BoundaryParts = List<List<List<Vertex>>>;

@immutable
class GeometryVersion {
  new({
    required List<String> parents,
    required this.timestamp,
    required BoundaryParts parts,
  }) : parents = List.unmodifiable(parents.toSet().toList()..sort()),
       parts = List.unmodifiable([
         for (final part in parts)
           List<List<Vertex>>.unmodifiable([
             for (final ring in part) List<Vertex>.unmodifiable(ring),
           ]),
       ]);

  factory fromJson(Map<String, Object?> json) => GeometryVersion(
    parents: (json['parents']! as List).cast<String>(),
    timestamp: Hlc.parse(json['t']! as String),
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

  /// Hashes of the version(s) this one was edited from; empty for the first.
  final List<String> parents;
  final Hlc timestamp;
  final BoundaryParts parts;

  /// The key of this version: SHA-256 of `{parts, parents, t}`.
  late final String hash = canonicalHash(toJson());

  Iterable<Vertex> get vertices =>
      parts.expand((part) => part.expand((r) => r));

  Map<String, Object?> toJson() => {
    'parents': parents,
    't': timestamp.toString(),
    'parts': [
      for (final part in parts)
        [
          for (final ring in part) [for (final v in ring) v.toJson()],
        ],
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is GeometryVersion && other.hash == hash;

  @override
  int get hashCode => hash.hashCode;
}

@immutable
class GeometryHistory {
  const new([this.versions = const {}]);

  factory fromJson(Map<String, Object?> json) {
    final versions = <String, GeometryVersion>{};
    for (final entry in (json['versions']! as Map<String, Object?>).values) {
      final version = GeometryVersion.fromJson(entry! as Map<String, Object?>);
      // Keys are recomputed rather than trusted, so a corrupted or tampered
      // key can't make two different versions look identical.
      versions[version.hash] = version;
    }
    return GeometryHistory(Map.unmodifiable(versions));
  }

  final Map<String, GeometryVersion> versions;

  bool get isEmpty => versions.isEmpty;

  /// Versions that no other version lists as a parent.
  List<GeometryVersion> get heads {
    final referenced = {for (final v in versions.values) ...v.parents};
    return versions.values.where((v) => !referenced.contains(v.hash)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// The boundary to show: the head with the latest timestamp.
  GeometryVersion? get current {
    final h = heads;
    return h.isEmpty ? null : h.last;
  }

  /// Concurrent edits on different phones left more than one head.
  bool get hasConflict => heads.length > 1;

  /// Adds a version edited from all current heads. Resolving a conflict is
  /// the same operation: the new version descends from every head.
  GeometryHistory commit(BoundaryParts parts, Hlc timestamp) {
    final version = GeometryVersion(
      parents: [for (final h in heads) h.hash],
      timestamp: timestamp,
      parts: parts,
    );
    return GeometryHistory(
      Map.unmodifiable({...versions, version.hash: version}),
    );
  }

  /// Union of both histories (grow-only set).
  GeometryHistory merge(GeometryHistory other) =>
      GeometryHistory(Map.unmodifiable({...versions, ...other.versions}));

  Map<String, Object?> toJson() => {
    'versions': {
      for (final MapEntry(:key, :value) in versions.entries)
        key: value.toJson(),
    },
  };
}
