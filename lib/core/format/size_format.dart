/// Storage sizes and large areas, as shown for offline maps (MAP-7, SET-8).
library;

import 'package:intl/intl.dart';
import 'package:terrenos/core/format/area_format.dart';

/// Decimal units, as Android shows storage: `12,3 MB` (PT) or `12.3 MB`.
String formatBytes(int bytes, {required String languageCode}) {
  final locale = numberLocaleFor(languageCode);
  String number(double value) => NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: value < 10 ? 1 : 0,
  ).format(value);

  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${number(bytes / 1000)} kB';
  if (bytes < 1000 * 1000 * 1000) return '${number(bytes / 1e6)} MB';
  return '${number(bytes / 1e9)} GB';
}

/// Square kilometres with two decimals, e.g. `3,25 km²`.
String formatSquareKilometres(
  double squareMetres, {
  required String languageCode,
}) {
  final format = NumberFormat.decimalPatternDigits(
    locale: numberLocaleFor(languageCode),
    decimalDigits: 2,
  );
  return '${format.format(squareMetres / 1e6)} km²';
}

/// Whole numbers with grouping: `1 534` (PT) or `1,534`.
String formatCount(int count, {required String languageCode}) =>
    NumberFormat.decimalPattern(numberLocaleFor(languageCode)).format(count);
