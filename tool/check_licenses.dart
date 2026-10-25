// Fails if any Dart dependency is under a copyleft licence that would bind
// the distributed MIT app (SPEC.md §5.3): GPL, LGPL or AGPL.
//
// Reads the licence files of every package in .dart_tool/package_config.json,
// so run `flutter pub get` first.
//
// Usage: dart run tool/check_licenses.dart
import 'dart:convert';
import 'dart:io';

/// Packages reviewed and accepted despite matching a copyleft pattern, with
/// the reason. Changing this list needs review (PLAN.md §7).
const _allowed = <String, String>{};

final _copyleft = {
  'AGPL': RegExp('GNU AFFERO GENERAL PUBLIC LICENSE', caseSensitive: false),
  'LGPL': RegExp('GNU LESSER GENERAL PUBLIC LICENSE', caseSensitive: false),
  'GPL': RegExp('GNU GENERAL PUBLIC LICENSE', caseSensitive: false),
};

void main() {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    stderr.writeln('Run `flutter pub get` first.');
    exit(2);
  }
  final packages =
      (jsonDecode(config.readAsStringSync())
              as Map<String, Object?>)['packages']!
          as List<Object?>;

  final problems = <String>[];
  var checked = 0;
  for (final entry in packages.cast<Map<String, Object?>>()) {
    final name = entry['name']! as String;
    if (name == 'terrenos') continue;
    final root = Directory.fromUri(
      config.uri.resolve(entry['rootUri']! as String),
    );
    final licenseFiles = _licenseFiles(root);
    if (licenseFiles.isEmpty) {
      problems.add('$name: no licence file found in ${root.path}');
      continue;
    }
    checked++;
    final text = licenseFiles.map((f) => f.readAsStringSync()).join('\n');
    // A package may be dual-licensed (e.g. "MIT or GPL"); those still match
    // and need a reviewed entry in _allowed.
    final match = _copyleft.entries.where((e) => e.value.hasMatch(text));
    if (match.isNotEmpty && !_allowed.containsKey(name)) {
      problems.add('$name: ${match.first.key} licence text found');
    }
  }

  if (problems.isNotEmpty) {
    problems.forEach(stderr.writeln);
    exit(1);
  }
  stdout.writeln('Licences OK ($checked packages checked).');
}

final _licenseName = RegExp('^(LICEN[CS]E|COPYING)', caseSensitive: false);

/// Licence files in [root], or in its nearest ancestor that has one: Flutter
/// SDK packages such as flutter_localizations are covered by the SDK's
/// top-level LICENSE.
List<File> _licenseFiles(Directory root) {
  var dir = root;
  for (var level = 0; level < 3 && dir.existsSync(); level++) {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => _licenseName.hasMatch(f.uri.pathSegments.last))
        .toList();
    if (files.isNotEmpty) return files;
    dir = dir.parent;
  }
  return const [];
}
