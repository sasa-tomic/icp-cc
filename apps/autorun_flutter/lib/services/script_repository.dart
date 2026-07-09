import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory;

import 'package:flutter/foundation.dart';

import '../models/script_record.dart';
import 'json_store.dart';

class ScriptRepository {
  // Singleton pattern
  static ScriptRepository? _instance;
  static ScriptRepository get instance {
    _instance ??= ScriptRepository.internal();
    return _instance!;
  }

  factory ScriptRepository({Directory? overrideDirectory}) {
    if (overrideDirectory != null) {
      // For testing: create a new instance with override directory
      return ScriptRepository.internal(overrideDirectory: overrideDirectory);
    }
    return instance;
  }

  ScriptRepository.internal({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory;

  /// The IO test-injection directory (see [openJsonDocumentStore]). On Web this
  /// is always `null` — no caller can supply a `Directory` in the browser.
  final Directory? _overrideDirectory;

  JsonDocumentStore? _store;

  /// Lazily resolves the JSON document store for this repository. The store is
  /// built once from [_overrideDirectory] (test injection) or the
  /// platform-default location, then cached.
  JsonDocumentStore get _docStore =>
      _store ??= openJsonDocumentStore(overrideDirectory: _overrideDirectory);

  /// Single source for this repository's JSON-store key name.
  static const String _storeKey = 'scripts';

  /// The empty-store payload written after a corruption reset. Schema-identical
  /// to the original `scripts.json`.
  static String _encodeEmptyStore() => jsonEncode(
        <String, dynamic>{
          'version': 1,
          'scripts': <Map<String, dynamic>>[],
        },
      );

  // Broadcast stream for script changes
  final StreamController<List<ScriptRecord>> _scriptsController =
      StreamController<List<ScriptRecord>>.broadcast();

  Stream<List<ScriptRecord>> get scriptsStream => _scriptsController.stream;

  Future<List<ScriptRecord>> loadScripts() async {
    final String? content = await _docStore.read(_storeKey);
    // Absent or whitespace-only key → fresh store → no scripts (no error).
    if (content == null) return <ScriptRecord>[];
    try {
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid scripts store format.');
      }
      final List<dynamic> arr =
          decoded['scripts'] as List<dynamic>? ?? <dynamic>[];
      return arr
          .map((dynamic item) =>
              ScriptRecord.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on FormatException {
      // Parsing failed: back up the corrupt payload (portably — into a sibling
      // store key, so this works on IO AND Web), reset to a safe empty state,
      // and surface the incident loudly. Never silently drop user data.
      debugPrint('ScriptRepository: corrupt `$_storeKey` store detected; '
          'backing up to `${_storeKey}_bak` and resetting.');
      await _docStore.write('${_storeKey}_bak', content);
      await _docStore.write(_storeKey, _encodeEmptyStore());
      return <ScriptRecord>[];
    }
  }

  Future<void> persistScripts(List<ScriptRecord> scripts) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'version': 1,
      'scripts': scripts.map((ScriptRecord s) => s.toJson()).toList(),
    };
    await _docStore.write(_storeKey, jsonEncode(payload));

    // Notify all listeners about the change
    _scriptsController.add(List<ScriptRecord>.unmodifiable(scripts));
  }

  void dispose() {
    _scriptsController.close();
  }
}
