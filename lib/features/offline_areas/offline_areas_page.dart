import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/format/size_format.dart';
import 'package:terrenos/core/map/offline_area.dart';
import 'package:terrenos/features/offline_areas/offline_areas_controller.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Offline maps: downloaded areas and stored imagery (MAP-8, SET-8).
class OfflineAreasPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final state = ref.watch(offlineAreasProvider);
    final usage = ref.watch(offlineStorageUsageProvider).value;
    String size(int bytes) => formatBytes(bytes, languageCode: language);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.offlineMapsTitle),
        actions: [
          if (state.areas.isNotEmpty)
            PopupMenuButton<void>(
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => unawaited(_confirmDeleteAll(context, ref)),
                  child: Text(l10n.offlineDeleteAll),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(context.push(Routes.offlineAreaNew)),
        icon: const Icon(Icons.add),
        label: Text(l10n.offlineDownloadArea),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: Text(l10n.offlineDownloadedAreas),
            subtitle: usage == null ? null : Text(size(usage.areas)),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.offlineBrowseCache),
            subtitle: Text(
              l10n.offlineBrowseCacheHint(
                usage == null ? '…' : size(usage.browsing),
              ),
            ),
            isThreeLine: true,
            trailing: TextButton(
              onPressed: usage == null || usage.browsing == 0
                  ? null
                  : () async {
                      await ref.read(browseCacheProvider).clear();
                      ref.invalidate(offlineStorageUsageProvider);
                    },
              child: Text(l10n.actionClear),
            ),
          ),
          const Divider(),
          if (state.areas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l10n.offlineAreasEmpty, textAlign: TextAlign.center),
            ),
          for (final area in state.areas) _AreaTile(area: area),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.offlineDeleteAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (ok ?? false) await ref.read(offlineAreasProvider.notifier).deleteAll();
  }
}

enum _AreaAction { resume, stop, downloadAgain, delete }

class _AreaTile extends ConsumerWidget {
  const new({required this.area});

  final OfflineArea area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final state = ref.watch(offlineAreasProvider);
    final controller = ref.read(offlineAreasProvider.notifier);
    String count(int n) => formatCount(n, languageCode: language);

    final active = state.activeId == area.id;
    final queued = state.queued.contains(area.id);
    final progress = active ? state.progress : null;
    final detail = switch (area.detail) {
      OfflineDetail.normal => l10n.offlineDetailNormal,
      OfflineDetail.high => l10n.offlineDetailHigh,
    };
    final status = active
        ? l10n.offlineStatusDownloading(
            ((progress?.fraction ?? 0) * 100).floor(),
          )
        : queued
        ? l10n.offlineStatusQueued
        : area.complete
        ? l10n.offlineTiles(
            formatBytes(area.savedBytes, languageCode: language),
            count(area.savedTiles),
          )
        : l10n.offlineStatusIncomplete(
            count(area.savedTiles),
            count(area.tileCount),
          );

    return ListTile(
      leading: active
          ? SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(value: progress?.fraction),
            )
          : Icon(
              area.complete && !queued
                  ? Icons.offline_pin
                  : Icons.downloading_outlined,
            ),
      title: Text(area.name),
      subtitle: Text(
        '${l10n.imageryPrevious('${area.source.year}')} · $detail\n$status',
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<_AreaAction>(
        onSelected: (action) async {
          switch (action) {
            case _AreaAction.resume:
              controller.resume(area.id);
            case _AreaAction.stop:
              controller.cancel(area.id);
            case _AreaAction.downloadAgain:
              controller.refresh(area.id);
            case _AreaAction.delete:
              if (await _confirmDelete(context)) {
                await controller.delete(area.id);
              }
          }
        },
        itemBuilder: (context) => [
          if (active || queued)
            PopupMenuItem(value: _AreaAction.stop, child: Text(l10n.actionStop))
          else if (area.complete)
            PopupMenuItem(
              value: _AreaAction.downloadAgain,
              child: Text(l10n.actionDownloadAgain),
            )
          else
            PopupMenuItem(
              value: _AreaAction.resume,
              child: Text(l10n.actionResume),
            ),
          PopupMenuItem(
            value: _AreaAction.delete,
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.offlineDeleteConfirm(area.name)),
        content: Text(l10n.offlineDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
