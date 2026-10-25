// Fails unless every ARB file has exactly the same messages and placeholders
// as the English template (SPEC.md §10: PT-PT and EN at 100 %).
//
// Usage: dart run tool/check_arb.dart
import 'dart:convert';
import 'dart:io';

const _dir = 'lib/l10n';
const _template = 'app_en.arb';

final _placeholder = RegExp(r'\{(\w+)');

void main() {
  final template = _read('$_dir/$_template');
  final others = Directory(_dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb') && !f.path.endsWith(_template));

  var problems = 0;
  void report(String message) {
    problems++;
    stderr.writeln(message);
  }

  for (final file in others) {
    final name = file.uri.pathSegments.last;
    final messages = _read(file.path);
    for (final key in template.keys) {
      final translated = messages[key];
      if (translated == null) {
        report('$name: missing "$key"');
      } else if (!_samePlaceholders(template[key]!, translated)) {
        report('$name: "$key" has different placeholders than $_template');
      } else if (translated.trim().isEmpty) {
        report('$name: "$key" is empty');
      }
    }
    for (final key in messages.keys) {
      if (!template.containsKey(key)) report('$name: unknown key "$key"');
    }
  }

  if (problems > 0) {
    stderr.writeln('$problems translation problem(s).');
    exit(1);
  }
  stdout.writeln('Translations complete.');
}

/// Messages only; `@key` metadata and `@@locale` are skipped.
Map<String, String> _read(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return {
    for (final MapEntry(:key, :value) in json.entries)
      if (!key.startsWith('@')) key: value! as String,
  };
}

bool _samePlaceholders(String a, String b) {
  Set<String> names(String s) =>
      _placeholder.allMatches(s).map((m) => m.group(1)!).toSet();
  return names(a).length == names(b).length && names(a).containsAll(names(b));
}
