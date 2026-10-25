import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/identifiers.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// The property list (MGT-1) with search by name or process number (IDN-6).
class PropertiesPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PropertiesPage> createState() => _PropertiesPageState();
}

class _PropertiesPageState extends ConsumerState<PropertiesPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Accent- and case-insensitive name match, or a normalised partial
  /// match on the process number.
  static bool matches(PropertyDocument doc, String query) {
    final q = query.trim();
    if (q.isEmpty) return true;
    final number = doc.processNumber;
    final key = Identifiers.normalizeProcessNumber(q);
    return foldAccents(doc.name).contains(foldAccents(q)) ||
        (number != null &&
            key.isNotEmpty &&
            Identifiers.normalizeProcessNumber(number).contains(key));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final properties = ref.watch(propertiesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navProperties)),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.newPropertyTitle,
        onPressed: () => chooseNewPropertyMethod(context),
        child: const Icon(Icons.add),
      ),
      body: properties.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (all) {
          if (all.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.propertiesEmpty, textAlign: TextAlign.center),
              ),
            );
          }
          final shown = [
            for (final doc in all)
              if (matches(doc, _search.text)) doc,
          ];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchBar(
                  controller: _search,
                  hintText: l10n.propertiesSearch,
                  leading: const Icon(Icons.search),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text(l10n.propertiesNoResults))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: shown.length,
                        itemBuilder: (context, i) =>
                            PropertyTile(property: shown[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PropertyTile extends ConsumerWidget {
  const new({required this.property, super.key});

  final PropertyDocument property;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final unit = ref.watch(settingsProvider.select((s) => s.areaUnit));
    final current = property.geometry.current;
    final area = current == null || current.vertices.length < 3
        ? null
        : GeometryService.measure(current.parts).areaSquareMetres;
    final number = property.processNumber;
    return ListTile(
      leading: const Icon(Icons.landscape),
      title: Text(property.name),
      subtitle: Text(
        [
          if (number != null) l10n.processNumberShort(number),
          if (area != null) formatArea(area, unit, languageCode: language),
        ].join(' · '),
      ),
      onTap: () => context.push(Routes.property(property.id)),
    );
  }
}

/// The method picker (SPEC.md §4). Only typing coordinates exists so far.
Future<void> chooseNewPropertyMethod(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final route = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                l10n.newPropertyMethodTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: Text(l10n.methodCoordinates),
              onTap: () =>
                  Navigator.of(context).pop(Routes.newPropertyCoordinates),
            ),
            for (final (icon, label) in [
              (Icons.draw, l10n.methodDraw),
              (Icons.directions_walk, l10n.methodWalk),
              (Icons.file_open, l10n.methodImport),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                subtitle: Text(l10n.comingSoon),
                enabled: false,
              ),
          ],
        ),
      ),
    ),
  );
  if (route != null && context.mounted) await context.push(route);
}

/// Lowercase without diacritics, so "sao joao" finds "São João".
String foldAccents(String s) {
  const from = 'áàâãäçéèêëíìîïñóòôõöúùûü';
  const to = 'aaaaaceeeeiiiinooooouuuu';
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final char in lower.split('')) {
    final i = from.indexOf(char);
    out.write(i < 0 ? char : to[i]);
  }
  return out.toString();
}
