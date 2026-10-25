import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// First-run step 3: three slides. The last one warns that the data only
/// exists on this phone and that the app is not an official registry
/// (SET-1). Finishing completes onboarding; the router then opens the map.
class IntroPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends ConsumerState<IntroPage> {
  final _pages = PageController();
  var _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slides = [
      (Icons.edit_location_alt, l10n.introRecordTitle, l10n.introRecordBody),
      (Icons.wifi_off, l10n.introOfflineTitle, l10n.introOfflineBody),
      (Icons.phone_android, l10n.introDataTitle, l10n.introDataBody),
    ];
    final isLast = _index == slides.length - 1;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  for (final (icon, title, body) in slides)
                    _Slide(icon: icon, title: title, body: body),
                ],
              ),
            ),
            Semantics(
              label: l10n.introPage(_index + 1, slides.length),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < slides.length; i++)
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _index
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: isLast
                    ? () => ref
                          .read(settingsProvider.notifier)
                          .update((s) => s.copyWith(onboardingComplete: true))
                    : () => _pages.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                child: Text(isLast ? l10n.actionGetStarted : l10n.actionNext),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const new({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(icon, size: 96, color: theme.colorScheme.primary),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
