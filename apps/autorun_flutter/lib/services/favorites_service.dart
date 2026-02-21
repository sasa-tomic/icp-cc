import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing script favorites with SharedPreferences persistence.
///
/// Provides methods to toggle, check, and retrieve favorite scripts.
/// Emits updates via [favoritesStream] for reactive UI updates.
class FavoritesService {
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  static const String _favoritesKey = 'script_favorites';
  Set<String> _favorites = {};
  final StreamController<Set<String>> _favoritesController =
      StreamController<Set<String>>.broadcast();

  /// Stream of favorites set that emits on every change.
  Stream<Set<String>> get favoritesStream => _favoritesController.stream;

  /// Loads favorites from SharedPreferences.
  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoritesJson = prefs.getString(_favoritesKey);

      if (favoritesJson != null) {
        final List<dynamic> favoritesList = jsonDecode(favoritesJson);
        _favorites = favoritesList.whereType<String>().toSet();
      } else {
        _favorites = {};
      }
    } catch (e) {
      _favorites = {};
    }
  }

  /// Saves favorites to SharedPreferences.
  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoritesJson = jsonEncode(_favorites.toList());
      await prefs.setString(_favoritesKey, favoritesJson);
      _favoritesController.add(Set.unmodifiable(_favorites));
    } catch (e) {
      throw Exception('Failed to save favorites: $e');
    }
  }

  /// Toggles the favorite status of a script.
  ///
  /// Returns `true` if the script is now a favorite, `false` otherwise.
  Future<bool> toggleFavorite(String scriptId) async {
    await _loadFavorites();

    if (_favorites.contains(scriptId)) {
      _favorites.remove(scriptId);
    } else {
      _favorites.add(scriptId);
    }

    await _saveFavorites();
    return _favorites.contains(scriptId);
  }

  /// Returns whether the given script is favorited.
  Future<bool> isFavorite(String scriptId) async {
    await _loadFavorites();
    return _favorites.contains(scriptId);
  }

  /// Returns all favorited script IDs.
  Future<Set<String>> getAllFavorites() async {
    await _loadFavorites();
    return Set.unmodifiable(_favorites);
  }

  /// Clears all favorites.
  Future<void> clearFavorites() async {
    _favorites.clear();
    await _saveFavorites();
  }

  /// Disposes the stream controller.
  void dispose() {
    _favoritesController.close();
  }
}
