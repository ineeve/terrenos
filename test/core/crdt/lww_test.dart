import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' show Glados, Glados2, Glados3, any;
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/crdt/lww.dart';

import 'generators.dart';

void main() {
  group('LwwRegister', () {
    test('the later timestamp wins', () {
      const older = LwwRegister('old', Hlc(1, 0, 'a'));
      const newer = LwwRegister('new', Hlc(1, 1, 'a'));
      expect(older.merge(newer).value, 'new');
      expect(newer.merge(older).value, 'new');
    });

    test('ties between devices are broken by device id', () {
      const a = LwwRegister('from a', Hlc(1, 0, 'a'));
      const b = LwwRegister('from b', Hlc(1, 0, 'b'));
      expect(a.merge(b).value, 'from b');
    });

    test('round-trips through JSON', () {
      const reg = LwwRegister<Object?>({'n': 'Caminho'}, Hlc(7, 2, 'a'));
      expect(LwwRegister<Object?>.fromJson(reg.toJson()), reg);
    });

    Glados2(
      any.stringRegister,
      any.stringRegister,
    ).test('merge is commutative', (a, b) => expect(a.merge(b), b.merge(a)));

    Glados3(any.stringRegister, any.stringRegister, any.stringRegister).test(
      'merge is associative',
      (a, b, c) => expect(a.merge(b).merge(c), a.merge(b.merge(c))),
    );

    Glados(any.stringRegister)
        .test('merge is idempotent', (a) => expect(a.merge(a), a));
  });

  group('LwwMap', () {
    test('a removal is kept and wins over an older value', () {
      final map = const LwwMap<String>()
          .put('k', 'v', const Hlc(1, 0, 'a'))
          .remove('k', const Hlc(2, 0, 'b'));
      expect(map['k'], isNull);
      expect(map.values, isEmpty);
      expect(map.entries.containsKey('k'), isTrue);

      final stale = const LwwMap<String>().put('k', 'v', const Hlc(1, 5, 'c'));
      expect(map.merge(stale)['k'], isNull);
    });

    test('round-trips through JSON', () {
      final map = const LwwMap<String>()
          .put('a', 'x', const Hlc(1, 0, 'a'))
          .remove('b', const Hlc(2, 0, 'a'));
      expect(LwwMap<String>.fromJson(map.toJson()), map);
    });

    Glados2(
      any.stringMap,
      any.stringMap,
    ).test('merge is commutative', (a, b) => expect(a.merge(b), b.merge(a)));

    Glados3(any.stringMap, any.stringMap, any.stringMap).test(
      'merge is associative',
      (a, b, c) => expect(a.merge(b).merge(c), a.merge(b.merge(c))),
    );

    Glados(any.stringMap)
        .test('merge is idempotent', (a) => expect(a.merge(a), a));
  });
}
