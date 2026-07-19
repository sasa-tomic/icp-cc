// ignore_for_file: lines_longer_than_80_chars

/// Substrate fakes for the Web e2e harness (Phase C Tier A).
///
/// These mocks live at the smallest I/O boundary the app talks to, exactly as
/// the human rules permit ("mock at the smallest boundary in e2e tests, e.g.
/// the literal outbound HTTP call"). They do NOT touch app logic, services, or
/// cryptography — the real `MarketplaceOpenApiService`, real
/// `FlutterSecureStorage` Web impl, and real pure-Dart Ed25519/Argon2id/AES
/// are exercised as-is.
///
/// Three Four seams cover the entire boot path of `KeypairApp` on Web:
///
/// 1. **HTTP** ([installSubstrateHttp]): both HTTP-using singletons
///    (`MarketplaceOpenApiService`, `PasskeyService`) expose an
///    `overrideHttpClient(http.Client)` seam. We inject a single
///    [SubstrateMockServer] that routes calls to in-memory handlers keyed by
///    `(METHOD, path-pattern)`. Used for marketplace browse + account flows.
/// 2. **SharedPreferences** ([installSubstratePrefs]): SDK-blessed
///    `SharedPreferences.setMockInitialValues`. Covers both direct prefs reads
///    (settings, onboarding gate, dev-options) and the WebJsonStore backing
///    `ProfileRepository`/`ScriptRepository` on Web (which reads/writes
///    SharedPreferences keys with the `icp_cc_store_` prefix).
/// 3. **Secure storage** ([installSubstrateSecureStorage]): SDK-blessed
///    `FlutterSecureStorage.setMockInitialValues`. The Web impl is round-trip
///    in-memory under the mock — keys + profiles persist for the suite's
///    lifetime.
/// 4. **path_provider** ([installSubstratePathProvider]): under
///    `flutter test -d chrome` the test code compiles for the Dart VM, so
///    `dart.library.html` is FALSE — the conditional export in
///    `lib/services/json_store.dart` selects `file_json_store.dart`, whose
///    `FileJsonStore` calls `getApplicationSupportDirectory()` via
///    `path_provider`. `flutter_cache_manager` (image caching) hits the same
///    plugin. `FileJsonStore` already has a fallback temp dir, but the
///    unhandled `MissingPluginException` propagates as a test failure, so we
///    install a fake `PathProviderPlatform` that returns a real temp dir.
///
/// Each installer is idempotent (safe to call from `setUpAll`); the substrate
/// is a process-wide singleton by design.
library;

export 'substrate_app_links.dart';
export 'substrate_http.dart';
export 'substrate_path_provider.dart';
export 'substrate_prefs.dart';
export 'substrate_secure_storage.dart';
