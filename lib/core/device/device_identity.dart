/// This phone's identity for sync, stored in `device.json` (SPEC.md §9.1).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/storage/atomic_file.dart';

@immutable
class DeviceIdentity {
  const new({
    required this.deviceId,
    required this.displayName,
    required this.lastTimestamp,
  });

  /// A new identity with a random 128-bit id (32 hex characters).
  factory generate([Random? random]) {
    final rng = random ?? Random.secure();
    final id = List.generate(
      16,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return DeviceIdentity(
      deviceId: id,
      displayName: '',
      lastTimestamp: Hlc.zero(id),
    );
  }

  factory fromJson(Map<String, Object?> json) {
    final id = json['deviceId']! as String;
    if (!_validId.hasMatch(id)) {
      throw FormatException('Invalid device id', id);
    }
    return DeviceIdentity(
      deviceId: id,
      displayName: json['name'] as String? ?? '',
      lastTimestamp: switch (json['hlc']) {
        final String s => Hlc.parse(s),
        _ => Hlc.zero(id),
      },
    );
  }

  static final _validId = RegExp(r'^[0-9a-f]{32}$');

  /// Maximum length of [displayName].
  static const maxNameLength = 40;

  final String deviceId;

  /// Shown to other group members, e.g. "Telemóvel da Maria".
  final String displayName;

  /// The clock's last value, so it never goes backwards across restarts.
  final Hlc lastTimestamp;

  DeviceIdentity copyWith({String? displayName, Hlc? lastTimestamp}) =>
      DeviceIdentity(
        deviceId: deviceId,
        displayName: displayName ?? this.displayName,
        lastTimestamp: lastTimestamp ?? this.lastTimestamp,
      );

  Map<String, Object?> toJson() => {
    'schema': 1,
    'deviceId': deviceId,
    'name': displayName,
    'hlc': lastTimestamp.toString(),
  };

  @override
  bool operator ==(Object other) =>
      other is DeviceIdentity &&
      other.deviceId == deviceId &&
      other.displayName == displayName &&
      other.lastTimestamp == lastTimestamp;

  @override
  int get hashCode => Object.hash(deviceId, displayName, lastTimestamp);
}

abstract interface class DeviceRepository {
  /// Loads the identity, creating and saving a new one on first run.
  DeviceIdentity loadOrCreate();
  Future<void> save(DeviceIdentity identity);
}

class FileDeviceRepository implements DeviceRepository {
  new(File file) : _file = AtomicFile(file.path);

  final AtomicFile _file;

  @override
  DeviceIdentity loadOrCreate() {
    // Unlike settings, a broken device file must not be silently replaced:
    // a new id would make this phone look like a different device to its
    // groups. Errors propagate so start-up can report them.
    final existing = _file.read(
      (text) =>
          DeviceIdentity.fromJson(jsonDecode(text) as Map<String, Object?>),
    );
    if (existing != null) return existing.value;
    final created = DeviceIdentity.generate();
    _file.writeSync(jsonEncode(created.toJson()));
    return created;
  }

  @override
  Future<void> save(DeviceIdentity identity) =>
      _file.write(jsonEncode(identity.toJson()));
}

class MemoryDeviceRepository implements DeviceRepository {
  new([DeviceIdentity? identity])
    : identity = identity ?? DeviceIdentity.generate();

  DeviceIdentity identity;

  @override
  DeviceIdentity loadOrCreate() => identity;

  @override
  Future<void> save(DeviceIdentity identity) async => this.identity = identity;
}
