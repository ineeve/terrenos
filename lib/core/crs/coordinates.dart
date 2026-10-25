/// Coordinate input and display (SPEC.md §7.5, VTX-3, VTX-6).
///
/// Users type coordinates from plans, documents and other apps, so parsing
/// is forgiving about separators and symbols but strict about values.
library;

import 'package:intl/intl.dart';
import 'package:meta/meta.dart';
import 'package:terrenos/core/crs/pt_tm06.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/geometry/validation.dart';

enum CoordinateAxis { latitude, longitude }

/// Why a value could not be read.
enum CoordinateError {
  empty,
  notANumber,
  outOfRange,

  /// Minutes or seconds of 60 or more.
  minutesOrSecondsTooLarge,

  /// E.g. "N" on a longitude.
  wrongHemisphere,
}

/// Either a value or an error.
@immutable
class Parsed {
  const new value(double this.value) : error = null;
  const new error(CoordinateError this.error) : value = null;

  final double? value;
  final CoordinateError? error;

  bool get isValid => value != null;

  @override
  bool operator ==(Object other) =>
      other is Parsed && other.value == value && other.error == error;

  @override
  int get hashCode => Object.hash(value, error);

  @override
  String toString() => isValid ? 'Parsed($value)' : 'Parsed($error)';
}

const _minusSigns = ['−', '–', '‒'];

/// Reads a plain number. Accepts `,` or `.` as the decimal separator and
/// ignores thousands separators (spaces, or groups of three) so that values
/// copied from Portuguese documents, like `-41 234,56`, work.
Parsed parseNumber(String input) {
  var s = input.trim();
  if (s.isEmpty) return const Parsed.error(CoordinateError.empty);
  for (final minus in _minusSigns) {
    s = s.replaceAll(minus, '-');
  }
  s = s.replaceAll(RegExp(r'[\s  ]'), '');

  final commas = ','.allMatches(s).length;
  final dots = '.'.allMatches(s).length;
  if (commas > 0 && dots > 0) {
    // The last separator is the decimal one; the other groups thousands.
    final decimal = s.lastIndexOf(',') > s.lastIndexOf('.') ? ',' : '.';
    final thousands = decimal == ',' ? '.' : ',';
    final integerPart = s.substring(0, s.lastIndexOf(decimal));
    if (decimal.allMatches(s).length > 1 ||
        !_validGrouping(integerPart, thousands)) {
      return const Parsed.error(CoordinateError.notANumber);
    }
    s = s.replaceAll(thousands, '').replaceAll(',', '.');
  } else if (commas > 1 || dots > 1) {
    final sep = commas > 1 ? ',' : '.';
    if (!_validGrouping(s, sep)) {
      return const Parsed.error(CoordinateError.notANumber);
    }
    s = s.replaceAll(sep, '');
  } else {
    s = s.replaceAll(',', '.');
  }

  if (!RegExp(r'^[-+]?(\d+\.?\d*|\.\d+)$').hasMatch(s)) {
    return const Parsed.error(CoordinateError.notANumber);
  }
  return Parsed.value(double.parse(s));
}

/// Thousands groups: 1–3 leading digits, then groups of exactly 3.
bool _validGrouping(String integerPart, String separator) {
  final groups = integerPart.replaceFirst(RegExp('^[-+]'), '').split(separator);
  return groups.first.isNotEmpty &&
      groups.first.length <= 3 &&
      groups.skip(1).every((g) => g.length == 3);
}

/// Reads decimal degrees for one axis and checks the range.
Parsed parseDecimalDegrees(String input, CoordinateAxis axis) {
  final parsed = parseNumber(input);
  if (!parsed.isValid) return parsed;
  return _inRange(parsed.value!, axis);
}

/// Reads degrees, minutes and seconds, e.g. `41°09'30.06"N`,
/// `8º37’42,60” O`, `N 41 9 30.06` or `-8°37.71'` (decimal minutes).
/// `O` (Oeste) and `L` (Leste) are accepted as well as `W` and `E`.
Parsed parseDms(String input, CoordinateAxis axis) {
  var s = input.trim().toUpperCase();
  if (s.isEmpty) return const Parsed.error(CoordinateError.empty);
  for (final minus in _minusSigns) {
    s = s.replaceAll(minus, '-');
  }

  var negative = false;
  final hemisphere = RegExp(r'^\s*([NSEWOL])|([NSEWOL])\s*$').firstMatch(s);
  if (hemisphere != null) {
    final letter = hemisphere.group(1) ?? hemisphere.group(2)!;
    final isLat = letter == 'N' || letter == 'S';
    if (isLat != (axis == CoordinateAxis.latitude)) {
      return const Parsed.error(CoordinateError.wrongHemisphere);
    }
    negative = letter == 'S' || letter == 'W' || letter == 'O';
    s = s.replaceRange(hemisphere.start, hemisphere.end, ' ');
  }
  if (s.trimLeft().startsWith('-')) {
    if (hemisphere != null) {
      // "-8° W" is contradictory; refuse rather than guess.
      return const Parsed.error(CoordinateError.notANumber);
    }
    negative = true;
    s = s.trimLeft().substring(1);
  }

  // Anything that isn't a digit or decimal separator separates components.
  if (RegExp(r'[^\d.,°º˚′″’”‘“"\x27\s]').hasMatch(s)) {
    return const Parsed.error(CoordinateError.notANumber);
  }
  final texts = [
    for (final m in RegExp(r'\d+(?:[.,]\d+)?').allMatches(s)) m.group(0)!,
  ];
  final parts = [for (final t in texts) double.parse(t.replaceAll(',', '.'))];
  if (parts.isEmpty || parts.length > 3) {
    return const Parsed.error(CoordinateError.notANumber);
  }
  // Only the last component may have decimals.
  for (var i = 0; i < texts.length - 1; i++) {
    if (texts[i].contains(RegExp('[.,]'))) {
      return const Parsed.error(CoordinateError.notANumber);
    }
  }
  if (parts.skip(1).any((v) => v >= 60)) {
    return const Parsed.error(CoordinateError.minutesOrSecondsTooLarge);
  }

  var value = parts[0];
  if (parts.length > 1) value += parts[1] / 60;
  if (parts.length > 2) value += parts[2] / 3600;
  return _inRange(negative ? -value : value, axis);
}

