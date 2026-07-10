/// Public facade for the Rust-core FFI bridge (R-1 — conditional-import split).
///
/// On IO platforms this re-exports the real FFI implementation
/// ([native_bridge_io.dart]); on Web the honest stub
/// ([native_bridge_web.dart]). This file itself imports NO `dart:ffi`, so the
/// package compiles cleanly under `flutter build web`.
///
/// Shared pure-Dart types live here and are imported by both implementations.
library;

export 'native_bridge_io.dart' if (dart.library.html) 'native_bridge_web.dart';

// R-3b WU-5 — IC-agent-on-Web readiness types (pure-Dart, VM-compilable).
// Re-exported here so consumers (ScriptAppHost, ScriptRunner) get the probe +
// its result type from the single facade import — exactly like QuickJsReadiness
// above. The types themselves live in `ic_agent_types.dart` because they are
// shared between the Web engine (`ic_agent_engine.dart`, browser-only) and the
// VM stub (`ic_agent_engine_vm_stub.dart`), both of which must stay pure-Dart.
// W6-1: `friendlyIcErrorMessage` + `kIcReachabilityMessage` are also re-exported
// so the dapp runner's result view can map raw IC error dumps to friendly text
// from the single facade import.
export 'web/ic_agent_types.dart'
    show
        IcAgentReadiness,
        IcAgentReady,
        IcAgentUnavailable,
        friendlyIcErrorMessage,
        kIcReachabilityMessage;

/// Keypair material returned by `RustBridgeLoader.generateKeypair`.
class RustKeypairResult {
  RustKeypairResult({
    required this.publicKeyB64,
    required this.privateKeyB64,
    required this.principalText,
  });
  final String publicKeyB64;
  final String privateKeyB64;
  final String principalText;
}

/// Vault-encryption output returned by `RustBridgeLoader.encryptVault`.
class EncryptedVaultResult {
  EncryptedVaultResult({
    required this.encryptedDataB64,
    required this.saltB64,
    required this.nonceB64,
  });
  final String encryptedDataB64;
  final String saltB64;
  final String nonceB64;
}

/// Thrown when vault encryption fails.
class VaultEncryptionException implements Exception {
  VaultEncryptionException(this.message);
  final String message;
  @override
  String toString() => 'VaultEncryptionException: $message';
}

/// Thrown when vault decryption fails.
class VaultDecryptionException implements Exception {
  VaultDecryptionException(this.message);
  final String message;
  @override
  String toString() => 'VaultDecryptionException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// R-3 WU-4 — QuickJS-on-Web readiness.
//
// The QuickJS-WASM engine must be LOADED (async, ~1–2 s on first run) before
// any script can execute. These sealed types let the UI render an honest
// loading / unavailable state instead of a raw exception or a silent no-op
// (mirrors the SecureStorageReadiness pattern). On IO/native the probe returns
// [QuickJsReady] immediately (the FFI is always available); on Web it loads
// the process-wide singleton engine.
// ─────────────────────────────────────────────────────────────────────────────

/// Result of [probeQuickJsReadiness]. Sealed so callers handle both states.
sealed class QuickJsReadiness {
  const QuickJsReadiness();
  bool get isReady;
}

/// The QuickJS engine is loaded (Web) or the FFI is available (native) —
/// scripts can execute.
final class QuickJsReady extends QuickJsReadiness {
  const QuickJsReady();
  @override
  bool get isReady => true;
}

/// The QuickJS-WASM engine could not be loaded (Web only). Render an actionable
/// panel — never a raw exception, never a silent no-op. [reason] is user-facing;
/// [detail] is for an optional "show details" affordance.
final class QuickJsUnavailable extends QuickJsReadiness {
  const QuickJsUnavailable({required this.reason, this.detail});
  final String reason;
  final String? detail;
  @override
  bool get isReady => false;
}

// `probeQuickJsReadiness()` is defined per-platform in
// `native_bridge_io.dart` (always [QuickJsReady]) and `native_bridge_web.dart`
// (loads the singleton engine), and re-exported to consumers via the
// conditional export at the top of this file.

// ─────────────────────────────────────────────────────────────────────────────
// R-3b WU-5 — IC-agent-on-Web readiness.
//
// The agent-js bundle must be LOADED (async — fetch the vendored JS, create the
// HttpAgent, fetch the mainnet root key via the CORS proxy) before any canister
// call can run. On IO/native the probe is an immediate [IcAgentReady] (the Rust
// FFI is the production path; agent-js is Web-only). On Web it loads the
// process-wide singleton agent and surfaces a friendly [IcAgentUnavailable]
// panel on failure — never a raw exception, never a silent no-op later. Mirrors
// the QuickJsReadiness gate above; awaited at the same boot sites.
// ─────────────────────────────────────────────────────────────────────────────

// `probeIcAgentReadiness()` is defined per-platform in
// `native_bridge_io.dart` (always [IcAgentReady]) and `native_bridge_web.dart`
// (loads the singleton agent), and re-exported to consumers via the
// conditional export at the top of this file.
