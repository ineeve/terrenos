/// Hybrid Logical Clock timestamps (SPEC.md §9.1).
///
/// A timestamp is `<epochMillis:13>:<counter:4 hex>:<deviceId>`. All parts are
/// fixed width, so comparing the strings gives the same order as comparing
/// the values, and two devices can never produce the same timestamp.
library;

import 'package:meta/meta.dart';

@immutable
class Hlc implements Comparable<Hlc> {
  const new(this.millis, this.counter, this.deviceId)
    : assert(millis >= 0 && millis <= maxMillis, 'millis out of range'),
      assert(counter >= 0 && counter <= maxCounter, 'counter out of range');

  /// The smallest timestamp for [deviceId]; useful as an initial value.
  const new zero(String deviceId) : this(0, 0, deviceId);

  factory parse(String value) {
    final parts = value.split(':');
    if (parts.length != 3 ||
        parts[0].length != _millisWidth ||
        parts[1].length != _counterWidth ||
        parts[2].isEmpty) {
      throw FormatException('Invalid HLC timestamp', value);
    }
    final millis = int.tryParse(parts[0]);
    final counter = int.tryParse(parts[1], radix: 16);
    if (millis == null || counter == null || millis < 0 || counter < 0) {
      throw FormatException('Invalid HLC timestamp', value);
    }
    return Hlc(millis, counter, parts[2]);
  }

  static const _millisWidth = 13;
  static const _counterWidth = 4;
  static const maxMillis = 9999999999999;
  static const maxCounter = 0xFFFF;

  final int millis;
  final int counter;
  final String deviceId;

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) return millis.compareTo(other.millis);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return deviceId.compareTo(other.deviceId);
  }

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >(Hlc other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.millis == millis &&
      other.counter == counter &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(millis, counter, deviceId);

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

  @override
  String toString() =>
      '${millis.toString().padLeft(_millisWidth, '0')}'
      ':${counter.toRadixString(16).padLeft(_counterWidth, '0')}'
      ':$deviceId';
}

/// Issues [Hlc] timestamps for one device.
///
/// The clock never goes backwards, even if the phone's wall clock does, and
/// after [receive] every later local timestamp is greater than the received
/// one, so a local edit always wins over everything already seen.
class HlcClock {
  new({required this.deviceId, Hlc? last, int Function()? wallClock})
    : _last = last ?? Hlc.zero(deviceId),
      _wallClock = wallClock ?? _systemMillis;

  /// Remote clocks further ahead than this trigger a warning (GRP-11).
  static const maxDrift = Duration(hours: 24);

  final String deviceId;
  final int Function() _wallClock;
  Hlc _last;

  /// The latest timestamp issued or observed; persist it so the clock
  /// survives restarts.
  Hlc get last => _last;

  /// Returns a new timestamp for a local change.
  Hlc now() {
    final wall = _wallClock();
    if (wall > _last.millis) {
      _last = Hlc(wall, 0, deviceId);
    } else {
      _last = _increment(_last.millis, _last.counter);
    }
    return _last;
  }

  /// Advances the clock past a timestamp received from another device.
  void receive(Hlc remote) {
    final wall = _wallClock();
    final millis = [wall, _last.millis, remote.millis].reduce(_max);
    if (millis == _last.millis && millis == remote.millis) {
      _last = _increment(millis, _max(_last.counter, remote.counter));
    } else if (millis == _last.millis) {
      _last = _increment(millis, _last.counter);
    } else if (millis == remote.millis) {
      _last = _increment(millis, remote.counter);
    } else {
      _last = Hlc(millis, 0, deviceId);
    }
  }

  /// Whether [remote] is so far ahead of this phone's wall clock that one of
  /// the two clocks is probably wrong.
  bool isFarAhead(Hlc remote) =>
      remote.millis - _wallClock() > maxDrift.inMilliseconds;

  Hlc _increment(int millis, int counter) => counter < Hlc.maxCounter
      ? Hlc(millis, counter + 1, deviceId)
      // Counter exhausted within one millisecond: borrow the next one.
      : Hlc(millis + 1, 0, deviceId);

  static int _max(int a, int b) => a > b ? a : b;

  static int _systemMillis() => DateTime.now().millisecondsSinceEpoch;
}
