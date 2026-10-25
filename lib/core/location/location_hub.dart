/// The app's one GPS stream (SPEC.md §7.3, REG-13, MAP-4).
///
/// geolocator keeps a single position stream per app and ignores new
/// settings while it runs, so the map's position dot and walk mode can't
/// each open their own. Everything listens here instead. The underlying
/// stream restarts with the recording notice while anything records, so
/// walk mode keeps going with the screen off even if the map was already
/// showing the position.
library;

import 'dart:async';

import 'package:terrenos/core/location/location_source.dart';

class LocationHub {
  new(this._source);

  final LocationSource _source;
  final _fixes = StreamController<LocationFix>.broadcast(sync: true);

  /// The notice of each listener that records, by listener.
  final _recording = <Object, RecordingNotice>{};
  int _listeners = 0;

  StreamSubscription<LocationFix>? _upstream;
  RecordingNotice? _upstreamNotice;

  /// Fixes while listened to. With [notice], the stream runs as a
  /// foreground service until this listener cancels (REG-13).
  Stream<LocationFix> fixes({RecordingNotice? notice}) {
    final token = Object();
    StreamSubscription<LocationFix>? relay;
    late final StreamController<LocationFix> controller;
    controller = StreamController<LocationFix>(
      onListen: () {
        _listeners++;
        if (notice != null) _recording[token] = notice;
        relay = _fixes.stream.listen(
          controller.add,
          onError: controller.addError,
        );
        _restart();
      },
      onCancel: () {
        unawaited(relay?.cancel());
        _listeners--;
        _recording.remove(token);
        _restart();
      },
    );
    return controller.stream;
  }

  /// Listeners right now, recording or not.
  int get listeners => _listeners;

  /// Whether the GPS stream is running, and with which notice.
  bool get isRunning => _upstream != null;
  RecordingNotice? get notice => _upstreamNotice;

  /// Starts, stops or restarts the GPS stream to match the listeners.
  /// Synchronous on purpose: cancelling clears geolocator's stream at once,
  /// so the new one gets the new settings.
  void _restart() {
    final wanted = _listeners == 0 ? null : _recording.values.firstOrNull;
    if (_listeners > 0 && _upstream != null && wanted == _upstreamNotice) {
      return;
    }
    unawaited(_upstream?.cancel());
    _upstream = null;
    _upstreamNotice = null;
    if (_listeners == 0) return;
    _upstreamNotice = wanted;
    _upstream = _source
        .fixes(notice: wanted)
        .listen(
          _fixes.add,
          onError: (Object e, StackTrace s) {
            // The stream ends after an error (e.g. location turned off);
            // the next listener starts a new one.
            _upstream = null;
            _upstreamNotice = null;
            _fixes.addError(e, s);
          },
          onDone: () {
            _upstream = null;
            _upstreamNotice = null;
          },
          cancelOnError: true,
        );
  }

  /// Stops the GPS stream; listeners get nothing more.
  Future<void> dispose() async {
    await _upstream?.cancel();
    _upstream = null;
    await _fixes.close();
  }
}
