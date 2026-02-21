import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryService {
  static final SearchHistoryService _instance =
      SearchHistoryService._internal();
  factory SearchHistoryService() => _instance;
  SearchHistoryService._internal();

  static const String _searchHistoryKey = 'search_history';
  static const int _maxHistoryItems = 10;
  List<String> _searchHistory = [];

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_searchHistoryKey);

      if (historyJson != null) {
        final List<dynamic> historyList = jsonDecode(historyJson);
        _searchHistory = historyList.cast<String>();
      }
    } catch (_) {
      _searchHistory = [];
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = jsonEncode(_searchHistory);
      await prefs.setString(_searchHistoryKey, historyJson);
    } catch (_) {}
  }

  Future<void> addSearchQuery(String query) async {
    await _loadHistory();

    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return;

    final normalizedQuery = trimmedQuery.toLowerCase();
    _searchHistory.removeWhere(
      (item) => item.toLowerCase() == normalizedQuery,
    );

    _searchHistory.insert(0, trimmedQuery);

    if (_searchHistory.length > _maxHistoryItems) {
      _searchHistory = _searchHistory.take(_maxHistoryItems).toList();
    }

    await _saveHistory();
  }

  Future<List<String>> getRecentSearches() async {
    await _loadHistory();
    return List.unmodifiable(_searchHistory);
  }

  Future<void> removeSearchQuery(String query) async {
    await _loadHistory();
    _searchHistory.remove(query);
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    _searchHistory.clear();
    await _saveHistory();
  }

  Future<int> getSearchCount() async {
    await _loadHistory();
    return _searchHistory.length;
  }
}
