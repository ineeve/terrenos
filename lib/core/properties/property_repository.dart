/// The properties on this phone: loading, and every local change
/// (SPEC.md §3.7, §8). Each change is stamped with the device clock and
/// written immediately, one file per property.
library;

import 'dart:async';

import 'package:terrenos/core/crdt/canonical_json.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/storage/document_store.dart';
import 'package:uuid/uuid.dart';

class PropertyRepository {
  new({
    required this.storage,
    required this.clock,
    required this.onClockAdvanced,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v7;

  final DocumentStorage<PropertyDocument> storage;
  final HlcClock clock;

  /// Called after every change so the clock can be persisted (§9.1).
  final Future<void> Function(Hlc last) onClockAdvanced;
  final String Function() _newId;

  final _documents = <String, PropertyDocument>{};
  final _changes = StreamController<void>.broadcast();

  /// Fires after every change.
  Stream<void> get changes => _changes.stream;

  /// Live properties, sorted by name.
  List<PropertyDocument> get properties =>
      _documents.values.where((d) => !d.isDeleted).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Deleted properties (the recycle bin, MGT-3).
  List<PropertyDocument> get deleted =>
      _documents.values.where((d) => d.isDeleted).toList();

  PropertyDocument? byId(String id) => _documents[id];

  Future<LoadReport<PropertyDocument>> load() async {
    final report = await storage.loadAll();
    _documents
      ..clear()
      ..addAll(report.documents);
    // The clock must never be behind data already on disk, e.g. if
    // device.json was restored from an older backup.
    for (final doc in _documents.values) {
      clock.receive(doc.latestTimestamp);
    }
    _changes.add(null);
    return report;
  }

  Future<PropertyDocument> create({
    required String name,
    BoundaryParts? boundary,
    Map<String, Object?> fields = const {},
    String? groupId,
  }) {
    var doc = PropertyDocument.create(
      id: _newId(),
      name: name.trim(),
      timestamp: clock.now(),
      groupId: groupId,
    );
    for (final MapEntry(:key, :value) in fields.entries) {
      doc = doc.withField(key, value, clock.now());
    }
    if (boundary != null) doc = doc.withGeometry(boundary, clock.now());
    return _put(doc);
  }

  /// Sets attribute fields; `null` clears a field.
  Future<PropertyDocument> setFields(String id, Map<String, Object?> fields) {
    var doc = _require(id);
    for (final MapEntry(:key, :value) in fields.entries) {
      // Compare as JSON: maps and lists are new objects on every save.
      final unchanged =
          doc.fields.containsKey(key) &&
          canonicalJson(doc.field(key)) == canonicalJson(value);
      if (!unchanged) {
        doc = doc.withField(key, value, clock.now());
      }
    }
    return _put(doc);
  }

  /// Saves a new boundary version (one per editing session, §9.5.3).
  Future<PropertyDocument> saveBoundary(String id, BoundaryParts parts) =>
      _put(_require(id).withGeometry(parts, clock.now()));

  Future<PropertyDocument> setVertexInfo(
    String id,
    String vertexId,
    Map<String, Object?>? info,
  ) => _put(_require(id).withVertexInfo(vertexId, info, clock.now()));

  /// Moves a property to the recycle bin (MGT-3).
  Future<PropertyDocument> delete(String id) =>
      _put(_require(id).withDeleted(deleted: true, timestamp: clock.now()));

  Future<PropertyDocument> restore(String id) =>
      _put(_require(id).withDeleted(deleted: false, timestamp: clock.now()));

  Future<void> dispose() => _changes.close();

  PropertyDocument _require(String id) =>
      _documents[id] ??
      (throw ArgumentError.value(id, 'id', 'No such property'));

  Future<PropertyDocument> _put(PropertyDocument doc) async {
    await storage.save(doc);
    _documents[doc.id] = doc;
    await onClockAdvanced(clock.last);
    _changes.add(null);
    return doc;
  }
}
