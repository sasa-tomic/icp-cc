import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum CallType {
  query,
  update,
  compositeQuery;

  String toJsonString() {
    switch (this) {
      case CallType.query:
        return 'query';
      case CallType.update:
        return 'update';
      case CallType.compositeQuery:
        return 'composite_query';
    }
  }

  static CallType fromJsonString(String value) {
    switch (value) {
      case 'update':
        return CallType.update;
      case 'composite_query':
        return CallType.compositeQuery;
      default:
        return CallType.query;
    }
  }
}

class CanisterCallRecord {
  final String canisterId;
  final String methodName;
  final String arguments;
  final DateTime timestamp;
  final CallType callType;
  final String resultSummary;

  const CanisterCallRecord({
    required this.canisterId,
    required this.methodName,
    required this.arguments,
    required this.timestamp,
    required this.callType,
    required this.resultSummary,
  });

  Map<String, dynamic> toJson() => {
        'canisterId': canisterId,
        'methodName': methodName,
        'arguments': arguments,
        'timestamp': timestamp.toIso8601String(),
        'callType': callType.toJsonString(),
        'resultSummary': resultSummary,
      };

  factory CanisterCallRecord.fromJson(Map<String, dynamic> json) =>
      CanisterCallRecord(
        canisterId: json['canisterId'] as String,
        methodName: json['methodName'] as String,
        arguments: json['arguments'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        callType: CallType.fromJsonString(json['callType'] as String),
        resultSummary: json['resultSummary'] as String,
      );
}

class CanisterHistoryService {
  static final CanisterHistoryService _instance =
      CanisterHistoryService._internal();
  factory CanisterHistoryService() => _instance;
  CanisterHistoryService._internal();

  static const String _historyKey = 'canister_call_history';
  static const int _maxHistoryItems = 50;
  List<CanisterCallRecord> _history = [];

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_historyKey);

      if (historyJson != null) {
        final List<dynamic> historyList = jsonDecode(historyJson);
        _history = historyList
            .map((item) =>
                CanisterCallRecord.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _history = [];
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson =
          jsonEncode(_history.map((record) => record.toJson()).toList());
      await prefs.setString(_historyKey, historyJson);
    } catch (_) {}
  }

  Future<void> addCall({
    required String canisterId,
    required String methodName,
    required String arguments,
    required CallType callType,
    required String resultSummary,
  }) async {
    await _loadHistory();

    final record = CanisterCallRecord(
      canisterId: canisterId,
      methodName: methodName,
      arguments: arguments,
      timestamp: DateTime.now(),
      callType: callType,
      resultSummary: resultSummary,
    );

    _history.insert(0, record);

    if (_history.length > _maxHistoryItems) {
      _history = _history.take(_maxHistoryItems).toList();
    }

    await _saveHistory();
  }

  Future<List<CanisterCallRecord>> getHistory() async {
    await _loadHistory();
    return List.unmodifiable(_history);
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
  }

  Future<int> getCount() async {
    await _loadHistory();
    return _history.length;
  }
}
