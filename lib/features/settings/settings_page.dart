import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/features/onboarding/device_name_page.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Settings (SPEC.md §3.1). Further entries (GPS, storage, app lock) arrive
/// with the features they configure.
class SettingsPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final device = ref.watch(deviceProvider);
    final controller = ref.read(settingsProvider.notifier);

    String languageLabel(AppLanguage? language) => switch (language) {
      null => l10n.languageSystem,
      AppLanguage.pt => l10n.languagePortuguese,
      AppLanguage.en => l10n.languageEnglish,
    };
    String areaLabel(AreaUnit unit) => switch (unit) {
      AreaUnit.hectaresAndSquareMetres => l10n.areaUnitHectaresAndSquareMetres,
      AreaUnit.squareMetres => l10n.areaUnitSquareMetres,
      AreaUnit.hectares => l10n.areaUnitHectares,
    };
    String coordinateLabel(CoordinateFormat format) => switch (format) {
      CoordinateFormat.decimalDegrees => l10n.coordinateFormatDecimal,
      CoordinateFormat.degreesMinutesSeconds => l10n.coordinateFormatDms,
      CoordinateFormat.ptTm06 => l10n.coordinateFormatPtTm06,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.settingsLanguage),
            subtitle: Text(languageLabel(settings.language)),
            onTap: () async {
              final choice = await _choose<AppLanguage?>(
                context,
                title: l10n.settingsLanguage,
                options: const [null, AppLanguage.pt, AppLanguage.en],
                selected: settings.language,
                label: languageLabel,
              );
              if (choice != null) {
                await controller.update(
                  (s) => s.copyWith(language: () => choice.value),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: Text(l10n.settingsDeviceName),
            subtitle: Text(device.displayName),
            onTap: () async {
              final name = await showDialog<String>(
                context: context,
                builder: (_) => _DeviceNameDialog(initial: device.displayName),
              );
              if (name != null) {
                await ref.read(deviceProvider.notifier).rename(name);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.square_foot),
            title: Text(l10n.settingsAreaUnit),
            subtitle: Text(areaLabel(settings.areaUnit)),
            onTap: () async {
              final choice = await _choose(
                context,
                title: l10n.settingsAreaUnit,
                options: AreaUnit.values,
                selected: settings.areaUnit,
                label: areaLabel,
              );
              if (choice != null) {
                await controller.update(
                  (s) => s.copyWith(areaUnit: choice.value),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.my_location),
            title: Text(l10n.settingsCoordinateFormat),
            subtitle: Text(coordinateLabel(settings.coordinateFormat)),
            onTap: () async {
              final choice = await _choose(
                context,
                title: l10n.settingsCoordinateFormat,
                options: CoordinateFormat.values,
                selected: settings.coordinateFormat,
                label: coordinateLabel,
              );
              if (choice != null) {
                await controller.update(
                  (s) => s.copyWith(coordinateFormat: choice.value),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: Text(l10n.offlineMapsTitle),
            subtitle: Text(l10n.offlineMapsSettingsHint),
            onTap: () => unawaited(context.push(Routes.offlineAreas)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.settingsAbout),
            subtitle: Text('${l10n.aboutPrivacy}\n${l10n.aboutDisclaimer}'),
            isThreeLine: true,
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.aboutLicences),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appTitle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps the chosen value so that choosing `null` (e.g. "same as this
/// phone") can be told apart from dismissing the dialog.
@immutable
class _Choice<T> {
  const new(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is _Choice<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

Future<_Choice<T>?> _choose<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T) label,
}) => showDialog<_Choice<T>>(
  context: context,
  builder: (context) => SimpleDialog(
    title: Text(title),
    children: [
      RadioGroup<_Choice<T>>(
        groupValue: _Choice(selected),
        onChanged: (choice) => Navigator.of(context).pop(choice),
        child: Column(
          children: [
            for (final option in options)
              RadioListTile<_Choice<T>>(
                value: _Choice(option),
                title: Text(label(option)),
              ),
          ],
        ),
      ),
    ],
  ),
);

class _DeviceNameDialog extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<_DeviceNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsDeviceName),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.deviceNameHint),
          validator: (value) => validateDeviceName(value, l10n),
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        TextButton(onPressed: _save, child: Text(l10n.actionSave)),
      ],
    );
  }
}
