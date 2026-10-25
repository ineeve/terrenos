import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/editing/boundary_editor.dart';
import 'package:terrenos/core/editing/drafts.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/properties/location.dart';
import 'package:terrenos/features/vertices/boundary_preview_map.dart';
import 'package:terrenos/features/vertices/coordinate_entry_page.dart';
import 'package:terrenos/features/vertices/vertex_table.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';
import 'package:uuid/uuid.dart';

/// Builds or edits a boundary as a vertex list (REG-11, VTX-2–5): a map
/// preview, live area and perimeter, the vertex table, and coordinate
/// entry. Works without any imagery: the map is only a preview.
class BoundaryEditorPage extends ConsumerStatefulWidget {
  /// `null` creates a new property; otherwise edits its boundary.
  const new({this.propertyId, this.draft, super.key});

  final String? propertyId;

  /// A saved draft to resume (REG-12).
  final BoundaryDraft? draft;

  @override
  ConsumerState<BoundaryEditorPage> createState() => _BoundaryEditorPageState();
}

class _BoundaryEditorPageState extends ConsumerState<BoundaryEditorPage> {
  late final BoundaryEditor _editor = _createEditor();
  late final String _draftId = widget.draft?.id ?? const Uuid().v7();
  String? _selectedId;

  /// Unsaved changes exist (or a draft was resumed): leaving asks first.
  late bool _changed = widget.draft != null;

  BoundaryEditor _createEditor() {
    final id = widget.propertyId;
    final doc = id == null
        ? null
        : ref.read(propertyRepositoryProvider).byId(id);
    final history = doc?.geometry;
    return BoundaryEditor(
      initial: widget.draft?.parts ?? history?.current?.parts ?? const [],
      usedIds: [
        for (final version in history?.versions.values ?? <GeometryVersion>[])
          ...version.vertices.map((v) => v.id),
      ],
    );
  }

  /// Applies an edit and saves the draft, so a crash loses nothing.
  void _update(void Function() change) {
    setState(change);
    _changed = true;
    unawaited(_saveDraft());
  }

  Future<void> _saveDraft() async {
    await ref
        .read(draftStorageProvider)
        .save(
          BoundaryDraft(
            id: _draftId,
            propertyId: widget.propertyId,
            parts: _editor.parts,
            updatedAt: DateTime.now(),
          ),
        );
    ref.invalidate(draftsProvider);
  }

  Future<void> _deleteDraft() async {
    await ref.read(draftStorageProvider).delete(_draftId);
    ref.invalidate(draftsProvider);
  }

