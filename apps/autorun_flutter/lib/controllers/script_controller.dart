import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/script_record.dart';
import '../services/script_repository.dart';

// Default sample TEA-style Lua app demonstrating UI widgets, forms, and canister calls.
// Shows various UI elements and allows loading sample governance/ledger data via a batch effect.
const String kDefaultSampleLua = r'''
function init(arg)
  return {
    count = 0,
    items = json.decode('[]'),
    last = nil,
    name = "",
    email = "",
    enabled = true,
    role = "user",
    showImage = false
  }, {}
end

function view(state)
  local children = {
    { type = "section", props = { title = "UI Widgets Demo" }, children = {
      { type = "text", props = { text = "Counter: "..tostring(state.count or 0) } },
      { type = "text_field", props = {
        label = "Name",
        placeholder = "Enter your name",
        value = state.name or "",
        on_change = { type = "set_name" }
      }},
      { type = "text_field", props = {
        label = "Email",
        placeholder = "Enter your email",
        value = state.email or "",
        keyboard_type = "email",
        on_change = { type = "set_email" }
      }},
      { type = "toggle", props = {
        label = "Enable features",
        value = state.enabled == true,
        on_change = { type = "set_enabled" }
      }},
      { type = "select", props = {
        label = "Role",
        value = state.role or "user",
        options = {
          { value = "user", label = "User" },
          { value = "admin", label = "Administrator" },
          { value = "moderator", label = "Moderator" }
        },
        on_change = { type = "set_role" }
      }},
      { type = "toggle", props = {
        label = "Show image",
        value = state.showImage == true,
        on_change = { type = "toggle_image" }
      }},
      { type = "row", children = {
        { type = "button", props = { label = "Increment", on_press = { type = "inc" } } },
        { type = "button", props = { label = "Load ICP samples", on_press = { type = "load_sample" } } }
      } }
    } }
  }

  -- Show image if enabled
  if state.showImage then
    table.insert(children, { type = "section", props = { title = "Image Demo" }, children = {
      { type = "image", props = {
        src = "https://picsum.photos/seed/icp-demo/300/200.jpg",
        width = 300,
        height = 200,
        fit = "cover"
      }}
    } })
  end

  -- Show current form values
  table.insert(children, { type = "section", props = { title = "Current Values" }, children = {
    { type = "list", props = {
      items = {
        { title = "Name", subtitle = state.name or "(empty)" },
        { title = "Email", subtitle = state.email or "(empty)" },
        { title = "Enabled", subtitle = tostring(state.enabled) },
        { title = "Role", subtitle = state.role or "user" },
        { title = "Show Image", subtitle = tostring(state.showImage) }
      }
    }}
  } })

  -- Show loaded results if any
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

  -- Handle UI widget events
  if t == "set_name" then
    state.name = msg.value or ""
    return state, {}
  end
  if t == "set_email" then
    state.email = msg.value or ""
    return state, {}
  end
  if t == "set_enabled" then
    state.enabled = msg.value == true
    return state, {}
  end
  if t == "set_role" then
    state.role = msg.value or "user"
    return state, {}
  end
  if t == "toggle_image" then
    state.showImage = msg.value == true
    return state, {}
  end

  -- Handle existing functionality
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
