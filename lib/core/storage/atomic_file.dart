/// Crash-safe text files (SPEC.md §8.3).
///
/// A write goes to `<file>.tmp` first and replaces the target with a rename,
/// keeping the previous version as `<file>.bak`. A crash at any point leaves
/// either the old or the new content readable, never a half-written file.
library;

import 'dart:io';

class AtomicFile {
  new(String path)
    : file = File(path),
      _tmp = File('$path.tmp'),
      _bak = File('$path.bak');

  final File file;
  final File _tmp;
  final File _bak;

  File get backup => _bak;

  Future<void> write(String contents) async {
    await _tmp.writeAsString(contents, flush: true);
    if (file.existsSync()) await file.rename(_bak.path);
    await _tmp.rename(file.path);
  }

  void writeSync(String contents) {
    _tmp.writeAsStringSync(contents, flush: true);
    if (file.existsSync()) file.renameSync(_bak.path);
    _tmp.renameSync(file.path);
  }

  /// Reads and parses the file, falling back to the backup if the main file
  /// is missing or [parse] throws. Returns `null` if neither exists.
  ///
  /// Errors from the main file are rethrown when there is no usable backup.
  AtomicReadResult<T>? read<T>(T Function(String contents) parse) {
    Object? mainError;
    StackTrace? mainStack;
    if (file.existsSync()) {
      try {
        return AtomicReadResult(parse(file.readAsStringSync()));
      } on Object catch (e, s) {
        mainError = e;
        mainStack = s;
      }
    }
    if (_bak.existsSync()) {
      try {
        return AtomicReadResult(
          parse(_bak.readAsStringSync()),
          recoveredFromBackup: true,
        );
      } on Object {
        // Fall through and report the main file's error, which is the more
        // useful one.
      }
    }
    if (mainError != null) Error.throwWithStackTrace(mainError, mainStack!);
    return null;
  }

  /// Deletes the file and its backup and temporary copies.
  Future<void> delete() async {
    for (final f in [file, _tmp, _bak]) {
      if (f.existsSync()) await f.delete();
    }
  }
}

class AtomicReadResult<T> {
  new(this.value, {this.recoveredFromBackup = false});

  final T value;
  final bool recoveredFromBackup;
}
