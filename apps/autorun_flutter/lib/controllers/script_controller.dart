import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/script_record.dart';
import '../services/script_repository.dart';

// Default sample TS app demonstrating UI widgets, forms, and canister calls.
// Self-contained IIFE bundle (the host runs QuickJS). Shows a counter, a
// name/email form, toggles, a select, an image, and a load_sample batch effect
// against the NNS governance + ICP ledger canisters.
const String kDefaultSampleBundle = r'''"use strict";
(() => {
  function init() {
    return {
      state: {
        count: 0,
        items: [],
        last: null,
        name: "",
        email: "",
        enabled: true,
        role: "user",
        showImage: false
      },
      effects: []
    };
  }

  function view(state) {
    var children = [];

    children.push({
      type: "section",
      props: { title: "UI Widgets Demo" },
      children: [
        { type: "text", props: { text: "Counter: " + (state.count || 0) } },
        { type: "text_field", props: {
          label: "Name", placeholder: "Enter your name",
          value: state.name || "", on_change: { type: "set_name" }
        }},
        { type: "text_field", props: {
          label: "Email", placeholder: "Enter your email",
          value: state.email || "", keyboard_type: "email",
          on_change: { type: "set_email" }
        }},
        { type: "toggle", props: {
          label: "Enable features",
          value: state.enabled === true,
          on_change: { type: "set_enabled" }
        }},
        { type: "select", props: {
          label: "Role", value: state.role || "user",
          options: [
            { value: "user", label: "User" },
            { value: "admin", label: "Administrator" },
            { value: "moderator", label: "Moderator" }
          ],
          on_change: { type: "set_role" }
        }},
        { type: "toggle", props: {
          label: "Show image",
          value: state.showImage === true,
          on_change: { type: "toggle_image" }
        }},
        { type: "row", children: [
          { type: "button", props: { label: "Increment", on_press: { type: "inc" } } },
          { type: "button", props: { label: "Load ICP samples", on_press: { type: "load_sample" } } }
        ]}
      ]
    });

    if (state.showImage) {
      children.push({
        type: "section",
        props: { title: "Image Demo" },
        children: [{
          type: "image",
          props: {
            src: "https://picsum.photos/seed/icp-demo/300/200.jpg",
            width: 300, height: 200, fit: "cover"
          }
        }]
      });
    }

    children.push({
      type: "section",
      props: { title: "Current Values" },
      children: [{
        type: "list",
        props: {
          items: [
            { title: "Name", subtitle: state.name || "(empty)" },
            { title: "Email", subtitle: state.email || "(empty)" },
            { title: "Enabled", subtitle: String(state.enabled) },
            { title: "Role", subtitle: state.role || "user" },
            { title: "Show Image", subtitle: String(state.showImage) }
          ]
        }
      }]
    });

    var items = state.items || [];
    if (Array.isArray(items) && items.length > 0) {
      children.push({
        type: "section",
        props: { title: "Loaded results" },
        children: [{ type: "list", props: { items: items } }]
      });
    }

    return { type: "column", children: children };
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";

    if (t === "set_name") {
      return { state: { ...state, name: typeof msg.value === "string" ? msg.value : "" }, effects: [] };
    }
    if (t === "set_email") {
      return { state: { ...state, email: typeof msg.value === "string" ? msg.value : "" }, effects: [] };
    }
    if (t === "set_enabled") {
      return { state: { ...state, enabled: msg.value === true }, effects: [] };
    }
    if (t === "set_role") {
      return { state: { ...state, role: typeof msg.value === "string" ? msg.value : "user" }, effects: [] };
    }
    if (t === "toggle_image") {
      return { state: { ...state, showImage: msg.value === true }, effects: [] };
    }
    if (t === "inc") {
      return { state: { ...state, count: (state.count || 0) + 1 }, effects: [] };
    }
    if (t === "load_sample") {
      var gov = {
        label: "gov", kind: 0,
        canister_id: "rrkah-fqaaa-aaaaa-aaaaq-cai",
        method: "get_pending_proposals", args: "()"
      };
      var ledger = {
        label: "ledger", kind: 0,
        canister_id: "ryjl3-tyaaa-aaaaa-aaaba-cai",
        method: "query_blocks", args: '{"start":0,"length":3}'
      };
      return { state: state, effects: [{ kind: "icp_batch", id: "load", items: [gov, ledger] }] };
    }
    if (t === "effect/result" && msg.id === "load") {
      var items = [];
      if (msg.ok) {
        var data = msg.data || {};
        for (var key in data) {
          if (!Object.prototype.hasOwnProperty.call(data, key)) continue;
          var v = data[key];
          var subtitle = (typeof v === "object" && v !== null) ? JSON.stringify(v) : String(v);
          items.push({ title: String(key), subtitle: subtitle });
        }
      } else {
        items.push({ title: "Error", subtitle: String(msg.error || "unknown error") });
      }
      return { state: { ...state, items: items }, effects: [] };
    }

    return { state: { ...state, last: msg }, effects: [] };
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
''';

