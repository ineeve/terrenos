import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/property_kinds.dart';
import 'package:terrenos/core/properties/location.dart';
import 'package:terrenos/features/properties/property_details_form_page.dart';
import 'package:terrenos/features/vertices/boundary_preview_map.dart';
import 'package:terrenos/features/vertices/vertex_table.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// One property: name and process number, map, area, vertex table
/// (SPEC.md §4.1, IDN-5).
class PropertyDetailPage extends ConsumerWidget {
  const new({required this.id, super.key});

  final String id;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(propertyRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    await repository.delete(id);
    if (context.mounted) context.pop();
    // MGT-3: deleting can be undone.
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.propertyDeleted),
        action: SnackBarAction(
          label: l10n.actionUndo,
          onPressed: () => repository.restore(id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final property = ref.watch(propertyProvider(id));
    if (property == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.propertyNotFound)),
      );
    }
    final language = Localizations.localeOf(context).languageCode;
    final unit = ref.watch(settingsProvider.select((s) => s.areaUnit));
    final current = property.geometry.current;
    final vertices = current?.vertices.toList() ?? const [];
    final measurements = vertices.length >= 3
        ? GeometryService.measure(current!.parts)
        : null;
    final number = property.processNumber;
    final type = PropertyType.fromCode(property.field(PropertyField.type));
    final landUse = LandUse.fromCode(property.field(PropertyField.landUse));

    return Scaffold(
      appBar: AppBar(
        title: Text(property.name),
        actions: [
          IconButton(
            tooltip: l10n.editDetailsTitle,
            icon: const Icon(Icons.edit),
            onPressed: () => context.push(Routes.propertyDetails(id)),
          ),
          IconButton(
            tooltip: l10n.actionDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (number != null)
            // IDN-7: long-press copies the official ID.
            GestureDetector(
              onLongPress: () => Clipboard.setData(ClipboardData(text: number)),
              child: Text(
                l10n.processNumberShort(number),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          if (readLocation(property) case final location?)
            Text(
              '${formatLocation(location)} (${location.distrito})',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          if (type != null || landUse != null)
            Text(
              [
                if (type != null) propertyTypeLabel(type, l10n),
                if (landUse != null) landUseLabel(landUse, l10n),
              ].join(' · '),
            ),
          const SizedBox(height: 12),
          if (current != null)
            BoundaryPreviewMap(parts: current.parts, height: 240),
          const SizedBox(height: 12),
          if (measurements != null) ...[
            _Fact(
              label: l10n.propertyArea,
              value: formatArea(
                measurements.areaSquareMetres,
                unit,
                languageCode: language,
              ),
            ),
            _Fact(
              label: l10n.propertyPerimeter,
              value: formatLength(
                measurements.perimeterMetres,
                languageCode: language,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.propertyVertices,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push(Routes.propertyBoundary(id)),
                icon: const Icon(Icons.edit_location_alt),
                label: Text(l10n.editBoundaryTitle),
              ),
            ],
          ),
          if (vertices.isNotEmpty) SurveyProgress(vertices: vertices),
          VertexRows(
            vertices: vertices,
            vertexInfo: property.vertexInfo.values,
          ),
          ..._otherDetails(context, property, l10n),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const new({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    ),
  );
}

/// The optional details (§3.6), shown only when set.
List<Widget> _otherDetails(
  BuildContext context,
  PropertyDocument doc,
  AppLocalizations l10n,
) {
  String? text(String key) {
    final value = doc.field(key);
    return value is String && value.isNotEmpty ? value : null;
  }

  final confrontations = doc.field(PropertyField.confrontations);
  final owners = doc.field(PropertyField.owners);
  final acquired = switch (doc.field(PropertyField.acquiredOn)) {
    final String s => DateTime.tryParse(s),
    _ => null,
  };
  final facts = <(String, String)>[
    if (text(PropertyField.placeName) case final v?) (l10n.fieldPlaceName, v),
    if (text(PropertyField.matrixArticle) case final v?)
      (l10n.fieldMatrixArticle, v),
    if (text(PropertyField.matrixParish) case final v?)
      (l10n.fieldMatrixParish, v),
    if (text(PropertyField.registryDescription) case final v?)
      (l10n.fieldRegistryDescription, v),
    if (text(PropertyField.cadastralSection) case final v?)
      (l10n.fieldCadastralSection, v),
    if (confrontations is Map)
      for (final (side, label) in [
        ('n', l10n.fieldNorth),
        ('s', l10n.fieldSouth),
        ('e', l10n.fieldEast),
        ('w', l10n.fieldWest),
      ])
        if (confrontations[side] case final String v) (label, v),
    if (owners is List)
      for (final owner in owners.whereType<Map<String, Object?>>())
        (
          l10n.sectionOwners,
          owner['share'] is num
              ? '${owner['name']} (${owner['share']} %)'
              : '${owner['name']}',
        ),
    if (acquired != null)
      (
        l10n.fieldAcquiredOn,
        MaterialLocalizations.of(context).formatCompactDate(acquired),
      ),
    if (text(PropertyField.notes) case final v?) (l10n.fieldNotes, v),
  ];
  if (facts.isEmpty) return const [];
  return [
    const Divider(height: 32),
    for (final (label, value) in facts)
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label),
        subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ),
  ];
}
