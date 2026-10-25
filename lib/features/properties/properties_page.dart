import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/property_kinds.dart';
import 'package:terrenos/core/properties/property_query.dart';
import 'package:terrenos/features/properties/property_details_form_page.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// How the list is searched, sorted and filtered; kept while the app runs.
final propertyQueryProvider =
    NotifierProvider<PropertyQueryController, PropertyQuery>(
      PropertyQueryController.new,
    );

class PropertyQueryController extends Notifier<PropertyQuery> {
  @override
  PropertyQuery build() => const PropertyQuery();

  // A method rather than a setter, to match the other controllers.
  // ignore: use_setters_to_change_properties
  void set(PropertyQuery query) => state = query;
}

/// The property list (MGT-1): search by name or process number (IDN-6),
/// sort, filters, and the count and total area of what is shown (MGT-2).
class PropertiesPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PropertiesPage> createState() => _PropertiesPageState();
}

class _PropertiesPageState extends ConsumerState<PropertiesPage> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(propertyQueryProvider).search;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final unit = ref.watch(settingsProvider.select((s) => s.areaUnit));
    final properties = ref.watch(propertiesProvider);
    final query = ref.watch(propertyQueryProvider);
    final controller = ref.read(propertyQueryProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navProperties),
        actions: [
          PopupMenuButton<PropertySort>(
            tooltip: l10n.sortTitle,
            icon: const Icon(Icons.sort),
            initialValue: query.sort,
            onSelected: (sort) => controller.set(query.copyWith(sort: sort)),
            itemBuilder: (context) => [
              for (final sort in PropertySort.values)
                CheckedPopupMenuItem(
                  value: sort,
                  checked: sort == query.sort,
                  child: Text(sortLabel(sort, l10n)),
                ),
            ],
          ),
          IconButton(
            tooltip: l10n.filtersTitle,
            icon: Badge(
              isLabelVisible: query.isFiltered,
              label: Text('${query.filterCount}'),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => showPropertyFilters(context),
          ),
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () => unawaited(context.push(Routes.recycleBin)),
                child: Text(l10n.recycleBinTitle),
              ),
            ],
          ),
        ],
      ),
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
          final shown = query.apply(all);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchBar(
                  controller: _search,
                  hintText: l10n.propertiesSearch,
                  leading: const Icon(Icons.search),
                  onChanged: (text) =>
                      controller.set(query.copyWith(search: text)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.propertiesSummary(
                          shown.length,
                          formatArea(
                            totalArea(shown),
                            unit,
                            languageCode: language,
                          ),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (query.isFiltered)
                      TextButton(
                        onPressed: () => controller.set(query.cleared),
                        child: Text(l10n.filterClear),
                      ),
                  ],
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

String sortLabel(PropertySort sort, AppLocalizations l10n) => switch (sort) {
  PropertySort.name => l10n.sortName,
  PropertySort.processNumber => l10n.sortProcessNumber,
  PropertySort.area => l10n.sortArea,
  PropertySort.freguesia => l10n.sortFreguesia,
  PropertySort.lastChange => l10n.sortLastChange,
};

/// The filters (MGT-1, MGT-8). Changes apply as they are made.
Future<void> showPropertyFilters(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const SafeArea(child: _Filters()),
    );

class _Filters extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(propertyQueryProvider);
    final controller = ref.read(propertyQueryProvider.notifier);
    final all = ref.watch(propertiesProvider).value ?? const [];
    final theme = Theme.of(context);
    final locations = [for (final d in all) ?locationOf(d)];
    int byName(String a, String b) => foldAccents(a).compareTo(foldAccents(b));
    final concelhos = {for (final l in locations) ?l.concelho}.toList()
      ..sort(byName);
    final freguesias = {
      for (final l in locations)
        if (query.concelhos.isEmpty || query.concelhos.contains(l.concelho))
          ?l.freguesia,
    }.toList()..sort(byName);

    Set<T> toggle<T>(Set<T> set, T value) =>
        set.contains(value) ? ({...set}..remove(value)) : {...set, value};
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    Widget chips<T>(
      Iterable<T> values,
      Set<T> selected,
      String Function(T) label,
      PropertyQuery Function(Set<T>) update,
    ) => Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final value in values)
          FilterChip(
            label: Text(label(value)),
            selected: selected.contains(value),
            onSelected: (_) => controller.set(update(toggle(selected, value))),
          ),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.filtersTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: query.isFiltered
                    ? () => controller.set(query.cleared)
                    : null,
                child: Text(l10n.filterClear),
              ),
            ],
          ),
          heading(l10n.fieldType),
          chips(
            PropertyType.values,
            query.types,
            (t) => propertyTypeLabel(t, l10n),
            (s) => query.copyWith(types: s),
          ),
          heading(l10n.fieldLandUse),
          chips(
            LandUse.values,
            query.landUses,
            (u) => landUseLabel(u, l10n),
            (s) => query.copyWith(landUses: s),
          ),
          if (concelhos.isNotEmpty) ...[
            heading(l10n.fieldConcelho),
            chips(
              concelhos,
              query.concelhos,
              (c) => c,
              (s) => query.copyWith(concelhos: s),
            ),
          ],
          if (freguesias.isNotEmpty) ...[
            heading(l10n.fieldFreguesia),
            chips(
              freguesias,
              query.freguesias,
              (f) => f,
              (s) => query.copyWith(freguesias: s),
            ),
          ],
          heading(l10n.fieldProcessNumber),
          SegmentedButton<bool?>(
            segments: [
              ButtonSegment(value: null, label: Text(l10n.filterAny)),
              ButtonSegment(value: true, label: Text(l10n.filterWith)),
              ButtonSegment(value: false, label: Text(l10n.filterWithout)),
            ],
            selected: {query.hasProcessNumber},
            onSelectionChanged: (s) => controller.set(
              query.copyWith(hasProcessNumber: () => s.single),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.filterPlanned),
            value: query.plannedOnly,
            onChanged: (value) =>
                controller.set(query.copyWith(plannedOnly: value)),
          ),
        ],
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
    final area = propertyArea(property);
    final number = property.processNumber;
    // IDN-2: the freguesia tells apart properties with the same name.
    final freguesia = locationOf(property)?.freguesia;
    return ListTile(
      leading: const Icon(Icons.landscape),
      title: Text(property.name),
      subtitle: Text(
        [
          if (number != null) l10n.processNumberShort(number),
          ?freguesia,
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
              leading: const Icon(Icons.draw),
              title: Text(l10n.methodDraw),
              onTap: () => Navigator.of(context).pop(Routes.newPropertyDraw),
            ),
            ListTile(
              leading: const Icon(Icons.directions_walk),
              title: Text(l10n.methodWalk),
              onTap: () => Navigator.of(context).pop(Routes.newPropertyWalk),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: Text(l10n.methodCoordinates),
              onTap: () =>
                  Navigator.of(context).pop(Routes.newPropertyCoordinates),
            ),
            for (final (icon, label) in [(Icons.file_open, l10n.methodImport)])
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
