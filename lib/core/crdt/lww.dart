/// Last-writer-wins registers and maps (SPEC.md §9.5.2).
library;

import 'package:meta/meta.dart';
import 'package:terrenos/core/crdt/canonical_json.dart';
import 'package:terrenos/core/crdt/hlc.dart';

/// A value together with the [Hlc] of the write that set it.
///
/// Values are JSON values (`null`, `bool`, `num`, `String`, `List`, `Map`).
@immutable
class LwwRegister<T> {
  const new(this.value, this.timestamp);

  factory fromJson(Map<String, Object?> json) =>
      LwwRegister<T>(json['v'] as T, Hlc.parse(json['t']! as String));

  final T value;
  final Hlc timestamp;

  /// Returns the register with the later timestamp.
  ///
  /// Equal timestamps only occur when both sides hold the same write, but if
  /// the values ever differ the tie is broken on their canonical JSON, so the
  /// result is still the same on every device.
  LwwRegister<T> merge(LwwRegister<T> other) {
    final order = timestamp.compareTo(other.timestamp);
    if (order > 0) return this;
    if (order < 0) return other;
    return canonicalJson(value).compareTo(canonicalJson(other.value)) >= 0
        ? this
        : other;
  }

  Map<String, Object?> toJson() => {'v': value, 't': timestamp.toString()};

  @override
  bool operator ==(Object other) =>
      other is LwwRegister<T> &&
      other.timestamp == timestamp &&
      canonicalJson(other.value) == canonicalJson(value);

  @override
  int get hashCode => Object.hash(timestamp, canonicalJson(value));
}

/// A map of [LwwRegister]s. A `null` value marks a removed entry; it is kept
/// so that the removal also wins on other devices.
@immutable
class LwwMap<T extends Object> {
  const new([this.entries = const {}]);

  factory fromJson(Map<String, Object?> json) => LwwMap<T>({
    for (final MapEntry(:key, :value) in json.entries)
      key: LwwRegister<T?>.fromJson(value! as Map<String, Object?>),
  });

  final Map<String, LwwRegister<T?>> entries;

  /// Live (non-removed) values.
  Map<String, T> get values => {
    for (final MapEntry(:key, :value) in entries.entries)
      if (value.value != null) key: value.value!,
  };

  T? operator [](String key) => entries[key]?.value;

  LwwMap<T> put(String key, T? value, Hlc timestamp) =>
      merge(LwwMap<T>({key: LwwRegister<T?>(value, timestamp)}));

  LwwMap<T> remove(String key, Hlc timestamp) => put(key, null, timestamp);

  LwwMap<T> merge(LwwMap<T> other) {
    final merged = Map<String, LwwRegister<T?>>.of(entries);
    for (final MapEntry(:key, :value) in other.entries.entries) {
      final mine = merged[key];
      merged[key] = mine == null ? value : mine.merge(value);
    }
    return LwwMap<T>(Map.unmodifiable(merged));
  }

  Map<String, Object?> toJson() => {
    for (final MapEntry(:key, :value) in entries.entries) key: value.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is LwwMap<T> &&
      canonicalJson(other.toJson()) == canonicalJson(toJson());

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;
}
