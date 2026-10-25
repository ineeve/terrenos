/// Synced documents: properties and groups (SPEC.md §9.5).
///
/// Both are state-based CRDTs: every part is either a last-writer-wins
/// register, a last-writer-wins map, or a grow-only set. Document-level merge
/// is added with sync (PLAN.md T3.1); the parts already merge.
library;

import 'package:meta/meta.dart';
import 'package:terrenos/core/crdt/canonical_json.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/crdt/lww.dart';
import 'package:terrenos/core/model/geometry_history.dart';

/// Thrown for documents written by a newer version of the app. Such files
/// are left untouched rather than quarantined.
class UnsupportedSchemaException implements Exception {
  new(this.schema, this.supported);

  final int schema;
  final int supported;

  @override
  String toString() =>
      'Document schema $schema is newer than supported ($supported)';
}

int _checkSchema(Map<String, Object?> json, int supported) {
  final schema = json['schema'];
  if (schema is! int || schema < 1) {
    throw FormatException('Missing or invalid schema', schema);
  }
  if (schema > supported) throw UnsupportedSchemaException(schema, supported);
  return schema;
}

/// Keys of the attribute registers in [PropertyDocument.fields] (§3.6).
abstract final class PropertyField {
  static const name = 'name';
  static const processNumber = 'processNumber';
  static const type = 'type';
  static const landUse = 'landUse';
  static const matrixArticle = 'matrixArticle';
  static const matrixParish = 'matrixParish';
  static const registryDescription = 'registryDescription';
  static const cadastralSection = 'cadastralSection';

  /// `{"distrito": …, "concelho": …, "freguesia": …}`
  static const location = 'location';
  static const placeName = 'placeName';

  /// `{"n": …, "s": …, "e": …, "w": …}`
  static const confrontations = 'confrontations';

  /// `[{"name": …, "share": …}]`
  static const owners = 'owners';

  /// ISO date, `yyyy-MM-dd`.
  static const acquiredOn = 'acquiredOn';
  static const notes = 'notes';
  static const colour = 'colour';
  static const tags = 'tags';
}

@immutable
class PropertyDocument {
  const new({
    required this.id,
    required this.createdBy,
    required this.createdAt,
    required this.group,
    required this.deleted,
    this.fields = const {},
    this.geometry = const GeometryHistory(),
    this.vertexInfo = const LwwMap(),
    this.attachments = const LwwMap(),
  });

  /// A new private property with its required identifier name.
  factory create({
    required String id,
    required String name,
    required Hlc timestamp,
    String? groupId,
  }) => PropertyDocument(
    id: id,
    createdBy: timestamp.deviceId,
    createdAt: timestamp,
    group: LwwRegister(groupId, timestamp),
    deleted: LwwRegister(false, timestamp),
    fields: {PropertyField.name: LwwRegister(name, timestamp)},
  );

  factory fromJson(Map<String, Object?> json) {
    _checkSchema(json, schemaVersion);
    return PropertyDocument(
      id: json['id']! as String,
      createdBy: json['createdBy']! as String,
      createdAt: Hlc.parse(json['createdAt']! as String),
      group: LwwRegister<String?>.fromJson(
        json['group']! as Map<String, Object?>,
      ),
      deleted: LwwRegister<bool>.fromJson(
        json['deleted']! as Map<String, Object?>,
      ),
      fields: Map.unmodifiable({
        for (final MapEntry(:key, :value)
            in (json['fields']! as Map<String, Object?>).entries)
          key: LwwRegister<Object?>.fromJson(value! as Map<String, Object?>),
      }),
      geometry: GeometryHistory.fromJson(
        json['geometry']! as Map<String, Object?>,
      ),
      vertexInfo: LwwMap.fromJson(json['vertexInfo']! as Map<String, Object?>),
      attachments: LwwMap.fromJson(
        json['attachments']! as Map<String, Object?>,
      ),
    );
  }

  static const schemaVersion = 1;

  /// UUIDv7; never changes.
  final String id;
  final String createdBy;
  final Hlc createdAt;

  /// Group id, or `null` for a private property.
  final LwwRegister<String?> group;
  final LwwRegister<bool> deleted;
  final Map<String, LwwRegister<Object?>> fields;
  final GeometryHistory geometry;

  /// Label, note and photos per vertex id; kept apart from the geometry so
  /// renaming a marker never conflicts with re-surveying it.
  final LwwMap<Map<String, Object?>> vertexInfo;
  final LwwMap<Map<String, Object?>> attachments;

  String get name => (fields[PropertyField.name]?.value as String?) ?? '';
  String? get processNumber =>
      fields[PropertyField.processNumber]?.value as String?;
  String? get groupId => group.value;
  bool get isDeleted => deleted.value;

  Object? field(String key) => fields[key]?.value;

