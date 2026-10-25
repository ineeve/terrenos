import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// First-run step 1: language, preselected from the phone (SET-1).
/// Choosing a language switches the app immediately.
class LanguagePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shown = AppLanguage.values.byName(
      Localizations.localeOf(context).languageCode,
    );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                l10n.languageTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              RadioGroup<AppLanguage>(
                groupValue: shown,
                onChanged: (language) => ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.copyWith(language: () => language)),
                child: Column(
                  children: [
                    RadioListTile(
                      value: AppLanguage.pt,
                      title: Text(l10n.languagePortuguese),
                    ),
                    RadioListTile(
                      value: AppLanguage.en,
                      title: Text(l10n.languageEnglish),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  // Keep what is shown, even if it came from the phone, so
                  // the app doesn't change language if the phone does.
                  await ref
                      .read(settingsProvider.notifier)
                      .update((s) => s.copyWith(language: () => shown));
                  if (context.mounted) {
                    await context.push(Routes.welcomeDeviceName);
                  }
                },
                child: Text(l10n.actionContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
