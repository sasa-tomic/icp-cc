import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

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
    if (_isCacheDirty) {
      await _loadFromStorage();
      _isCacheDirty = false;
    }
    return List.unmodifiable(_cachedBookmarks);
  }

  static Future<void> add({
    required String canisterId,
    required String method,
    String? label,
  }) async {
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
    _cachedBookmarks.removeWhere((entry) =>
        entry.canisterId == canisterId && entry.method == method);

    await _saveToStorage();
    BookmarksEvents.notifyChanged();
  }

  static Future<void> _loadFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');

      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.isNotEmpty) {
          final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
          _cachedBookmarks = jsonList
              .whereType<Map<String, dynamic>>()
              .map((json) => BookmarkEntry.fromJson(json))
              .toList();
          return;
        }
      }
      _cachedBookmarks = [];
    } catch (e) {
      // If loading fails, start with empty list
      _cachedBookmarks = [];
    }
  }

  static Future<void> _saveToStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');

      final jsonString = json.encode(
        _cachedBookmarks.map((entry) => entry.toJson()).toList(),
      );
      await file.writeAsString(jsonString);
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