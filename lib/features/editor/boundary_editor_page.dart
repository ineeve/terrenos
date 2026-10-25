import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/editing/boundary_draft.dart';
import 'package:terrenos/core/editing/boundary_editor.dart';
import 'package:terrenos/core/format/area_format.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/geometry/validation.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/features/editor/draw_map.dart';
import 'package:terrenos/features/vertices/boundary_preview_map.dart';
import 'package:terrenos/features/vertices/coordinate_entry_page.dart';
import 'package:terrenos/features/vertices/vertex_format.dart';
import 'package:terrenos/features/vertices/vertex_table.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Builds or edits a boundary (REG-1, REG-11, VTX-2–5). Two views of the
/// same edit: draw on the map, or the vertex table with coordinate entry,
/// which works without any imagery. Every change is saved as a draft
/// (REG-12).
class BoundaryEditorPage extends ConsumerStatefulWidget {
  /// `null` creates a new property; otherwise edits its boundary.
  const new({this.propertyId, this.startOnMap = false, super.key});

  final String? propertyId;
  final bool startOnMap;

  @override
  ConsumerState<BoundaryEditorPage> createState() => _BoundaryEditorPageState();
}

class _BoundaryEditorPageState extends ConsumerState<BoundaryEditorPage> {
  late final BoundaryDraft? _resumed = ref
      .read(draftStorageProvider)
      .load(widget.propertyId ?? BoundaryDraft.newProperty);
  late final BoundaryEditor _editor = _createEditor();
  late bool _onMap = widget.startOnMap;
  late bool _dirty = _resumed != null;
  String? _selectedId;

  /// The vertex being dragged on the map, before the move is committed.
  ({String id, DrawPosition at})? _drag;

  BoundaryEditor _createEditor() {
    final id = widget.propertyId;
    final doc = id == null
        ? null
        : ref.read(propertyRepositoryProvider).byId(id);
    final history = doc?.geometry;
    return BoundaryEditor(
      initial: _resumed?.parts ?? history?.current?.parts ?? const [],
      usedIds: [
        for (final version in history?.versions.values ?? <GeometryVersion>[])
          ...version.vertices.map((v) => v.id),
      ],
    );
  }

  /// Applies an edit and writes the draft (REG-12).
  void _change(void Function() edit) {
    setState(() {
      edit();
      _dirty = true;
    });
    final drafts = ref.read(draftStorageProvider);
    final key = widget.propertyId ?? BoundaryDraft.newProperty;
    final draft = BoundaryDraft(
      propertyId: widget.propertyId,
      parts: _editor.parts,
      updatedAt: DateTime.now().toUtc(),
    );
    if (draft.vertexCount == 0) {
      unawaited(drafts.delete(key));
    } else {
      unawaited(drafts.save(draft));
    }
  }

  Future<void> _discardDraft() async {
    _dirty = false;
    await ref
        .read(draftStorageProvider)
        .delete(widget.propertyId ?? BoundaryDraft.newProperty);
  }

  RingRef _ringOf(String id) {
    final parts = _editor.parts;
    for (var p = 0; p < parts.length; p++) {
      for (var r = 0; r < parts[p].length; r++) {
        if (parts[p][r].any((v) => v.id == id)) return (part: p, ring: r);
      }
    }
    return outerRing;
  }

  /// The boundary as shown: with the dragged vertex where the finger is.
  BoundaryParts get _shown {
    final drag = _drag;
    if (drag == null) return _editor.parts;
    return [
      for (final part in _editor.parts)
        [
          for (final ring in part)
            [
              for (final v in ring)
                if (v.id == drag.id)
                  Vertex(
                    id: v.id,
                    lon: drag.at.position.lon,
                    lat: drag.at.position.lat,
                    source: VertexSource.map,
                  )
                else
                  v,
            ],
        ],
    ];
  }

