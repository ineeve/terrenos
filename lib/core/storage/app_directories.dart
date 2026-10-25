/// The on-disk layout of the app's private directory (SPEC.md §8.1).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class AppDirectories {
  new(this.root);

  final Directory root;

  File get deviceFile => File(p.join(root.path, 'device.json'));
  File get settingsFile => File(p.join(root.path, 'settings.json'));
  Directory get groups => _dir('groups');
  Directory get properties => _dir('properties');
  Directory get drafts => _dir('drafts');
  Directory get blobs => _dir('blobs');
  Directory get thumbs => _dir('thumbs');
  Directory get tiles => _dir('tiles');
  Directory get quarantine => _dir('quarantine');
  Directory get logs => _dir('logs');

  Directory _dir(String name) => Directory(p.join(root.path, name));

  Future<void> ensureCreated() async {
    for (final dir in [
      root,
      groups,
      properties,
      drafts,
      blobs,
      thumbs,
      tiles,
      quarantine,
      logs,
    ]) {
      await dir.create(recursive: true);
    }
  }
}
