import 'dart:async';

import 'package:terrenos/core/location/location_source.dart';

/// A location source the test drives: set [current] and what
/// [requestAccess] returns, then [emit] fixes.
class FakeLocationSource implements LocationSource {
  new({this.current = LocationAccess.denied, LocationAccess? afterRequest})
    : afterRequest = afterRequest ?? current;

  LocationAccess current;
  LocationAccess afterRequest;
  int requests = 0;
  final openedSettings = <LocationAccess>[];
  final _fixes = StreamController<LocationFix>.broadcast();

  bool get listening => _fixes.hasListener;

  void emit(LocationFix fix) => _fixes.add(fix);

  void fail(Object error) => _fixes.addError(error);

  @override
  Future<LocationAccess> access() async => current;

  @override
  Future<LocationAccess> requestAccess() async {
    requests++;
    return current = afterRequest;
  }

  @override
  Stream<LocationFix> fixes() => _fixes.stream;

  @override
  Future<void> openSettings(LocationAccess access) async =>
      openedSettings.add(access);
}
