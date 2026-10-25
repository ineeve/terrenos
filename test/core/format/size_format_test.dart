import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/format/size_format.dart';

void main() {
  test('bytes use decimal units and the language’s separators', () {
    expect(formatBytes(512, languageCode: 'en'), '512 B');
    expect(formatBytes(2300, languageCode: 'en'), '2.3 kB');
    expect(formatBytes(12345678, languageCode: 'en'), '12 MB');
    expect(formatBytes(4567890, languageCode: 'pt'), '4,6 MB');
    expect(formatBytes(1500000000, languageCode: 'pt'), '1,5 GB');
  });

  test('square kilometres and counts', () {
    expect(formatSquareKilometres(3250000, languageCode: 'pt'), '3,25 km²');
    expect(formatSquareKilometres(4000000, languageCode: 'en'), '4.00 km²');
    expect(formatCount(1534, languageCode: 'en'), '1,534');
    // Portuguese groups with a (non-breaking) space.
    expect(formatCount(1534, languageCode: 'pt'), matches(r'^1\s534$'));
  });
}
