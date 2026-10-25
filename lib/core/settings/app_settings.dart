/// User preferences, stored in `settings.json` (SPEC.md §3.1, §8.1).
library;

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:terrenos/core/storage/atomic_file.dart';

/// App languages (SET-2). `null` in [AppSettings.language] means "follow the
/// phone": Portuguese if the phone is in Portuguese, English otherwise.
enum AppLanguage { pt, en }

enum AreaUnit { hectaresAndSquareMetres, squareMetres, hectares }

enum CoordinateFormat { decimalDegrees, degreesMinutesSeconds, ptTm06 }

@immutable
class AppSettings {
  const new({
    this.language,
    this.areaUnit = AreaUnit.hectaresAndSquareMetres,
    this.coordinateFormat = CoordinateFormat.decimalDegrees,
    this.entryFormat,
    this.onboardingComplete = false,
  });

  /// Unknown or missing values fall back to defaults, so an older or newer
  /// settings file never stops the app from starting.
  factory fromJson(Map<String, Object?> json) => AppSettings(
    language: _byName(AppLanguage.values, json['language']),
    areaUnit:
        _byName(AreaUnit.values, json['areaUnit']) ??
        AreaUnit.hectaresAndSquareMetres,
    coordinateFormat:
        _byName(CoordinateFormat.values, json['coordinateFormat']) ??
        CoordinateFormat.decimalDegrees,
    entryFormat: _byName(CoordinateFormat.values, json['entryFormat']),
    onboardingComplete: json['onboardingComplete'] == true,
  );

  final AppLanguage? language;
  final AreaUnit areaUnit;

  /// How coordinates are displayed (SET-4).
  final CoordinateFormat coordinateFormat;

  /// The format last used to type coordinates (VTX-3); `null` until then,
  /// when typing starts in the display format.
  final CoordinateFormat? entryFormat;
  final bool onboardingComplete;

  AppSettings copyWith({
    AppLanguage? Function()? language,
    AreaUnit? areaUnit,
    CoordinateFormat? coordinateFormat,
    CoordinateFormat? entryFormat,
    bool? onboardingComplete,
  }) => AppSettings(
    language: language != null ? language() : this.language,
    areaUnit: areaUnit ?? this.areaUnit,
    coordinateFormat: coordinateFormat ?? this.coordinateFormat,
    entryFormat: entryFormat ?? this.entryFormat,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
  );

  Map<String, Object?> toJson() => {
    'schema': 1,
    'language': language?.name,
    'areaUnit': areaUnit.name,
    'coordinateFormat': coordinateFormat.name,
    'entryFormat': entryFormat?.name,
    'onboardingComplete': onboardingComplete,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.language == language &&
      other.areaUnit == areaUnit &&
      other.coordinateFormat == coordinateFormat &&
      other.entryFormat == entryFormat &&
      other.onboardingComplete == onboardingComplete;

  @override
  int get hashCode => Object.hash(
    language,
    areaUnit,
    coordinateFormat,
    entryFormat,
    onboardingComplete,
  );
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

abstract interface class SettingsRepository {
  AppSettings load();
  Future<void> save(AppSettings settings);
}

class FileSettingsRepository implements SettingsRepository {
  new(File file) : _file = AtomicFile(file.path);

  final AtomicFile _file;

  @override
  AppSettings load() {
    try {
      return _file
              .read(
                (text) => AppSettings.fromJson(
                  jsonDecode(text) as Map<String, Object?>,
                ),
              )
              ?.value ??
          const AppSettings();
    } on Object {
      // Unreadable settings are not worth blocking start-up for.
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) =>
      _file.write(jsonEncode(settings.toJson()));
}

class MemorySettingsRepository implements SettingsRepository {
  new([this.settings = const AppSettings()]);

  AppSettings settings;

  @override
  AppSettings load() => settings;

  @override
  Future<void> save(AppSettings settings) async => this.settings = settings;
}
