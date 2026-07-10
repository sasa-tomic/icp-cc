import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

class DownloadRecord {
  final String marketplaceScriptId;
  final String title;
  final String authorName;
  final String? version;
  final DateTime downloadedAt;
  final String localScriptId;

  DownloadRecord({
    required this.marketplaceScriptId,
    required this.title,
    required this.authorName,
    this.version,
    required this.downloadedAt,
    required this.localScriptId,
  });

  Map<String, dynamic> toJson() => {
    'marketplaceScriptId': marketplaceScriptId,
    'title': title,
    'authorName': authorName,
    'version': version,
    'downloadedAt': downloadedAt.toIso8601String(),
    'localScriptId': localScriptId,
  };

  factory DownloadRecord.fromJson(Map<String, dynamic> json) => DownloadRecord(
    marketplaceScriptId: json['marketplaceScriptId'] as String,
    title: json['title'] as String,
    authorName: json['authorName'] as String,
    version: json['version'] as String?,
    downloadedAt: DateTime.parse(json['downloadedAt'] as String),
    localScriptId: json['localScriptId'] as String,
  );
}

class DownloadHistoryService {
  static final DownloadHistoryService _instance = DownloadHistoryService._internal();
  factory DownloadHistoryService() => _instance;
  DownloadHistoryService._internal();

  static const String _downloadHistoryKey = 'download_history';
  List<DownloadRecord> _downloadHistory = [];

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_downloadHistoryKey);

    // No stored key yet (first run / cleared history) is the ONLY legitimate
    // "empty" case — it is not an error.
    if (historyJson == null) {
      _downloadHistory = [];
      return;
    }

    try {
      final List<dynamic> historyList = jsonDecode(historyJson);
      _downloadHistory = historyList
          .map((item) => DownloadRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    } on FormatException catch (e) {
      // Stored history is unparseable JSON (e.g. a truncated/partial write).
      // Discard it but surface the loss loudly (AGENTS.md: no silent failures)
      // instead of swallowing every possible error as "empty". Unexpected
      // errors — a structural/type mismatch in a stored record — propagate to
      // the caller rather than being masked.
      debugPrint('DownloadHistoryService: discarding unparseable history: $e');
      _downloadHistory = [];
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = jsonEncode(
        _downloadHistory.map((record) => record.toJson()).toList(),
      );
      await prefs.setString(_downloadHistoryKey, historyJson);
    } catch (e, st) {
      // A swallowed write error would silently drop the user's download
      // history on the next load. Fail loudly instead: log the body +
      // context, then rethrow so callers (addToHistory/removeFromHistory/
      // clearHistory) can surface a SnackBar. See AGENTS.md: no silent
      // failures; matches BookmarksService._saveToStorage (QS-10).
      debugPrint(
        'DownloadHistoryService: failed to persist download history '
        '(${_downloadHistory.length} records): $e\n$st',
      );
      throw Exception('Failed to save download history: $e');
    }
  }

  Future<void> addToHistory({
    required String marketplaceScriptId,
    required String title,
    required String authorName,
    String? version,
    required String localScriptId,
  }) async {
    await _loadHistory();

    // Remove any existing record for this marketplace script
    _downloadHistory.removeWhere(
      (record) => record.marketplaceScriptId == marketplaceScriptId,
    );

    // Add new record
    final record = DownloadRecord(
      marketplaceScriptId: marketplaceScriptId,
      title: title,
      authorName: authorName,
      version: version,
      downloadedAt: DateTime.now(),
      localScriptId: localScriptId,
    );

    _downloadHistory.insert(0, record); // Insert at beginning (most recent first)
    
    // Keep only the most recent 100 downloads
    if (_downloadHistory.length > 100) {
      _downloadHistory = _downloadHistory.take(100).toList();
    }

    await _saveHistory();
  }

  Future<List<DownloadRecord>> getDownloadHistory() async {
    await _loadHistory();
    return List.unmodifiable(_downloadHistory);
  }

  Future<DownloadRecord?> getDownloadRecord(String marketplaceScriptId) async {
    await _loadHistory();
    try {
      return _downloadHistory.firstWhere(
        (record) => record.marketplaceScriptId == marketplaceScriptId,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> removeFromHistory(String marketplaceScriptId) async {
    await _loadHistory();
    _downloadHistory.removeWhere(
      (record) => record.marketplaceScriptId == marketplaceScriptId,
    );
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    _downloadHistory.clear();
    await _saveHistory();
  }

  Future<bool> isDownloaded(String marketplaceScriptId) async {
    await _loadHistory();
    return _downloadHistory.any(
      (record) => record.marketplaceScriptId == marketplaceScriptId,
    );
  }

  Future<int> getDownloadCount() async {
    await _loadHistory();
    return _downloadHistory.length;
  }
}