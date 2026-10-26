import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/settings/app_settings.dart';

/// intl uses a no-break space as the Portuguese grouping separator.
String _nbsp(String s) => s.replaceAll(' ', ' ');

void main() {
  setUpAll(initializeDateFormatting);

  test('Portuguese uses a space for thousands and a decimal comma', () {
    expect(
      formatArea(12345.6, AreaUnit.squareMetres, languageCode: 'pt'),
      '${_nbsp('12 346')} m²',
    );
    expect(
      formatArea(123456, AreaUnit.hectares, languageCode: 'pt'),
      '12,35 ha',
    );
  });

  test('English uses a comma for thousands and a decimal point', () {
    expect(
      formatArea(12345.6, AreaUnit.squareMetres, languageCode: 'en'),
      '12,346 m²',
    );
    expect(
      formatArea(123456, AreaUnit.hectares, languageCode: 'en'),
      '12.35 ha',
    );
  });

  test('small parcels show four decimals in hectares', () {
    expect(formatArea(950, AreaUnit.hectares, languageCode: 'en'), '0.0950 ha');
  });

  test('the default unit shows both', () {
    expect(
      formatArea(9228.2, AreaUnit.hectaresAndSquareMetres, languageCode: 'pt'),
      '0,9228 ha (${_nbsp('9 228')} m²)',
    );
  });

  test('any other language formats as English', () {
    expect(numberLocaleFor('fr'), 'en');
    expect(numberLocaleFor('pt'), 'pt_PT');
  });

  test('lengths have one decimal and locale grouping', () {
    expect(formatLength(1234.56, languageCode: 'en'), '1,234.6 m');
    expect(formatLength(384.56, languageCode: 'pt'), '384,6 m');
  });

  test('walking distances round more as they grow', () {
    expect(formatDistance(4.24, languageCode: 'pt'), '4,2 m');
    expect(formatDistance(42.4, languageCode: 'en'), '42 m');
    expect(formatDistance(999.4, languageCode: 'en'), '999 m');
    expect(formatDistance(1234, languageCode: 'pt'), '1,2 km');
  });
}
