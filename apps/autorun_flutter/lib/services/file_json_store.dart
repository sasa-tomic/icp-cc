/// IO implementation of [JsonDocumentStore] (WU-1).
///
/// Selected by [json_store.dart]'s conditional export on every non-Web target.
/// One file per key: `<directory>/<key>.json`. File I/O goes through the
/// existing `file_io.dart` `readJson`/`writeJson` helpers, which already apply
/// the `AppDurations.ioOperation` timeout — so every call here is bounded.
///
/// The directory is resolved (lazily, on first use) as, in priority order:
/// 1. the [overrideDirectory] passed to the constructor (test injection), else
/// 2. `path_provider`'s `getApplicationSupportDirectory()`, else
/// 3. a fresh temp dir under `Directory.systemTemp` (restricted/test envs).
///
/// This mirrors the directory-resolution logic the repositories used to inline,
/// now centralised here so both repositories and any future caller share it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'file_io.dart' as file_io;
import 'json_store.dart';

/// Key characters permitted in a [JsonDocumentStore] key. Restricted to a safe
/// filename subset so a key can never escape its `<key>.json` slot via path
/// traversal or odd characters. Anything else is rejected loudly.
final RegExp _safeKey = RegExp(r'^[A-Za-z0-9_]+$');

/// Validates that [key] is a safe store key. Throws [ArgumentError] otherwise —
/// store keys are programmer-controlled constants, so an invalid one is a bug.
void _validateKey(String key) {
  if (!_safeKey.hasMatch(key)) {
    throw ArgumentError.value(
      key,
      'key',
      'JsonDocumentStore keys must be alphanumeric + underscore only '
          '(got: $key).',
    );
  }
}

/// `JsonDocumentStore` backed by one JSON file per key on the local filesystem.
class FileJsonStore implements JsonDocumentStore {
  /// Creates a file-backed store rooted at [overrideDirectory] when given, or
  /// at the platform app-support directory (with a temp-dir fallback) otherwise.
  ///
  /// Pass [overrideDirectory] only for tests; production callers should omit it
  /// and let the default resolution pick the right platform directory.
  FileJsonStore({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory;

  final Directory? _overrideDirectory;
  Directory? _resolvedDirectory;

  /// Resolves (and ensures) the storage directory on first use. Lazy so the
  /// store can be constructed cheaply and only touches the filesystem when a
  /// read/write/delete actually runs.
  Future<Directory> _directory() async {
    final Directory? cached = _resolvedDirectory;
    if (cached != null) {
      return cached;
    }

    Directory directory;
    final Directory? override = _overrideDirectory;
    if (override != null) {
      directory = override;
    } else {
      try {
        directory = await getApplicationSupportDirectory();
      } catch (e, st) {
        debugPrint('FileJsonStore: path_provider unavailable, falling back to '
            'temp dir: $e\n$st');
        directory = await Directory.systemTemp.createTemp('icp_autorun_store_');
      }
    }

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    _resolvedDirectory = directory;
    return directory;
  }

  Future<File> _fileFor(String key) async {
    _validateKey(key);
    final Directory directory = await _directory();
    return File('${directory.path}/$key.json');
  }

  @override
  Future<String?> read(String key) async {
    final File file = await _fileFor(key);
    if (!await file.exists()) {
      return null;
    }
    final String content = await file_io.readJson(file);
    if (content.trim().isEmpty) {
      return null;
    }
    return content;
  }

  @override
  Future<void> write(String key, String json) async {
    final File file = await _fileFor(key);
    // The directory is guaranteed to exist after `_fileFor` → `_directory`,
    // but be defensive: a caller may write to a store whose override dir was
    // deleted mid-session. `create(recursive: true)` is idempotent.
    await file.parent.create(recursive: true);
    await file_io.writeJson(file, json);
  }

  @override
  Future<void> delete(String key) async {
    final File file = await _fileFor(key);
    if (await file.exists()) {
      await file.delete();
    }
    // Idempotent: deleting an absent key is a no-op.
  }
}

/// Platform-default store constructor re-exported via [json_store.dart]'s
/// conditional export. On IO this returns a [FileJsonStore]; on Web the
/// counterpart in `web_json_store.dart` returns a localStorage-backed store.
///
/// Pass [overrideDirectory] to force a specific filesystem location (tests).
/// On Web the argument is accepted (for a uniform call site) and ignored — the
/// browser has no filesystem.
JsonDocumentStore openJsonDocumentStore({Directory? overrideDirectory}) =>
    FileJsonStore(overrideDirectory: overrideDirectory);
