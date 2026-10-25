/// Offline areas and their downloads (MAP-7, MAP-8).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/core/map/offline_area.dart';
import 'package:terrenos/core/map/tile_downloader.dart';
import 'package:uuid/uuid.dart';

@immutable
class OfflineAreasState {
  const new({
    this.areas = const [],
    this.activeId,
    this.progress,
    this.queued = const [],
  });

  /// Newest first.
  final List<OfflineArea> areas;

  /// The area being downloaded now; downloads run one at a time.
  final String? activeId;
  final DownloadProgress? progress;

  /// Areas waiting for their turn.
  final List<String> queued;

  bool isBusy(String id) => id == activeId || queued.contains(id);

  OfflineAreasState copyWith({
    List<OfflineArea>? areas,
    String? Function()? activeId,
    DownloadProgress? Function()? progress,
    List<String>? queued,
  }) => OfflineAreasState(
    areas: areas ?? this.areas,
    activeId: activeId != null ? activeId() : this.activeId,
    progress: progress != null ? progress() : this.progress,
    queued: queued ?? this.queued,
  );
}

final offlineAreasProvider =
    NotifierProvider<OfflineAreasController, OfflineAreasState>(
      OfflineAreasController.new,
    );

/// Bytes used by downloaded areas and by the browsing cache (SET-8).
final offlineStorageUsageProvider = FutureProvider<({int areas, int browsing})>(
  (ref) async {
    // Recount when areas are added, finished or deleted.
    ref.watch(
      offlineAreasProvider.select(
        (s) => (s.areas.length, s.activeId, s.queued.length),
      ),
    );
    final areas = await ref.read(tileStorageProvider).totalBytes();
    final browsing = await ref.read(browseCacheProvider).totalBytes();
    return (areas: areas, browsing: browsing);
  },
);

class OfflineAreasController extends Notifier<OfflineAreasState> {
  final _refresh = <String>{};
  bool _cancelActive = false;
  Future<void>? _running;
  Future<DownloadOutcome>? _activeDownload;

  /// Areas deleted while downloading, whose result must not be saved.
  final _discarded = <String>{};

  /// The last write of the area list; writes run one at a time.
  Future<void> _saving = Future.value();

  @override
  OfflineAreasState build() {
    ref.onDispose(() => _cancelActive = true);
    final areas = ref.read(tileStorageProvider).loadAreas()
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return OfflineAreasState(areas: areas);
  }

  TileDownloader get _downloader => TileDownloader(
    fetch: ref.read(tileFetcherProvider),
    storage: ref.read(tileStorageProvider),
  );

  OfflineArea? _area(String id) =>
      state.areas.where((a) => a.id == id).firstOrNull;

  /// Saves a new area and queues its download.
  Future<OfflineArea> add({
    required String name,
    required ImagerySource source,
    required LatLngBounds bounds,
    required OfflineDetail detail,
  }) async {
    final area = OfflineArea(
      id: const Uuid().v7(),
      name: name.trim(),
      source: source,
      bounds: bounds,
      detail: detail,
      downloadedAt: DateTime.now().toUtc(),
    );
    await _save([area, ...state.areas]);
    _enqueue(area.id);
    return area;
  }

  /// Continues a download that stopped; saved tiles are kept.
  void resume(String id) => _enqueue(id);

  /// Downloads every tile of the area again (MAP-8).
  void refresh(String id) {
    _refresh.add(id);
    _enqueue(id);
  }

  void cancel(String id) {
    if (id == state.activeId) _cancelActive = true;
    _refresh.remove(id);
    state = state.copyWith(queued: [...state.queued.where((q) => q != id)]);
  }

  /// Deletes the area's tiles, except those another area still needs.
  Future<void> delete(String id) async {
    final area = _area(id);
    if (area == null) return;
    final wasActive = state.activeId == id;
    if (wasActive) _discarded.add(id);
    cancel(id);
    if (wasActive) await _activeDownload;
    final others = state.areas.where((a) => a.id != id).toList();
    await ref
        .read(tileStorageProvider)
        .delete(
          area.source,
          area.tiles.where(
            (t) => !others.any((other) => other.covers(area.source, t)),
          ),
        );
    await _save([...state.areas.where((a) => a.id != id)]);
  }

  Future<void> deleteAll() async {
    _refresh.clear();
    state = state.copyWith(queued: const []);
    if (state.activeId case final id?) {
      _discarded.add(id);
      _cancelActive = true;
      await _activeDownload;
    }
    await _saving.catchError((Object _) {});
    await ref.read(tileStorageProvider).clear();
    state = state.copyWith(areas: const []);
  }

  void _enqueue(String id) {
    if (state.isBusy(id)) return;
    state = state.copyWith(queued: [...state.queued, id]);
    _running ??= _run();
  }

  /// Downloads queued areas one after another.
  Future<void> _run() async {
    while (ref.mounted && state.queued.isNotEmpty) {
      final id = state.queued.first;
      final area = _area(id);
      state = state.copyWith(
        queued: state.queued.skip(1).toList(),
        activeId: () => area?.id,
        progress: () => null,
      );
      if (area == null) continue;
      _cancelActive = false;
      final refresh = _refresh.remove(id);
      var saved = area.copyWith(downloadedAt: DateTime.now().toUtc());
      await _replace(saved);

      final outcome = await (_activeDownload = _downloader.download(
        area,
        refresh: refresh,
        isCancelled: () => _cancelActive,
        onProgress: (p) {
          if (!ref.mounted) return;
          saved = saved.copyWith(savedTiles: p.saved, savedBytes: p.bytes);
          state = state.copyWith(progress: () => p);
        },
      ));
      if (!ref.mounted) return;
      saved = saved.copyWith(complete: outcome == DownloadOutcome.complete);
      // The area may have been deleted while it was downloading.
      if (!_discarded.remove(id) && _area(id) != null) await _replace(saved);
      state = state.copyWith(activeId: () => null, progress: () => null);
    }
    _running = null;
  }

  Future<void> _replace(OfflineArea area) => _save([
    for (final a in state.areas)
      if (a.id == area.id) area else a,
  ]);

  /// Updates the list now and writes it after any earlier write, so the
  /// file always ends with the latest list. A failed write doesn't block
  /// later ones.
  Future<void> _save(List<OfflineArea> areas) {
    state = state.copyWith(areas: areas);
    final storage = ref.read(tileStorageProvider);
    return _saving = _saving
        .catchError((Object _) {})
        .then((_) => storage.saveAreas(areas));
  }
}
