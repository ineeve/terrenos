import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/features/groups/groups_page.dart';
import 'package:terrenos/features/map/map_page.dart';
import 'package:terrenos/features/onboarding/device_name_page.dart';
import 'package:terrenos/features/onboarding/intro_page.dart';
import 'package:terrenos/features/onboarding/language_page.dart';
import 'package:terrenos/features/properties/properties_page.dart';
import 'package:terrenos/features/settings/settings_page.dart';
import 'package:terrenos/features/shell/home_shell.dart';

abstract final class Routes {
  static const welcomeLanguage = '/welcome/language';
  static const welcomeDeviceName = '/welcome/device-name';
  static const welcomeIntro = '/welcome/intro';
  static const map = '/map';
  static const properties = '/properties';
  static const groups = '/groups';
  static const settings = '/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  // The router is created once; onboarding completion is fed in through a
  // listenable so navigation state survives settings changes.
  final onboarded = ValueNotifier(
    ref.read(settingsProvider).onboardingComplete,
  );
  ref
    ..listen(
      settingsProvider.select((s) => s.onboardingComplete),
      (_, next) => onboarded.value = next,
    )
    ..onDispose(onboarded.dispose);

  final router = GoRouter(
    initialLocation: Routes.map,
    refreshListenable: onboarded,
    redirect: (context, state) {
      final inWelcome = state.matchedLocation.startsWith('/welcome');
      if (!onboarded.value && !inWelcome) return Routes.welcomeLanguage;
      if (onboarded.value && inWelcome) return Routes.map;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.welcomeLanguage,
        builder: (context, state) => const LanguagePage(),
      ),
      GoRoute(
        path: Routes.welcomeDeviceName,
        builder: (context, state) => const DeviceNamePage(),
      ),
      GoRoute(
        path: Routes.welcomeIntro,
        builder: (context, state) => const IntroPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          _branch(Routes.map, const MapPage()),
          _branch(Routes.properties, const PropertiesPage()),
          _branch(Routes.groups, const GroupsPage()),
          _branch(Routes.settings, const SettingsPage()),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(String path, Widget page) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => page)],
);