  Future<void> _add() async {
    final typed = await CoordinateEntryPage.open(context, ring: _editor.ring());
    if (typed == null) return;
    _change(() {
      _selectedId = _editor
          .add(
            typed.position,
            source: VertexSource.typed,
            input: typed.input,
            afterId: typed.afterId,
          )
          .id;
    });
  }

  /// A tap on the map adds a vertex after the selected one, or at the end.
  void _addOnMap(DrawPosition at) {
    final selected = _selectedId;
    _change(() {
      _selectedId = _editor
          .add(
            at.position,
            source: VertexSource.map,
            afterId: selected,
            ref: selected == null ? outerRing : _ringOf(selected),
          )
          .id;
    });
  }

  void _delete(String id) => _change(() {
    _editor.delete(id);
    if (_selectedId == id) _selectedId = null;
  });

  Future<void> _edit(Vertex vertex) async {
    final typed = await CoordinateEntryPage.open(
      context,
      vertex: vertex,
      ring: _editor.ring(_ringOf(vertex.id)),
    );
    if (typed == null) return;
    _change(() {
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
        _delete(vertex.id);
    }
  }

  Future<void> _finish() async {
    final l10n = AppLocalizations.of(context);
    final others = [
      for (final doc
          in ref.read(propertiesProvider).value ?? const <PropertyDocument>[])
        if (doc.id != widget.propertyId)
          if (doc.geometry.current case final current?)
            (id: doc.id, name: doc.name, parts: current.parts),
    ];
    final result = GeometryValidator.validate(_editor.parts, others: others);
    final ok = await confirmIssues(context, result.issues, l10n);
    if (!ok || !mounted) return;

    final id = widget.propertyId;
    if (id == null) {
      // The draft is kept until the details are saved too.
      await context.push(Routes.newPropertyDetails, extra: result.parts);
    } else {
      await ref.read(propertyRepositoryProvider).saveBoundary(id, result.parts);
      await _discardDraft();
      if (mounted) context.pop();
    }
  }

  Future<void> _confirmLeave() async {
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.draftDiscardTitle),
        content: Text(l10n.draftDiscardBody),
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
    if (!(discard ?? false) || !mounted) return;
    await _discardDraft();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final areaUnit = ref.watch(settingsProvider.select((s) => s.areaUnit));
    final shown = _shown;
    final ring = _editor.ring();
    final count = shown.fold(
      0,
      (sum, part) => sum + part.fold(0, (s, r) => s + r.length),
    );
    final measurements = count >= 3 ? GeometryService.measure(shown) : null;
    final small = Theme.of(context).textTheme.bodySmall;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.propertyId == null
                    ? l10n.newPropertyTitle
                    : l10n.editBoundaryTitle,
              ),
              // Live area and perimeter (REG-6).
              if (measurements == null)
                Text(l10n.editorNeedThree, style: small)
              else ...[
                Text(
                  l10n.editorArea(
                    formatArea(
                      measurements.areaSquareMetres,
                      areaUnit,
                      languageCode: language,
                    ),
                  ),
                  style: small,
                ),
                Text(
                  l10n.editorPerimeter(
                    formatLength(
                      measurements.perimeterMetres,
                      languageCode: language,
                    ),
                  ),
                  style: small,
                ),
              ],
            ],
          ),
          toolbarHeight: 72,
          actions: [
            IconButton(
              tooltip: l10n.actionUndo,
              icon: const Icon(Icons.undo),
              onPressed: _editor.canUndo ? () => _change(_editor.undo) : null,
            ),
            IconButton(
              tooltip: l10n.actionRedo,
              icon: const Icon(Icons.redo),
              onPressed: _editor.canRedo ? () => _change(_editor.redo) : null,
            ),
            IconButton(
              tooltip: _onMap ? l10n.editorShowList : l10n.editorShowMap,
              icon: Icon(_onMap ? Icons.list_alt : Icons.map_outlined),
              onPressed: () => setState(() => _onMap = !_onMap),
            ),
          ],
        ),
        body: _onMap
            ? _mapView(shown, l10n, language)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  BoundaryPreviewMap(parts: shown, highlightId: _selectedId),
                  if (ring.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SurveyProgress(vertices: ring),
                  ],
                  const Divider(),
                  VertexRows(vertices: ring, onTap: (v, _) => _actions(v)),
                ],
              ),
        floatingActionButton: _onMap
            ? null
            : FloatingActionButton.extended(
                onPressed: _add,
                icon: const Icon(Icons.add_location_alt),
                label: Text(l10n.vertexAddTitle),
              ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_onMap) ...[
                  IconButton.outlined(
                    tooltip: l10n.actionDeleteVertex,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _selectedId == null
                        ? null
                        : () => _delete(_selectedId!),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: count >= 3 ? _finish : null,
                    child: Text(
                      widget.propertyId == null
                          ? l10n.actionNext
                          : l10n.actionSave,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapView(BoundaryParts shown, AppLocalizations l10n, String language) {
    final format = ref.watch(
      settingsProvider.select((s) => s.coordinateFormat),
    );
    final focusId = _drag?.id ?? _selectedId;
    Vertex? focus;
    var index = 0;
    for (final part in shown) {
      for (final ring in part) {
        for (final (i, v) in ring.indexed) {
          if (v.id == focusId) (focus, index) = (v, i);
        }
      }
    }
    final theme = Theme.of(context);
    return Stack(
      children: [
        DrawMap(
          parts: shown,
          selectedId: _selectedId,
          propertyId: widget.propertyId,
          onAdd: _addOnMap,
          onSelect: (id) => setState(() => _selectedId = id),
          onDrag: (id, at) =>
              setState(() => _drag = at == null ? null : (id: id, at: at)),
          onMove: (id, at) => _change(
            () => _editor.move(id, at.position, source: VertexSource.map),
          ),
          onInsert: (afterId, position) => _change(() {
            _selectedId = _editor
                .add(
                  position,
                  source: VertexSource.map,
                  afterId: afterId,
                  ref: _ringOf(afterId),
                )
                .id;
          }),
          onDelete: _delete,
        ),
        // The selected or dragged vertex's coordinates, live (REG-1).
        Positioned(
          left: 8,
          right: 8,
          top: 8,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: focus == null
                  ? Text(l10n.drawHint, style: theme.textTheme.bodySmall)
                  : Row(
                      children: [
                        Text(
                          vertexLabel(index, null),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(switch (formatVertex(
                            focus,
                            format,
                            language,
                          )) {
                            (final a, final b) => '$a\n$b',
                          }),
                        ),
                        if (_drag?.at.snapped ?? false)
                          Tooltip(
                            message: l10n.drawSnapped,
                            child: const Icon(Icons.join_inner),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ],
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
  final language = Localizations.localeOf(context).languageCode;
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
              child: Text('• ${issueText(issue, l10n, language)}'),
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

String issueText(
  GeometryIssue issue,
  AppLocalizations l10n,
  String languageCode,
) => switch (issue) {
  TooFewVertices() => l10n.issueTooFew,
  SelfIntersection() => l10n.issueCrossing,
  AreaOutOfRange() => l10n.issueArea,
  OutsidePortugal(:final swapLooksRight) =>
    swapLooksRight
        ? '${l10n.issueOutside} ${l10n.issueSwap}'
        : l10n.issueOutside,
  LowConfidenceVertices() => l10n.issueLowAccuracy,
  TooManyVertices() => l10n.issueTooMany,
  // VAL-7 shows the overlap in m² whatever the area unit.
  OverlapsProperties(:final overlaps) => [
    for (final o in overlaps)
      l10n.issueOverlap(
        o.name,
        formatArea(
          o.areaSquareMetres,
          AreaUnit.squareMetres,
          languageCode: languageCode,
        ),
      ),
  ].join('\n'),
};
