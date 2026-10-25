import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/format/text.dart';

void main() {
  test('folds case, Portuguese accents and spaces', () {
    expect(foldForSearch('  São   João da Ponte '), 'sao joao da ponte');
    expect(foldForSearch('AÇORES Évora Olhão'), 'acores evora olhao');
  });
}
