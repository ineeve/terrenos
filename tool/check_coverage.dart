// Fails if line coverage in coverage/lcov.info is below the targets in
// PLAN.md §7. Run after `flutter test --coverage`.
//
// Usage: dart run tool/check_coverage.dart [coverage/lcov.info]
import 'dart:io';

/// Path prefix → minimum line coverage (%). Generated code is excluded.
const _targets = {'lib/core/': 90.0, 'lib/': 80.0};

const _excluded = ['lib/l10n/gen/'];

void main(List<String> args) {
  final path = args.isEmpty ? 'coverage/lcov.info' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('$path not found. Run `flutter test --coverage` first.');
    exit(2);
  }

  final hit = <String, int>{};
  final found = <String, int>{};
  String? current;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      current = line.substring(3).replaceAll(r'\', '/');
      final libIndex = current.indexOf('lib/');
      if (libIndex > 0) current = current.substring(libIndex);
    } else if (line.startsWith('LF:') && current != null) {
      found[current] = int.parse(line.substring(3));
    } else if (line.startsWith('LH:') && current != null) {
      hit[current] = int.parse(line.substring(3));
    }
  }

  var failed = false;
  for (final MapEntry(key: prefix, value: minimum) in _targets.entries) {
    var lines = 0;
    var covered = 0;
    for (final source in found.keys) {
      if (!source.startsWith(prefix)) continue;
      if (_excluded.any(source.startsWith)) continue;
      lines += found[source]!;
      covered += hit[source] ?? 0;
    }
    final percent = lines == 0 ? 100.0 : covered * 100 / lines;
    final ok = percent >= minimum;
    failed |= !ok;
    stdout.writeln(
      '${ok ? 'OK  ' : 'FAIL'} $prefix ${percent.toStringAsFixed(1)}% '
      '($covered/$lines lines, minimum $minimum%)',
    );
  }
  if (failed) exit(1);
}
