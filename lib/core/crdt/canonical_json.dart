/// Canonical JSON: sorted object keys, no whitespace (SPEC.md §9.4).
///
/// Two devices holding equal documents produce byte-identical output, so the
/// SHA-256 of the canonical form can be compared during sync.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

String canonicalJson(Object? value) {
  final buffer = StringBuffer();
  _write(buffer, value);
  return buffer.toString();
}

/// Lowercase hex SHA-256 of [canonicalJson] of [value].
String canonicalHash(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

void _write(StringBuffer out, Object? value) {
  switch (value) {
    case null:
      out.write('null');
    case bool():
      out.write(value);
    case int():
      out.write(value);
    case double():
      if (!value.isFinite) {
        throw ArgumentError.value(
          value,
          'value',
          'JSON numbers must be finite',
        );
      }
      out.write(jsonEncode(value));
    case String():
      out.write(jsonEncode(value));
    case List<Object?>():
      out.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) out.write(',');
        _write(out, value[i]);
      }
      out.write(']');
    case Map<String, Object?>():
      final keys = value.keys.toList()..sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        out
          ..write(jsonEncode(keys[i]))
          ..write(':');
        _write(out, value[keys[i]]);
      }
      out.write('}');
    default:
      throw ArgumentError.value(
        value,
        'value',
        'Not a JSON value (${value.runtimeType})',
      );
  }
}
