/// Area formatting in the user's unit and language (SET-3, SPEC.md §10).
library;

import 'package:intl/intl.dart';
import 'package:terrenos/core/settings/app_settings.dart';

const squareMetresPerHectare = 10000;

/// The intl locale used for numbers. Portuguese always formats as in
/// Portugal (`1 234,5`), even on phones set to Brazilian Portuguese.
String numberLocaleFor(String languageCode) =>
    languageCode == 'pt' ? 'pt_PT' : 'en';

String formatArea(
  double squareMetres,
  AreaUnit unit, {
  required String languageCode,
}) {
  final locale = numberLocaleFor(languageCode);
  String number(double value, int decimals) =>
      NumberFormat.decimalPatternDigits(
        locale: locale,
        decimalDigits: decimals,
      ).format(value);

  String m2() => '${number(squareMetres, 0)} m²';
  String ha() {
    final hectares = squareMetres / squareMetresPerHectare;
    // Small parcels need more decimals to be meaningful in hectares.
    return '${number(hectares, hectares >= 1 ? 2 : 4)} ha';
  }

  return switch (unit) {
    AreaUnit.squareMetres => m2(),
    AreaUnit.hectares => ha(),
    AreaUnit.hectaresAndSquareMetres => '${ha()} (${m2()})',
  };
}
