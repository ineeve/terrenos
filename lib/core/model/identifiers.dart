/// Identifier name and process number rules (SPEC.md §3.6.1, IDN-1–4).
library;

import 'package:terrenos/core/model/documents.dart';

enum NameError { empty, tooLong }

enum ProcessNumberError { tooLong, invalidCharacters }

abstract final class Identifiers {
  static const maxNameLength = 80;
  static const maxProcessNumberLength = 40;

  static final _processNumberCharacters = RegExp(
    r'^[\p{L}\p{N} /\-._]*$',
    unicode: true,
  );
  static final _ignoredInComparison = RegExp(r'[\s\-./_]');

  /// IDN-1: required, trimmed, at most 80 characters, any letters.
  static NameError? validateName(String value) {
    final name = value.trim();
    if (name.isEmpty) return NameError.empty;
    if (name.length > maxNameLength) return NameError.tooLong;
    return null;
  }

  /// IDN-3: optional; letters, digits, space and `/ - . _`.
  static ProcessNumberError? validateProcessNumber(String value) {
    final number = value.trim();
    if (number.length > maxProcessNumberLength) {
      return ProcessNumberError.tooLong;
    }
    if (!_processNumberCharacters.hasMatch(number)) {
      return ProcessNumberError.invalidCharacters;
    }
    return null;
  }

  /// The value to store: trimmed, otherwise exactly as typed (leading zeros,
  /// letters and punctuation kept). Empty means "no process number".
  static String? storedProcessNumber(String value) {
    final number = value.trim();
    return number.isEmpty ? null : number;
  }

  /// For duplicate checks and search (IDN-4, IDN-6): case-insensitive, with
  /// spaces and `- . / _` removed, so `0012 / 2023-a` matches `0012/2023-A`.
  static String normalizeProcessNumber(String value) =>
      value.replaceAll(_ignoredInComparison, '').toLowerCase();

  /// For name duplicate warnings (IDN-2): trimmed, case-insensitive,
  /// collapsed spaces.
  static String normalizeName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// Other live properties with the same normalised process number.
  static List<PropertyDocument> sameProcessNumber(
    String processNumber,
    Iterable<PropertyDocument> others, {
    String? exceptId,
  }) {
    final key = normalizeProcessNumber(processNumber);
    if (key.isEmpty) return const [];
    return [
      for (final doc in others)
        if (doc.id != exceptId &&
            !doc.isDeleted &&
            doc.processNumber != null &&
            normalizeProcessNumber(doc.processNumber!) == key)
          doc,
    ];
  }

  /// Other live properties with the same normalised name.
  static List<PropertyDocument> sameName(
    String name,
    Iterable<PropertyDocument> others, {
    String? exceptId,
  }) {
    final key = normalizeName(name);
    return [
      for (final doc in others)
        if (doc.id != exceptId &&
            !doc.isDeleted &&
            normalizeName(doc.name) == key)
          doc,
    ];
  }
}
