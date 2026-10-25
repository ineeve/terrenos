import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/app/theme.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// English is listed first so it is the fallback for phones in any language
/// other than Portuguese (SPEC.md SET-1).
const supportedLocales = [Locale('en'), Locale('pt')];

class TerrenosApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(settingsProvider.select((s) => s.language));
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // null follows the phone's language (SET-1); a choice in the app wins.
      locale: switch (language) {
        null => null,
        AppLanguage.pt => const Locale('pt'),
        AppLanguage.en => const Locale('en'),
      },
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
