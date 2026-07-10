import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'file_io.dart';

/// Thrown when the on-disk bookmarks file EXISTS but cannot be read or parsed
/// (partial/truncated write, disk error, bad encoding, malformed JSON, or an
/// empty/whitespace file — a legitimately-empty store is the 2-byte `"[]"`,
/// never 0 bytes).
///
/// This is surfaced LOUDLY instead of being swallowed: silently resetting the
/// in-memory cache to `[]` here would let the next `add`/`remove` overwrite the
/// corrupt-but-partially-recoverable file with empty (or single-entry) data —
/// permanent, silent bookmark loss. The corrupt file is left untouched on disk
/// so the caller (UI) can offer recovery. See F-3 / QS-3.
class BookmarksLoadException implements Exception {
  BookmarksLoadException(this.cause, {this.path});

  /// The underlying error (FormatException, FileSystemException, …).
  final Object cause;

  /// Path of the file that failed to load, when known.
  final String? path;

  @override
  String toString() {
    final where = path == null ? '' : ' ($path)';
    return 'BookmarksLoadException: could not read bookmarks file$where: $cause';
  }
}

class BookmarkEntry {
  BookmarkEntry({
    required this.canisterId,
    required this.method,
    this.label,
  });

  factory BookmarkEntry.fromJson(Map<String, dynamic> json) {
    return BookmarkEntry(
      canisterId: json['canister_id'] as String,
      method: json['method'] as String,
      label: json['label'] as String?,
    );
  }

  final String canisterId;
  final String method;
  final String? label;

  Map<String, dynamic> toJson() {
    return {
      'canister_id': canisterId,
      'method': method,
      if (label != null) 'label': label,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BookmarkEntry &&
        other.canisterId == canisterId &&
        other.method == method;
  }

  @override
  int get hashCode => canisterId.hashCode ^ method.hashCode;
}

class BookmarksService {
  static const String _fileName = 'icp_bookmarks.json';
  static List<BookmarkEntry> _cachedBookmarks = [];
  static bool _isCacheDirty = true;

  static Future<List<BookmarkEntry>> list() async {
    await _ensureLoaded();
    return List.unmodifiable(_cachedBookmarks);
  }

  /// Loads from storage on demand. Throws [BookmarksLoadException] (rethrown
  /// to the caller) if the file is corrupt — the cache is left UNTOUCHED in
  /// that case so a later save cannot poison/overwrite the corrupt file.
  static Future<void> _ensureLoaded() async {
    if (_isCacheDirty) {
      await _loadFromStorage();
      _isCacheDirty = false;
    }
  }

  static Future<void> add({
    required String canisterId,
    required String method,
    String? label,
  }) async {
    // Never mutate+save unless the on-disk file has been successfully read:
    // if the file is corrupt, _ensureLoaded throws and we abort BEFORE touching
    // the cache or writing — preventing a poisoned save from clobbering the
    // corrupt-but-partially-recoverable file. See F-3 / QS-3.
    await _ensureLoaded();

    final newEntry = BookmarkEntry(
      canisterId: canisterId,
      method: method,
      label: label,
    );

    // Remove existing entry with same canisterId and method
    _cachedBookmarks.removeWhere((entry) =>
        entry.canisterId == canisterId && entry.method == method);

    // Add new entry
    _cachedBookmarks.add(newEntry);

    await _saveToStorage();
    BookmarksEvents.notifyChanged();
  }

  static Future<void> remove({
    required String canisterId,
    required String method,
  }) async {
    // See add(): load must succeed before any mutation+save.
    await _ensureLoaded();

    _cachedBookmarks.removeWhere((entry) =>
        entry.canisterId == canisterId && entry.method == method);

    await _saveToStorage();
    BookmarksEvents.notifyChanged();
  }

  static Future<void> _loadFromStorage() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$_fileName');

    // A genuinely MISSING file is a first run (or a clean wipe): empty is the
    // correct, expected state and must NOT raise — otherwise first launch
    // would show a scary error. Only an existing-but-unreadable or
    // existing-but-unparseable file is corruption.
    if (!await file.exists()) {
      _cachedBookmarks = [];
      return;
    }

    final String jsonString;
    try {
      jsonString = await readJson(file);
    } on TimeoutException {
      rethrow;
    } catch (e) {
      // File exists but the bytes can't be read (permissions, disk error, …).
      // Surface loudly; leave the cache + the file untouched so the caller can
      // recover and the next save cannot overwrite this file.
      throw BookmarksLoadException(e, path: file.path);
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      _cachedBookmarks = jsonList
          .whereType<Map<String, dynamic>>()
          .map((json) => BookmarkEntry.fromJson(json))
          .toList();
    } on TimeoutException {
      rethrow;
    } catch (e) {
      // Malformed JSON — including an empty/whitespace file, since a valid
      // empty store is the 2-byte "[]", never 0 bytes. (An empty file can
      // only result from a truncated write or external tampering.) DO NOT
      // reset the cache to [] here: that would let the next save clobber this
      // corrupt-but-partially-recoverable file → silent data loss (F-3/QS-3).
      throw BookmarksLoadException(e, path: file.path);
    }
  }

  static Future<void> _saveToStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');

      final jsonString = json.encode(
        _cachedBookmarks.map((entry) => entry.toJson()).toList(),
      );
      await writeJson(file, jsonString);
    } catch (e) {
      // Fail-fast: rethrow the error to make it visible
      throw Exception('Failed to save bookmarks: $e');
    }
  }

  static void invalidateCache() {
    _isCacheDirty = true;
  }
}

class BookmarksEvents {
  static final _notifier = ValueNotifier<int>(0);

  static ValueNotifier<int> get listenable => _notifier;

  static void notifyChanged() {
    _notifier.value++;
  }
}