  Future<void> _confirmLeave() async {
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardTitle),
        content: Text(l10n.discardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionKeepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionDiscard),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    await _deleteDraft();
    _changed = false;
    if (mounted) context.pop();
  }

  Future<void> _add() async {
    final typed = await CoordinateEntryPage.open(context);
    if (typed == null) return;
    _update(() {
      _selectedId = _editor
          .add(typed.position, source: VertexSource.typed, input: typed.input)
          .id;
    });
  }

  Future<void> _edit(Vertex vertex) async {
    final typed = await CoordinateEntryPage.open(context, vertex: vertex);
    if (typed == null) return;
    _update(() {
      _editor.move(
        vertex.id,
        typed.position,
        source: VertexSource.typed,
        input: typed.input,
      );
      _selectedId = vertex.id;
    });
  }

  Future<void> _actions(Vertex vertex) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _selectedId = vertex.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_location_alt),
                title: Text(l10n.vertexEditTitle),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.actionDelete),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        await _edit(vertex);
      case 'delete':
        _update(() => _editor.delete(vertex.id));
    }
  }

  Future<void> _finish() async {
    final l10n = AppLocalizations.of(context);
    final result = GeometryValidator.validate(_editor.parts);
    final ok = await confirmIssues(context, result.issues, l10n);
    if (!ok || !mounted) return;

    final id = widget.propertyId;
    if (id == null) {
      // The draft is deleted once the property is saved (details page).
      await context.push(
        Routes.newPropertyDetails,
        extra: (parts: result.parts, draftId: _draftId),
      );
    } else {
      final repository = ref.read(propertyRepositoryProvider);
      final doc = await repository.saveBoundary(id, result.parts);
      // Keep an automatic location in step with the new boundary (PROP-9).
      if (isAutoLocation(doc)) {
        final location = autoLocation(
          await ref.read(caopOrNullProvider.future),
          result.parts,
        );
        if (location != null) {
          await repository.setFields(id, {PropertyField.location: location});
        }
      }
      await _deleteDraft();
      _changed = false;
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final areaUnit = ref.watch(settingsProvider.select((s) => s.areaUnit));
    final ring = _editor.ring();
    Measurements? measurements;
    if (ring.length >= 3) {
      measurements = GeometryService.measure(_editor.parts);
    }

    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.propertyId == null
                ? l10n.newPropertyTitle
                : l10n.editBoundaryTitle,
          ),
          actions: [
            IconButton(
              tooltip: l10n.actionUndo,
              icon: const Icon(Icons.undo),
              onPressed: _editor.canUndo ? () => _update(_editor.undo) : null,
            ),
            IconButton(
              tooltip: l10n.actionRedo,
              icon: const Icon(Icons.redo),
              onPressed: _editor.canRedo ? () => _update(_editor.redo) : null,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            BoundaryPreviewMap(parts: _editor.parts, highlightId: _selectedId),
            const SizedBox(height: 12),
            if (measurements == null)
              Text(l10n.editorNeedThree)
            else ...[
              Text(
                l10n.editorArea(
                  formatArea(
                    measurements.areaSquareMetres,
                    areaUnit,
                    languageCode: language,
                  ),
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                l10n.editorPerimeter(
                  formatLength(
                    measurements.perimeterMetres,
                    languageCode: language,
                  ),
                ),
              ),
            ],
            if (ring.isNotEmpty) ...[
              const SizedBox(height: 8),
              SurveyProgress(vertices: ring),
            ],
            const Divider(),
            VertexRows(vertices: ring, onTap: (v, _) => _actions(v)),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add_location_alt),
          label: Text(l10n.vertexAddTitle),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: ring.length >= 3 ? _finish : null,
              child: Text(
                widget.propertyId == null ? l10n.actionNext : l10n.actionSave,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows validation problems. Errors block (returns `false`); warnings ask
/// for confirmation (VAL-*, SPEC.md §3.5).
Future<bool> confirmIssues(
  BuildContext context,
  List<GeometryIssue> issues,
  AppLocalizations l10n,
) async {
  if (issues.isEmpty) return true;
  final errors = issues.where((i) => i.severity == Severity.error).toList();
  final shown = errors.isNotEmpty ? errors : issues;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        errors.isNotEmpty
            ? l10n.cannotContinueTitle
            : l10n.checkBeforeContinuingTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final issue in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• ${issueText(issue, l10n)}'),
            ),
        ],
      ),
      actions: [
        if (errors.isEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(errors.isEmpty),
          child: Text(
            errors.isEmpty ? l10n.actionContinueAnyway : l10n.actionOk,
          ),
        ),
      ],
    ),
  );
  return proceed ?? false;
}

String issueText(GeometryIssue issue, AppLocalizations l10n) => switch (issue) {
  TooFewVertices() => l10n.issueTooFew,
  SelfIntersection() => l10n.issueCrossing,
  AreaOutOfRange() => l10n.issueArea,
  OutsidePortugal(:final swapLooksRight) =>
    swapLooksRight
        ? '${l10n.issueOutside} ${l10n.issueSwap}'
        : l10n.issueOutside,
  LowConfidenceVertices() => l10n.issueLowAccuracy,
  TooManyVertices() => l10n.issueTooMany,
};