class ScriptController extends ChangeNotifier {
  ScriptController(this._repository) {
    // Listen to repository changes from other controller instances
    _repositorySubscription = _repository.scriptsStream.listen((scripts) {
      // Only update if this is an external change (not from this controller)
      if (_scripts.length != scripts.length ||
          !_areScriptListsEqual(_scripts, scripts)) {
        _scripts
          ..clear()
          ..addAll(scripts);
        notifyListeners();
      }
    });
  }

  final ScriptRepository _repository;
  final List<ScriptRecord> _scripts = <ScriptRecord>[];
  StreamSubscription<List<ScriptRecord>>? _repositorySubscription;

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
    String? bundleOverride,
    Map<String, dynamic>? metadata,
  }) async {
    if (title.trim().isEmpty) {
      throw ArgumentError('title is required');
    }
    // Default to a sensible emoji when none provided.
    String? finalEmoji =
        (emoji != null && emoji.trim().isNotEmpty) ? emoji.trim() : null;
    String? finalImageUrl = (imageUrl != null && imageUrl.trim().isNotEmpty)
        ? imageUrl.trim()
        : null;
    if (finalEmoji == null && finalImageUrl == null) {
      finalEmoji = '📜';
    }
    _setBusy(true);
    try {
      final String id = const Uuid().v4();
      final DateTime now = DateTime.now().toUtc();
      final String defaultBundle =
          bundleOverride == null || bundleOverride.trim().isEmpty
              ? kDefaultSampleBundle
              : bundleOverride;

      final ScriptRecord record = ScriptRecord(
        id: id,
        title: title.trim(),
        emoji: finalEmoji,
        imageUrl: finalImageUrl,
        bundle: defaultBundle,
        createdAt: now,
        updatedAt: now,
        metadata: metadata ?? {},
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

  Future<void> updateSource(
      {required String id, required String bundle}) async {
    final int idx = _scripts.indexWhere((ScriptRecord r) => r.id == id);
    if (idx < 0) {
      throw ArgumentError('Script not found: $id');
    }
    final ScriptRecord current = _scripts[idx];
    final Map<String, dynamic> updatedMetadata =
        Map<String, dynamic>.from(current.metadata);
    updatedMetadata.remove('sha256_checksum');
    final ScriptRecord updated = current.copyWith(
      bundle: bundle,
      updatedAt: DateTime.now().toUtc(),
      metadata: updatedMetadata,
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
    String? finalEmoji =
        (emoji != null && emoji.trim().isNotEmpty) ? emoji.trim() : null;
    String? finalImageUrl = (imageUrl != null && imageUrl.trim().isNotEmpty)
        ? imageUrl.trim()
        : null;
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

  Future<void> recordScriptRun(String id) async {
    final int idx = _scripts.indexWhere((ScriptRecord r) => r.id == id);
    if (idx < 0) {
      throw ArgumentError('Script not found: $id');
    }
    final ScriptRecord updated = _scripts[idx].recordRun();
    _scripts[idx] = updated;
    await _repository.persistScripts(_scripts);
    notifyListeners();
  }

  void _setBusy(bool value) {
    if (_isBusy == value) return;
    _isBusy = value;
    notifyListeners();
  }

  bool _areScriptListsEqual(
      List<ScriptRecord> list1, List<ScriptRecord> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id ||
          list1[i].updatedAt != list2[i].updatedAt) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _repositorySubscription?.cancel();
    super.dispose();
  }
}