  /// SHA-256 of the canonical JSON; equal on every device holding the same
  /// state (sync index, §9.4).
  String get docHash => canonicalHash(toJson());

  PropertyDocument withField(String key, Object? value, Hlc timestamp) => _copy(
    fields: Map.unmodifiable({
      ...fields,
      key: LwwRegister<Object?>(value, timestamp),
    }),
  );

  PropertyDocument withGeometry(BoundaryParts parts, Hlc timestamp) =>
      _copy(geometry: geometry.commit(parts, timestamp));

  PropertyDocument withVertexInfo(
    String vertexId,
    Map<String, Object?>? info,
    Hlc timestamp,
  ) => _copy(vertexInfo: vertexInfo.put(vertexId, info, timestamp));

  PropertyDocument withAttachment(
    String attachmentId,
    Map<String, Object?>? attachment,
    Hlc timestamp,
  ) => _copy(attachments: attachments.put(attachmentId, attachment, timestamp));

  PropertyDocument withGroup(String? groupId, Hlc timestamp) =>
      _copy(group: LwwRegister(groupId, timestamp));

  PropertyDocument withDeleted({
    required bool deleted,
    required Hlc timestamp,
  }) => _copy(deleted: LwwRegister(deleted, timestamp));

  PropertyDocument _copy({
    LwwRegister<String?>? group,
    LwwRegister<bool>? deleted,
    Map<String, LwwRegister<Object?>>? fields,
    GeometryHistory? geometry,
    LwwMap<Map<String, Object?>>? vertexInfo,
    LwwMap<Map<String, Object?>>? attachments,
  }) => PropertyDocument(
    id: id,
    createdBy: createdBy,
    createdAt: createdAt,
    group: group ?? this.group,
    deleted: deleted ?? this.deleted,
    fields: fields ?? this.fields,
    geometry: geometry ?? this.geometry,
    vertexInfo: vertexInfo ?? this.vertexInfo,
    attachments: attachments ?? this.attachments,
  );

  /// The newest timestamp anywhere in the document. Used to restore the
  /// device clock on start-up, so the clock is never behind stored data.
  Hlc get latestTimestamp {
    var latest = createdAt;
    void see(Hlc t) {
      if (t > latest) latest = t;
    }

    see(group.timestamp);
    see(deleted.timestamp);
    for (final r in fields.values) {
      see(r.timestamp);
    }
    for (final v in geometry.versions.values) {
      see(v.timestamp);
    }
    for (final r in vertexInfo.entries.values) {
      see(r.timestamp);
    }
    for (final r in attachments.entries.values) {
      see(r.timestamp);
    }
    return latest;
  }

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'id': id,
    'createdBy': createdBy,
    'createdAt': createdAt.toString(),
    'group': group.toJson(),
    'deleted': deleted.toJson(),
    'fields': {
      for (final MapEntry(:key, :value) in fields.entries) key: value.toJson(),
    },
    'geometry': geometry.toJson(),
    'vertexInfo': vertexInfo.toJson(),
    'attachments': attachments.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is PropertyDocument && other.docHash == docHash;

  @override
  int get hashCode => docHash.hashCode;
}

@immutable
class GroupDocument {
  const new({
    required this.id,
    required this.name,
    required this.colour,
    this.members = const LwwMap(),
    this.removedProperties = const {},
  });

  factory fromJson(Map<String, Object?> json) {
    _checkSchema(json, schemaVersion);
    return GroupDocument(
      id: json['id']! as String,
      name: LwwRegister<String>.fromJson(json['name']! as Map<String, Object?>),
      colour: LwwRegister<String>.fromJson(
        json['colour']! as Map<String, Object?>,
      ),
      members: LwwMap.fromJson(json['members']! as Map<String, Object?>),
      removedProperties: Map.unmodifiable({
        for (final MapEntry(:key, :value)
            in (json['removedProperties']! as Map<String, Object?>).entries)
          key: Hlc.parse(value! as String),
      }),
    );
  }

  static const schemaVersion = 1;

  final String id;
  final LwwRegister<String> name;

  /// `#RRGGBB`
  final LwwRegister<String> colour;

  /// deviceId → `{"name": …, "joinedAt": …}`
  final LwwMap<Map<String, Object?>> members;

  /// Properties moved out of this group, with the time of the move
  /// (§9.5.5). Merges by keeping the later time.
  final Map<String, Hlc> removedProperties;

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'id': id,
    'name': name.toJson(),
    'colour': colour.toJson(),
    'members': members.toJson(),
    'removedProperties': {
      for (final MapEntry(:key, :value) in removedProperties.entries)
        key: value.toString(),
    },
  };

  @override
  bool operator ==(Object other) =>
      other is GroupDocument &&
      canonicalJson(other.toJson()) == canonicalJson(toJson());

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;
}
