import 'package:glados/glados.dart';
import 'package:terrenos/core/crdt/hlc.dart';
import 'package:terrenos/core/crdt/lww.dart';

/// Small value ranges on purpose, so that collisions (equal millis, equal
/// counters, the same key) are frequent and the interesting cases get tested.
extension CrdtAnys on Any {
  Generator<String> get deviceId => choose(['dev-a', 'dev-b', 'dev-c']);

  Generator<Hlc> get hlc =>
      combine3(intInRange(0, 20), intInRange(0, 3), deviceId, Hlc.new);

  Generator<LwwRegister<String?>> get stringRegister => combine2(
    choose<String?>([null, 'x', 'y', 'z']),
    hlc,
    LwwRegister<String?>.new,
  );

  Generator<LwwMap<String>> get stringMap =>
      list(
        combine3(
          choose(['k1', 'k2', 'k3']),
          choose<String?>([null, 'x', 'y']),
          hlc,
          (key, value, t) => (key, value, t),
        ),
      ).map(
        (writes) => writes.fold(
          const LwwMap<String>(),
          (map, w) => map.put(w.$1, w.$2, w.$3),
        ),
      );
}