Parsed _inRange(double value, CoordinateAxis axis) {
  final limit = axis == CoordinateAxis.latitude ? 90 : 180;
  return value.abs() > limit
      ? const Parsed.error(CoordinateError.outOfRange)
      : Parsed.value(value);
}

// ---------------------------------------------------------------------------
// Display

/// `41.1583500` (EN) or `41,1583500` (PT); 7 decimals, the stored precision.
String formatDecimalDegrees(double value, String languageCode) =>
    _number(value, 7, languageCode, grouping: false);

/// `41°09'30.06"N`; longitudes use `O` (Oeste) in Portuguese, `W` in
/// English.
String formatDms(double value, CoordinateAxis axis, String languageCode) {
  final pt = languageCode == 'pt';
  final hemisphere = switch (axis) {
    CoordinateAxis.latitude => value < 0 ? 'S' : 'N',
    CoordinateAxis.longitude => value < 0 ? (pt ? 'O' : 'W') : 'E',
  };
  // Work in hundredths of a second so rounding carries correctly.
  var hundredths = (value.abs() * 360000).round();
  final degrees = hundredths ~/ 360000;
  hundredths -= degrees * 360000;
  final minutes = hundredths ~/ 6000;
  hundredths -= minutes * 6000;
  final seconds = _number(hundredths / 100, 2, languageCode, grouping: false);
  final paddedSeconds = (hundredths < 1000 ? '0' : '') + seconds;
  final paddedMinutes = minutes.toString().padLeft(2, '0');
  return "$degrees°$paddedMinutes'$paddedSeconds\"$hemisphere";
}

/// PT-TM06 metres with 2 decimals, e.g. `-41 234,56` (PT) or `-41,234.56`
/// (EN). Use `grouping: false` for values meant to be copied.
String formatMetres(
  double value,
  String languageCode, {
  bool grouping = true,
}) => _number(value, 2, languageCode, grouping: grouping);

String _number(
  double value,
  int decimals,
  String languageCode, {
  required bool grouping,
}) {
  final format = NumberFormat.decimalPatternDigits(
    locale: numberLocaleFor(languageCode),
    decimalDigits: decimals,
  );
  if (!grouping) format.turnOffGrouping();
  return format.format(value);
}

// ---------------------------------------------------------------------------
// Checking a typed pair (§7.5 validation table)

enum CoordinateSystem { wgs84, ptTm06 }

/// What to tell the user about a typed coordinate pair.
@immutable
class PairCheck {
  const new({
    required this.lat,
    required this.lon,
    this.outsidePortugal = false,
    this.suggestNegativeLongitude = false,
    this.suggestSwap = false,
  });

  final double lat;
  final double lon;

  /// Outside mainland Portugal plus 50 km (VAL-6). A warning only.
  final bool outsidePortugal;

  /// Longitude typed as positive where the negative value is in Portugal:
  /// mainland Portugal lies entirely west of Greenwich.
  final bool suggestNegativeLongitude;

  /// Swapping the two values would put the point in Portugal.
  final bool suggestSwap;
}

/// Checks a pair in [system]: `(lat, lon)` for WGS84, `(m, p)` for PT-TM06.
PairCheck checkPair(CoordinateSystem system, double first, double second) {
  LatLon toLatLon(double a, double b) => switch (system) {
    CoordinateSystem.wgs84 => (lat: a, lon: b),
    CoordinateSystem.ptTm06 => PtTm06.toLatLon(a, b),
  };
  bool inside(LatLon p) =>
      MainlandPortugal.contains(p.lat, p.lon, withBuffer: true);

  final point = toLatLon(first, second);
  if (inside(point)) return PairCheck(lat: point.lat, lon: point.lon);

  final negativeLon =
      system == CoordinateSystem.wgs84 &&
      second > 0 &&
      inside((lat: first, lon: -second));
  final swapped =
      _plausible(system, second, first) && inside(toLatLon(second, first));
  return PairCheck(
    lat: point.lat,
    lon: point.lon,
    outsidePortugal: true,
    suggestNegativeLongitude: negativeLon,
    suggestSwap: swapped && !negativeLon,
  );
}

/// PT-TM06 values far outside the grid make the inverse projection
/// meaningless; only consider swaps within ±1000 km.
bool _plausible(CoordinateSystem system, double a, double b) =>
    system == CoordinateSystem.wgs84 || (a.abs() < 1e6 && b.abs() < 1e6);

/// Rounds degrees to the stored precision (§7.1).
double roundDegrees(double value) => (value * 1e7).roundToDouble() / 1e7;

/// Rounds metres to the input precision (0.01 m).
double roundMetres(double value) => (value * 100).roundToDouble() / 100;
