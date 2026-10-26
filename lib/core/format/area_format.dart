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

/// Lengths in metres with one decimal, e.g. `384,6 m` (PT) or `384.6 m`.
String formatLength(double metres, {required String languageCode}) {
  final number = NumberFormat.decimalPatternDigits(
    locale: numberLocaleFor(languageCode),
    decimalDigits: 1,
  ).format(metres);
  return '$number m';
}

/// A walking distance: `4,2 m` under 10 m, `42 m` under 1 km, then
/// `1,2 km` (PT; `.` in English).
String formatDistance(double metres, {required String languageCode}) {
  String number(double value, int decimals) =>
      NumberFormat.decimalPatternDigits(
        locale: numberLocaleFor(languageCode),
        decimalDigits: decimals,
      ).format(value);
  if (metres < 10) return '${number(metres, 1)} m';
  if (metres < 1000) return '${number(metres, 0)} m';
  return '${number(metres / 1000, 1)} km';
}
