import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'json_store.dart';

/// Thrown when the bookmarks document EXISTS but cannot be parsed (partial/
/// truncated write, malformed JSON, a JSON value of the wrong shape, etc.).
///
/// This is surfaced LOUDLY instead of being swallowed: silently resetting the
/// in-memory cache to `[]` here would let the next `add`/`remove` overwrite the
/// corrupt-but-partially-recoverable document with empty (or single-entry) data
/// — permanent, silent bookmark loss. The corrupt document is left untouched in
/// its store so the caller (UI) can offer recovery. See F-3 / QS-3.
///
/// Storage is platform-abstracted via [JsonDocumentStore] (a file on native, a
/// localStorage slot on Web), so [path] carries a best-effort identifier (the
/// store key) and may be `null` when no path concept applies (e.g. Web).
class BookmarksLoadException implements Exception {
  BookmarksLoadException(this.cause, {this.path});

  /// The underlying error (FormatException, …).
  final Object cause;

  /// Best-effort identifier of the store/document that failed to load, when
  /// known. May be `null` (e.g. on Web there is no filesystem path).
  final String? path;

  @override
  String toString() {
    final where = path == null ? '' : ' ($path)';
    return 'BookmarksLoadException: could not read bookmarks$where: $cause';
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

/// Manages the user's saved canister/method bookmarks.
///
/// Persistence is routed through the web-aware [JsonDocumentStore] (one file on
/// native, a `localStorage` slot on Web) — so bookmarks work on Flutter Web,
/// which direct filesystem `File` access never could. The store key is
/// [_storeKey]; the persisted shape is a bare JSON array of [BookmarkEntry].
class BookmarksService {
  /// Single source for this service's [JsonDocumentStore] key name. Mirrors the
  /// short-key convention used by the sibling repositories (`'profiles'`,
  /// `'scripts'`).
  static const String _storeKey = 'bookmarks';

  static List<BookmarkEntry> _cachedBookmarks = [];
  static bool _isCacheDirty = true;

  /// Test-only injected store. When `null`, the platform-default store is built
  /// lazily via [openJsonDocumentStore] (a [FileJsonStore] on native, a
  /// [WebJsonStore] in the browser). Production code MUST NOT touch this.
  static JsonDocumentStore? _injectedStore;

  static JsonDocumentStore get _docStore =>
      _injectedStore ?? openJsonDocumentStore();

  /// Test-only seam: back the service with a specific [JsonDocumentStore] (e.g.
  /// a [FileJsonStore] rooted at a temp dir). Pass `null` to restore the
  /// platform-default store. Also drops the in-memory cache so the next read
  /// hits the freshly-injected store. Production code MUST NOT call this.
  @visibleForTesting
  static void overrideStoreForTesting(JsonDocumentStore? store) {
    _injectedStore = store;
    invalidateCache();
  }

  static Future<List<BookmarkEntry>> list() async {
    await _ensureLoaded();
    return List.unmodifiable(_cachedBookmarks);
  }

  /// Loads from storage on demand. Throws [BookmarksLoadException] (rethrown
  /// to the caller) if the document is corrupt — the cache is left UNTOUCHED in
  /// that case so a later save cannot poison/overwrite the corrupt document.
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
    // Never mutate+save unless the stored document has been successfully read:
    // if it is corrupt, _ensureLoaded throws and we abort BEFORE touching the
    // cache or writing — preventing a poisoned save from clobbering the
    // corrupt-but-partially-recoverable document. See F-3 / QS-3.
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
    final JsonDocumentStore store = _docStore;

    // The store returns null for an ABSENT key OR a whitespace-only value
    // (documented [JsonDocumentStore] contract: callers can rely on
    // `null` ⇔ "no data" regardless of platform). Either way this is the
    // legitimate first-run / clean-wipe state → empty is correct and must NOT
    // raise. Only an existing-but-unparseable or wrong-shape document is
    // corruption. (An empty/whitespace value carries no recoverable entries, so
    // normalizing it to "absent" cannot lose data — unlike genuinely malformed
    // JSON, which still throws loudly below.)
    final String? jsonString;
    try {
      jsonString = await store.read(_storeKey);
    } on TimeoutException {
      rethrow;
    } catch (e) {
      // Document exists but the bytes can't be read (permissions, disk error,
      // …). Surface loudly; leave the cache untouched so the caller can recover
      // and the next save cannot overwrite this document.
      throw BookmarksLoadException(e, path: _storeKey);
    }

    if (jsonString == null) {
      _cachedBookmarks = [];
      return;
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
      // Malformed JSON or a non-array / bad-entry document. DO NOT reset the
      // cache to [] here: that would let the next save clobber this
      // corrupt-but-partially-recoverable document → silent data loss
      // (F-3 / QS-3).
      throw BookmarksLoadException(e, path: _storeKey);
    }
  }

  static Future<void> _saveToStorage() async {
    try {
      final jsonString = json.encode(
        _cachedBookmarks.map((entry) => entry.toJson()).toList(),
      );
      await _docStore.write(_storeKey, jsonString);
    } catch (e) {
      // Fail-fast: rethrow the error to make it visible.
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
