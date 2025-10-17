import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/script_record.dart';
import '../services/script_repository.dart';

// Default sample TEA-style Lua app demonstrating UI, buttons, and canister calls.
// Shows a counter and allows loading sample governance/ledger data via a batch effect.
const String kDefaultSampleLua = r'''
function init(arg)
  return {
    count = 0,
    items = json.decode('[]'),
    last = nil
  }, {}
end

function view(state)
  local children = {
    { type = "section", props = { title = "Sample UI-enabled Script" }, children = {
      { type = "text", props = { text = "Counter: "..tostring(state.count or 0) } },
      { type = "row", children = {
        { type = "button", props = { label = "Increment", on_press = { type = "inc" } } },
        { type = "button", props = { label = "Load ICP samples", on_press = { type = "load_sample" } } }
      } }
    } }
  }
  local items = state.items or {}
  if type(items) == 'table' and #items > 0 then
    table.insert(children, { type = "section", props = { title = "Loaded results" }, children = {
      { type = "list", props = { items = items } }
    } })
  end
  return { type = "column", children = children }
end

function update(msg, state)
  local t = (msg and msg.type) or ""
  if t == "inc" then
    state.count = (state.count or 0) + 1
    return state, {}
  end
  if t == "load_sample" then
    -- Trigger a batch of canister calls; host will request permission
    local gov = { label = "gov", kind = 0, canister_id = "rrkah-fqaaa-aaaaa-aaaaq-cai", method = "get_pending_proposals", args = "()" }
    local ledger = { label = "ledger", kind = 0, canister_id = "ryjl3-tyaaa-aaaaa-aaaba-cai", method = "query_blocks", args = "{\"start\":0,\"length\":3}" }
    return state, { { kind = "icp_batch", id = "load", items = { gov, ledger } } }
  end
  if t == "effect/result" and msg.id == "load" then
    -- Normalize results into a list for display
    local items = {}
    if msg.ok then
      for k, v in pairs(msg.data or {}) do
        table.insert(items, { title = tostring(k), subtitle = type(v) == 'table' and json.encode(v) or tostring(v) })
      end
    else
      table.insert(items, { title = "Error", subtitle = tostring(msg.error or "unknown error") })
    end
    state.items = items
    return state, {}
  end
  state.last = msg
  return state, {}
end
''';

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
    String? luaSourceOverride,
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
      final String defaultLua = luaSourceOverride == null || luaSourceOverride.trim().isEmpty
          ? kDefaultSampleLua
          : luaSourceOverride;

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
