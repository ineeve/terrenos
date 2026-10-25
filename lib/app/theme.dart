import 'package:flutter/material.dart';

/// Material 3 with larger text defaults, because many users are older
/// (SPEC.md §4.2). Dynamic colour is not used: status colours on the map
/// need a fixed palette.
abstract final class AppTheme {
  static const seed = Color(0xFF2E7D32);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme;
    return base.copyWith(
      textTheme: text.copyWith(
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 18),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 16),
        labelLarge: text.labelLarge?.copyWith(fontSize: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
