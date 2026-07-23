/// Pure-Dart facade for the app's local JSON document store (WU-1).
///
/// Stores NON-SENSITIVE structured state (profile metadata + public-key data,
/// local/owned script bundles) behind one tiny async contract. Two thin impls
/// are selected via a **conditional export** — exactly mirroring the established
/// `lib/rust/native_bridge.dart` split:
///
///   export 'file_json_store.dart' if (dart.library.html) 'web_json_store.dart';
///
/// - **IO** (`file_json_store.dart`): one `<key>.json` file per key, written via
///   the existing `file_io.dart` helpers (which already apply
///   `AppDurations.ioOperation` timeouts). Selected on every non-Web target.
/// - **Web** (`web_json_store.dart`): `package:shared_preferences` (backed by
///   `localStorage` via `shared_preferences_web`), keys prefixed `icp_cc_store_`.
///   Selected when `dart.library.html` is available.
///
/// ## Sensitive data is NOT stored here
/// Private keys, mnemonics, and vault blobs stay in `flutter_secure_storage`
/// (already Web-capable via IndexedDB + AES). This store holds only public
/// metadata that is meaningless without those secrets — moving it here does not
/// weaken the zero-knowledge model. Never use [JsonDocumentStore] for secrets.
///
/// ## Idempotence
/// [write] overwrites any existing value; [delete] is a no-op when the key is
/// absent. Both impls honour this so callers need not special-case the platform.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

// Conditional export: IO file store on every non-Web target, localStorage-backed
// Web store in the browser. `openJsonDocumentStore()` and the concrete store
// class come from whichever file is selected here. This file itself imports NO
// `dart:io`, so the facade compiles cleanly on every target.
export 'file_json_store.dart' if (dart.library.html) 'web_json_store.dart';

/// A tiny async key/value store for non-sensitive JSON documents.
///
/// Implementations MUST be idempotent for [write] and [delete] (see above) and
/// MUST surface errors loudly (never return a silent default on failure).
abstract class JsonDocumentStore {
  /// Returns the stored JSON string for [key], or `null` if the key is absent
  /// or holds only whitespace.
  Future<String?> read(String key);

  /// Stores [json] under [key], overwriting any previous value.
  Future<void> write(String key, String json);

  /// Removes [key]; a no-op (not an error) if [key] is absent.
  Future<void> delete(String key);
}

/// Test-only: when non-null, `openJsonDocumentStore()` returns this instead of
/// the platform default ([FileJsonStore] / [WebJsonStore]). Widget and fast e2e
/// tests set this to an in-memory store to avoid real file I/O hanging under
/// the Flutter test binding's fake clock. MUST be set back to `null` in tearDown.
@visibleForTesting
JsonDocumentStore? testJsonStoreOverride;
