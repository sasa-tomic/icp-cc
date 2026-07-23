// ignore_for_file: lines_longer_than_80_chars

/// In-memory [JsonDocumentStore] for the fast e2e harness.
///
/// On the Dart VM (non-Web), [FileJsonStore] does real `dart:io` file I/O which
/// hangs under the Flutter test binding's fake clock. This pure-Dart store
/// completes synchronously (wrapped in a microtask) so it never blocks the
/// pump cycle.
library;

import 'package:icp_autorun/services/json_store.dart';

/// A simple `Map<String, String>` backed [JsonDocumentStore].
///
/// Honour the same whitespace ⇔ absent contract as [FileJsonStore] /
/// [WebJsonStore].
class SubstrateJsonStore implements JsonDocumentStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async {
    final value = _data[key];
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Future<void> write(String key, String json) async {
    _data[key] = json;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  /// Clears all data (for test reset between flows).
  void reset() {
    _data.clear();
  }
}

/// Installs (or replaces) the global in-memory [JsonDocumentStore] override.
///
/// Call this in `setUp` / `resetState` of the fast harness. Set
/// `testJsonStoreOverride = null` in `tearDown` to restore the platform default.
SubstrateJsonStore installSubstrateJsonStore() {
  final store = SubstrateJsonStore();
  testJsonStoreOverride = store;
  return store;
}
