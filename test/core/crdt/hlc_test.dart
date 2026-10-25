import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' show Glados2, any;
import 'package:terrenos/core/crdt/hlc.dart';

import 'generators.dart';

void main() {
  group('Hlc', () {
    test('formats with fixed widths', () {
      expect(
        const Hlc(1729852920000, 26, 'abc').toString(),
        '1729852920000:001a:abc',
      );
      expect(const Hlc(5, 0, 'd').toString(), '0000000000005:0000:d');
    });

    test('parse is the inverse of toString', () {
      const hlc = Hlc(1729852920000, 0xFFFF, 'f00d');
      expect(Hlc.parse(hlc.toString()), hlc);
    });

    test('rejects malformed strings', () {
      for (final bad in [
        '',
        '1729852920000:0000',
        '172985292000:0000:a',
        '1729852920000:000:a',
        '1729852920000:zzzz:a',
        '1729852920000:0000:',
      ]) {
        expect(() => Hlc.parse(bad), throwsFormatException, reason: bad);
      }
    });

    Glados2(any.hlc, any.hlc).test('string order matches value order', (a, b) {
      expect(a.toString().compareTo(b.toString()).sign, a.compareTo(b).sign);
    });
  });

  group('HlcClock', () {
    test('uses the wall clock when it moves forward', () {
      var wall = 1000;
      final clock = HlcClock(deviceId: 'a', wallClock: () => wall);
      expect(clock.now(), const Hlc(1000, 0, 'a'));
      wall = 2000;
      expect(clock.now(), const Hlc(2000, 0, 'a'));
    });

    test('never goes backwards when the wall clock does', () {
      var wall = 5000;
      final clock = HlcClock(deviceId: 'a', wallClock: () => wall);
      final first = clock.now();
      wall = 1000;
      final second = clock.now();
      expect(second > first, isTrue);
      expect(second, const Hlc(5000, 1, 'a'));
    });

    test('borrows the next millisecond when the counter is exhausted', () {
      final clock = HlcClock(
        deviceId: 'a',
        last: const Hlc(10, Hlc.maxCounter, 'a'),
        wallClock: () => 0,
      );
      expect(clock.now(), const Hlc(11, 0, 'a'));
    });

    test('local timestamps after receive beat the received one', () {
      final clock = HlcClock(deviceId: 'a', wallClock: () => 1000);
      const remote = Hlc(9000, 7, 'b');
      clock.receive(remote);
      expect(clock.now() > remote, isTrue);
    });

    Glados2(any.hlc, any.hlc).test(
      'receive then now is greater than both inputs',
      (start, remote) {
        final clock = HlcClock(
          deviceId: 'local',
          last: Hlc(start.millis, start.counter, 'local'),
          wallClock: () => 10,
        )..receive(remote);
        final next = clock.now();
        expect(next > remote, isTrue);
        expect(next.millis >= start.millis, isTrue);
      },
    );

    test('restores from the persisted last timestamp', () {
      final clock = HlcClock(
        deviceId: 'a',
        last: const Hlc(9000, 3, 'a'),
        wallClock: () => 100,
      );
      expect(clock.now(), const Hlc(9000, 4, 'a'));
    });

    test('detects a remote clock more than 24 h ahead', () {
      const day = 24 * 60 * 60 * 1000;
      final clock = HlcClock(deviceId: 'a', wallClock: () => 1000);
      expect(clock.isFarAhead(const Hlc(1000 + day, 0, 'b')), isFalse);
      expect(clock.isFarAhead(const Hlc(1001 + day, 0, 'b')), isTrue);
    });
  });
}
