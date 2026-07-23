/// Web implementation of [JsonDocumentStore] (WU-1).
///
/// Selected by [json_store.dart]'s conditional export when compiling for the
/// browser (`dart.library.html`). Backed by `package:shared_preferences`, whose
/// Web implementation (`shared_preferences_web`) stores values in `localStorage`
/// (synchronous, in-memory-cached after the first async load). This is the right
/// home for the NON-SENSITIVE metadata this store holds: profile labels + public
/// keys, and local/owned script bundles. **Secrets never live here** — private
/// keys, mnemonics, and vault blobs stay in `flutter_secure_storage` (IndexedDB
/// + AES on Web), unchanged by WU-1.
///
/// Keys are prefixed with [_prefix] so this store never collides with other
/// `shared_preferences` users in the same origin.
///
/// This file is **pure Dart** (no `dart:io`, no `dart:html`): it imports only
/// `shared_preferences` and the pure facade, mirroring the philosophy of
/// `lib/rust/native_bridge_web.dart`.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_design_system.dart';
import 'json_store.dart';

/// Single source for the localStorage key prefix. Co-located with the only
/// implementation that uses it. (Store-KEY names like `'profiles'`/`'scripts'`
/// live with their respective repositories.)
const String _prefix = 'icp_cc_store_';

/// `JsonDocumentStore` backed by `shared_preferences` (→ `localStorage` on Web).
class WebJsonStore implements JsonDocumentStore {
  /// Loads the shared preferences instance. `SharedPreferences.getInstance` does
  /// a one-time async read of `localStorage` on first call and then serves from
  /// an in-memory cache, so subsequent resolves are cheap. Bounded by the same
  /// I/O timeout the file store uses, per the "all I/O has a timeout" rule.
  Future<SharedPreferences> _prefs() =>
      SharedPreferences.getInstance().timeout(AppDurations.ioOperation);

  @override
  Future<String?> read(String key) async {
    final SharedPreferences prefs = await _prefs();
    final String? value = prefs.getString('$_prefix$key');
    // Honour the JsonDocumentStore contract: whitespace-only ⇔ absent, so
    // callers get a uniform `null` ⇔ "no data" on every platform. The file
    // impl already normalizes this; without it here, a corrupt/empty web value
    // would be handed back raw and parsed as garbage downstream.
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Future<void> write(String key, String json) async {
    final SharedPreferences prefs = await _prefs();
    await prefs
        .setString('$_prefix$key', json)
        .timeout(AppDurations.ioOperation);
  }

  @override
  Future<void> delete(String key) async {
    final SharedPreferences prefs = await _prefs();
    await prefs.remove('$_prefix$key').timeout(AppDurations.ioOperation);
    // Idempotent: removing an absent key is a no-op.
  }
}

/// Platform-default store constructor, Web counterpart to the one in
/// `file_json_store.dart`. Returns a [WebJsonStore]. [overrideDirectory] is
/// accepted solely so call sites can be platform-agnostic; the browser has no
/// filesystem, so it MUST be null and is ignored. Typed as `Object?` (rather
/// than `dart:io`'s `Directory?`) so this file need not import `dart:io`.
JsonDocumentStore openJsonDocumentStore({Object? overrideDirectory}) {
  // ignore: invalid_use_of_visible_for_testing_member
  if (testJsonStoreOverride != null) {
    // ignore: invalid_use_of_visible_for_testing_member
    return testJsonStoreOverride!;
  }
  assert(
    overrideDirectory == null,
    'overrideDirectory is not supported on Web (no filesystem).',
  );
  return WebJsonStore();
}
