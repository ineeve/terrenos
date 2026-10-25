import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/crdt/canonical_json.dart';

void main() {
  test('sorts keys at every level and drops whitespace', () {
    expect(
      canonicalJson({
        'b': 1,
        'a': {'z': true, 'y': null},
        'c': [3, 'x', -8.6291],
      }),
      '{"a":{"y":null,"z":true},"b":1,"c":[3,"x",-8.6291]}',
    );
  });

  test('escapes strings like JSON and keeps Unicode', () {
    expect(canonicalJson('São "João"\n'), r'"São \"João\"\n"');
  });

  test('equal values hash equally regardless of key order', () {
    expect(canonicalHash({'a': 1, 'b': 2}), canonicalHash({'b': 2, 'a': 1}));
    expect(canonicalHash({'a': 1}), isNot(canonicalHash({'a': 2})));
    expect(canonicalHash(null), hasLength(64));
  });

  test('rejects values that are not JSON', () {
    expect(() => canonicalJson(double.nan), throwsArgumentError);
    expect(() => canonicalJson(DateTime(2026)), throwsArgumentError);
    expect(() => canonicalJson({1: 'a'}), throwsArgumentError);
  });
}
