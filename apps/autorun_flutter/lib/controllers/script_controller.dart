import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/script_record.dart';
import '../services/script_repository.dart';

class ScriptController extends ChangeNotifier {
  ScriptController(this._repository);

  final ScriptRepository _repository;
  final List<ScriptRecord> _scripts = <ScriptRecord>[];

  bool _initialized = false;
  bool _isBusy = false;

  List<ScriptRecord> get scripts => List<ScriptRecord>.unmodifiable(_scripts);
  bool get isBusy => _isBusy;

  Future<void> ensureLoaded() async {
    if (_initialized) return;
    await refresh();
    _initialized = true;
  }

  Future<void> refresh() async {
    _setBusy(true);
    try {
      final List<ScriptRecord> records = await _repository.loadScripts();
      _scripts
        ..clear()
        ..addAll(records);
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<ScriptRecord> createScript({
    required String title,
    String? emoji,
    String? imageUrl,
  }) async {
    if (title.trim().isEmpty) {
      throw ArgumentError('title is required');
    }
    // Default to a sensible emoji when none provided.
    String? finalEmoji = (emoji != null && emoji.trim().isNotEmpty) ? emoji.trim() : null;
    String? finalImageUrl = (imageUrl != null && imageUrl.trim().isNotEmpty) ? imageUrl.trim() : null;
    if (finalEmoji == null && finalImageUrl == null) {
      finalEmoji = '📜';
    }
    _setBusy(true);
    try {
      final String id = const Uuid().v4();
      final DateTime now = DateTime.now().toUtc();
      // Default script demonstrates governance + ledger queries via batch
      const String defaultLua =
          'local gov = icp_call({ canister_id = "rrkah-fqaaa-aaaaa-aaaaq-cai", method = "get_pending_proposals", kind = 0, args = "()" })\n'
          'local ledger = icp_call({ canister_id = "ryjl3-tyaaa-aaaaa-aaaba-cai", method = "query_blocks", kind = 0, args = "{\\"start\\":0,\\"length\\":10}" })\n'
          'return icp_batch({ gov, ledger })\n';

      final ScriptRecord record = ScriptRecord(
        id: id,
        title: title.trim(),
        emoji: finalEmoji,
        imageUrl: finalImageUrl,
        luaSource: defaultLua,
        createdAt: now,
        updatedAt: now,
      );
      _scripts.add(record);
      await _repository.persistScripts(_scripts);
      notifyListeners();
      return record;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteScript(String id) async {
    _scripts.removeWhere((ScriptRecord r) => r.id == id);
    await _repository.persistScripts(_scripts);
    notifyListeners();
  }

  Future<void> updateSource({required String id, required String luaSource}) async {
    final int idx = _scripts.indexWhere((ScriptRecord r) => r.id == id);
    if (idx < 0) {
      throw ArgumentError('Script not found: $id');
    }
    final ScriptRecord current = _scripts[idx];
    final ScriptRecord updated = current.copyWith(
      luaSource: luaSource,
      updatedAt: DateTime.now().toUtc(),
    );
    _scripts[idx] = updated;
    await _repository.persistScripts(_scripts);
    notifyListeners();
  }

  Future<void> updateDetails({
    required String id,
    required String title,
    String? emoji,
    String? imageUrl,
  }) async {
    final int idx = _scripts.indexWhere((ScriptRecord r) => r.id == id);
    if (idx < 0) {
      throw ArgumentError('Script not found: $id');
    }
    final String trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('title is required');
    }
    String? finalEmoji = (emoji != null && emoji.trim().isNotEmpty) ? emoji.trim() : null;
    String? finalImageUrl = (imageUrl != null && imageUrl.trim().isNotEmpty) ? imageUrl.trim() : null;
    if (finalEmoji == null && finalImageUrl == null) {
      finalEmoji = '📜';
    }
    final ScriptRecord current = _scripts[idx];
    final ScriptRecord updated = current.copyWith(
      title: trimmedTitle,
      emoji: finalEmoji,
      imageUrl: finalImageUrl,
      updatedAt: DateTime.now().toUtc(),
    );
    _scripts[idx] = updated;
    await _repository.persistScripts(_scripts);
    notifyListeners();
  }

  void _setBusy(bool value) {
    if (_isBusy == value) return;
    _isBusy = value;
    notifyListeners();
  }
}
