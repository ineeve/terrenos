import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/editing/boundary_fixes.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/features/vertices/vertex_format.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// "5/8 vértices levantados" (VTX-11).
class SurveyProgress extends StatelessWidget {
  const new({required this.vertices, super.key});

  final List<Vertex> vertices;

  @override
  Widget build(BuildContext context) {
    final surveyed = vertices.where((v) => v.isSurveyed).length;
    return Text(
      AppLocalizations.of(context)
          .vertexSurveyedCount('$surveyed', '${vertices.length}'),
      style: Theme.of(context).textTheme.labelLarge,
    );
  }
}

/// One row per vertex: label, coordinates in the user's format, source,
/// and planned/surveyed status (VTX-2). A sliver that builds only the rows
/// on screen, so a boundary at the 5 000-vertex limit (VAL-9) still scrolls
/// smoothly; place it in a [CustomScrollView].
class VertexRows extends ConsumerWidget {
  const new({
    required this.vertices,
    this.vertexInfo = const {},
    this.onTap,
    super.key,
  });

  final List<Vertex> vertices;
  final Map<String, Map<String, Object?>> vertexInfo;
  final void Function(Vertex vertex, int index)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(
      settingsProvider.select((s) => s.coordinateFormat),
    );
    final language = Localizations.localeOf(context).languageCode;
    return SliverList.builder(
      itemCount: vertices.length,
      itemBuilder: (context, i) => _row(
        context,
        l10n,
        vertices[i],
        i,
        formatVertex(vertices[i], format, language),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    Vertex v,
    int index,
    (String, String) coordinates,
  ) {
    final (sourceIcon, sourceLabel) = switch (v.source) {
      VertexSource.gps => (Icons.gps_fixed, l10n.vertexSourceGps),
      VertexSource.typed => (Icons.keyboard, l10n.vertexSourceTyped),
      VertexSource.map => (Icons.touch_app, l10n.vertexSourceMap),
      VertexSource.import => (Icons.file_open, l10n.vertexSourceImport),
    };
    final status = v.isSurveyed ? l10n.vertexSurveyed : l10n.vertexPlanned;
    final accuracy = v.gps == null
        ? ''
        : ' · ±${v.gps!.accuracyMetres.toStringAsFixed(0)} m';
    final colours = Theme.of(context).colorScheme;
    return ListTile(
      leading: Semantics(
        label: status,
        child: Icon(
          v.isSurveyed ? Icons.circle : Icons.circle_outlined,
          color: colours.primary,
        ),
      ),
      title: Text(vertexLabel(index, vertexInfo[v.id])),
      subtitle: Text('${coordinates.$1}\n${coordinates.$2}'),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // VAL-8: imprecise or mocked GPS.
          if (isLowConfidence(v))
            Tooltip(
              message: l10n.vertexLowConfidence,
              child: Icon(
                Icons.warning_amber,
                color: colours.error,
                semanticLabel: l10n.vertexLowConfidence,
              ),
            ),
          Tooltip(
            message: '$sourceLabel$accuracy',
            child: Icon(sourceIcon, semanticLabel: '$sourceLabel$accuracy'),
          ),
        ],
      ),
      onTap: onTap == null ? null : () => onTap!(v, index),
    );
  }
}
