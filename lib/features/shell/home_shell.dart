import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/editing/drafts.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Bottom navigation: Mapa · Terrenos · Grupos · Definições (SPEC.md §4).
class HomeShell extends ConsumerWidget {
  const new({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final drafts = ref.watch(draftsProvider).value ?? const [];
    return Scaffold(
      body: Column(
        children: [
          if (drafts.isNotEmpty) _DraftBanner(draft: drafts.first),
          Expanded(child: shell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(
          index,
          // Tapping the current tab returns to its first page.
          initialLocation: index == shell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map),
            label: l10n.navMap,
          ),
          NavigationDestination(
            icon: const Icon(Icons.landscape_outlined),
            selectedIcon: const Icon(Icons.landscape),
            label: l10n.navProperties,
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            selectedIcon: const Icon(Icons.groups),
            label: l10n.navGroups,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}

/// Offers to resume a boundary that wasn't finished, e.g. because the app
/// was closed or crashed while editing (REG-12).
class _DraftBanner extends ConsumerWidget {
  const new({required this.draft});

  final BoundaryDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    Future<void> discard() async {
      await ref.read(draftStorageProvider).delete(draft.id);
      ref.invalidate(draftsProvider);
    }

    return SafeArea(
      bottom: false,
      child: MaterialBanner(
        leading: const Icon(Icons.edit_note),
        content: Text(l10n.draftBanner('${draft.vertexCount}')),
        actions: [
          TextButton(onPressed: discard, child: Text(l10n.actionDiscard)),
          FilledButton(
            onPressed: () async {
              final id = draft.propertyId;
              if (id == null) {
                await context.push(Routes.newPropertyCoordinates, extra: draft);
              } else if (ref.read(propertyProvider(id)) == null) {
                // The property was deleted since; nothing to resume.
                await discard();
              } else {
                await context.push(Routes.propertyBoundary(id), extra: draft);
              }
            },
            child: Text(l10n.actionResume),
          ),
        ],
      ),
    );
  }
}

/// Placeholder body for tabs whose features arrive in later milestones.
class InDevelopment extends StatelessWidget {
  const new({required this.title, required this.icon, super.key});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).inDevelopment,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
