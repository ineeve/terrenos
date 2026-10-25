import 'package:flutter/material.dart';
import 'package:terrenos/features/shell/home_shell.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

class PropertiesPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => InDevelopment(
    title: AppLocalizations.of(context).navProperties,
    icon: Icons.landscape,
  );
}
