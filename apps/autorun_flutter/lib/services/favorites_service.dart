import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class FavoriteEntry {
  FavoriteEntry({
    required this.canisterId,
    required this.method,
    this.label,
  });

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) {
    return FavoriteEntry(
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
    return other is FavoriteEntry &&
        other.canisterId == canisterId &&
        other.method == method;
  }

  @override
  int get hashCode => canisterId.hashCode ^ method.hashCode;
}

class FavoritesService {
  static const String _fileName = 'icp_favorites.json';
  static List<FavoriteEntry> _cachedFavorites = [];
  static bool _isCacheDirty = true;

  static Future<List<FavoriteEntry>> list() async {
    if (_isCacheDirty) {
      await _loadFromStorage();
      _isCacheDirty = false;
    }
    return List.unmodifiable(_cachedFavorites);
  }

  static Future<void> add({
    required String canisterId,
    required String method,
    String? label,
  }) async {
    final newEntry = FavoriteEntry(
      canisterId: canisterId,
      method: method,
      label: label,
    );

    // Remove existing entry with same canisterId and method
    _cachedFavorites.removeWhere((entry) =>
        entry.canisterId == canisterId && entry.method == method);

    // Add new entry
    _cachedFavorites.add(newEntry);

    await _saveToStorage();
    FavoritesEvents.notifyChanged();
  }

  static Future<void> remove({
    required String canisterId,
    required String method,
  }) async {
    _cachedFavorites.removeWhere((entry) =>
        entry.canisterId == canisterId && entry.method == method);

    await _saveToStorage();
    FavoritesEvents.notifyChanged();
  }

  static Future<void> _loadFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');

      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.isNotEmpty) {
          final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
          _cachedFavorites = jsonList
              .whereType<Map<String, dynamic>>()
              .map((json) => FavoriteEntry.fromJson(json))
              .toList();
          return;
        }
      }
      _cachedFavorites = [];
    } catch (e) {
      // If loading fails, start with empty list
      _cachedFavorites = [];
    }
  }

  static Future<void> _saveToStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');

      final jsonString = json.encode(
        _cachedFavorites.map((entry) => entry.toJson()).toList(),
      );
      await file.writeAsString(jsonString);
    } catch (e) {
      // Fail-fast: rethrow the error to make it visible
      throw Exception('Failed to save favorites: $e');
    }
  }

  static void invalidateCache() {
    _isCacheDirty = true;
  }
}

class FavoritesEvents {
  static final _notifier = ValueNotifier<int>(0);

  static ValueNotifier<int> get listenable => _notifier;

  static void notifyChanged() {
    _notifier.value++;
  }
}