# Browser (Flutter Web) Support

This document is the authoritative reference for the Flutter Web target's
status. It supersedes the earlier "Web is unbuildable" assessment — the
conditional-import split (R-1) and a pure-Dart Web runtime foundation (R-2 /
R-4 / R-5) are now in place.

## TL;DR

Flutter Web **builds cleanly** (`flutter build web` → exit 0) and runs the
identity / account / vault / passkey flows in the browser. The browser has no
`dart:ffi`, so every operation the native core (`libicp_core`) provides is
re-implemented in **pure Dart** on Web — no JS interop, no mock crypto. Script
execution (QuickJS) and direct IC canister calls are deliberately **stubbed**
(staged for a follow-up effort).

| Area | Status on Web |
|------|---------------|
| Ed25519 keypair generation, signing, ICP principal | ✅ Real (pure Dart) — cross-compatible with native |
| Vault crypto (Argon2id + AES-256-GCM) | ✅ Real (pure Dart) — blobs round-trip native ↔ Web |
| Secure storage (`flutter_secure_storage_web`) | ✅ Backend present (IndexedDB + AES) |
| Backend CORS for browser fetch | ✅ Permissive by default (no change needed) |
| Passkeys (`navigator.credentials`) | ✅ Compiles; WebAuthn E2E needs a real browser session |
| secp256k1 keypair / signing | ⚠️ Best-effort STUBBED (Ed25519 is the ICP-critical path) |
| QuickJS script execution / linting (R-3) | 🟢 **R-3a ✅** — execution (init/view/update + jsExec) AND lint/validate run on Web with native parity (51 golden vectors); **R-3b ✅** — IC-canister HTTP agent (`fetchCandid`/`callAnonymous`/`callAuthenticated`) via `@dfinity/agent` + backend byte-relay CORS proxy, live-verified on mainnet |
| IC canister calls (`fetchCandid`, `callAuthenticated`, …) | ❌ STUBBED — staged |

## How to run

```bash
cd apps/autorun_flutter
flutter run -d chrome        # dev (hot reload)
flutter build web            # production bundle → build/web/
```

> **Wasm note.** `flutter build web` (the default JS target) succeeds. The
> future **Wasm** (`--wasm`) target is not yet supported: `dart:ffi`,
> `dart:js_util`, and `package:js` (used transitively by
> `flutter_secure_storage_web` and `libc_setenv_io.dart`) cannot compile to
> Wasm today. The build prints these as warnings, not errors.

## Architecture

`apps/autorun_flutter/lib/rust/native_bridge.dart` is a pure-Dart facade with
a conditional export:

```dart
export 'native_bridge_io.dart'  // real dart:ffi → libicp_core
    if (dart.library.html) 'native_bridge_web.dart';  // pure-Dart impl
```

- **IO platforms** → `native_bridge_io.dart` calls the Rust cdylib via FFI.
- **Web** → `native_bridge_web.dart` re-implements the crypto in pure Dart:
  - Ed25519 keygen / sign → `package:ed25519_edwards` (Go-port; sync).
  - ICP principal (SPKI DER RFC 8410 → SHA-224 → CRC32 → base32) → inline
    using `package:crypto`.
  - BIP39 seed derivation (PBKDF2-HMAC-SHA512, 2048 iters) → inline using
    `package:crypto`. *(The `package:bip39` `mnemonicToSeed` is buggy for
    24-word mnemonics — see the inline note in `native_bridge_web.dart`.)*
  - Argon2id KDF → `package:cryptography`'s `DartArgon2id`.
  - AES-256-GCM → `package:cryptography`'s `AesGcm.with256bits()`.

Because the implementation is pure Dart (no `dart:html` / `dart:js_interop`),
the **same code paths are unit-testable in `flutter test`** (Dart VM) and ship
to the browser unchanged. There is no separate "browser test" harness.

## Cross-compatibility (native ↔ Web)

Vault blobs and signatures are **byte-for-byte interchangeable** between the
native core and the Web runtime. This is verified by:

1. An **Argon2id known vector**: `derive_key("test-password", 16×0x01)` with
   Bitwarden-level params (m=65536, t=3, p=4, outLen=32) produces
   `d01d66842417f2c272d92e15e46a23e2b351b2c52ae42d1c59c1c8a7c3486a63` on both
   Rust (`argon2` crate) and the Dart `DartArgon2id`. Since AES-256-GCM is
   deterministic given (key, nonce), matching KDF ⇒ matching blobs.
2. **Ed25519 vectors**: the standard all-zero-entropy BIP39 mnemonic yields an
   identical keypair / principal / signature on both sides (captured from
   `crates/icp_core/tests/common/mod.rs`).
3. **Live round-trip tests** (`test/features/web/`): a blob encrypted by
   `libicp_core` decrypts on Web and vice-versa.

See `apps/autorun_flutter/test/features/web/` for the cross-compat suites.

## What is still stubbed (fail-fast)

The following throw a loud `UnsupportedError` on Web. They are **staged** for a
separate effort (R-3 / IC HTTP-agent) and are NOT regressions:

- `jsExec`, `jsAppInit`, `jsAppView`, `jsAppUpdate` — **DONE (R-3a).** These
  now run on Web via the vendored `quickjs-emscripten` WASM
  (`web/vendor/quickjs/`) driven from Dart (`lib/rust/web/quickjs_engine.dart`),
  producing the same `{state, effects}` / `{result, messages}` envelopes as the
  native engine. A readiness gate (`probeQuickJsReadiness()`) loads the engine
  before the sync eval calls; loading/unavailable states surface honestly.
  `jsLint` + `validateJsComprehensive` are **DONE (WU-5)** — a pure-Dart port of
  the `static_analysis` mod (no QuickJS needed for the static stages), VM-tested.
- `fetchCandid`, `parseCandid`, `callAnonymous`, `callAuthenticated` — need a
  Web-native IC HTTP agent (R-3b follow-up). Scripts that emit `action:"call"`/
  `"batch"` *effects* run and surface the descriptors; resolving them to live
  IC calls is what R-3b adds.
- `secp256k1` keygen / signing (`alg=1`) — best-effort; Ed25519 (`alg=0`) is the
  ICP-critical path and is fully implemented. secp256k1 requires BIP32
  derivation (`m/44'/223'/0'/0/0`) on top of ECDSA, staged as an R-2 follow-up.

## QuickJS-on-Web (R-3)

R-3 ports the native QuickJS engine (`crates/icp_core/src/js_engine/runtime.rs`)
to the browser. Bundles are plain ES2015 JavaScript (no TS transpilation), so
the Web engine is a near-mechanical mirror onto `quickjs-emscripten` (the
standard QuickJS-WASM library — its runtime API is a near-1:1 match for
`rquickjs`, the native engine).

- **Vendored asset:** `web/vendor/quickjs/quickjs_emscripten.bundle.js` (~850 KB,
  WASM inlined as base64 — `@jitl/quickjs-singlefile-browser-release-sync@0.32.0`
  pre-bundled via esbuild; no separate `.wasm` fetch, no app build step). Loaded
  by a `<script type="module">` in `web/index.html`; it installs
  `globalThis.__quickjsEmscripten`, which `lib/rust/web/quickjs_engine.dart`
  drives via `dart:js_interop`.
- **Status:**
  - WU-1 (PoC) ✅ — `flutter build web` clean; `just verify-quickjs-web` proves
    `evalCode("1+2")===3`, `setMemoryLimit` aborts OOM (`InternalError: out of
    memory`), and `setInterruptHandler` halts `while(true){}` at the wall-clock
    deadline (`InternalError: interrupted`, ~100ms — mirroring `runtime.rs:25,30-37`).
  - **R-3a (execution) ✅** — `jsExec` + `jsAppInit/View/Update` ported to
    `WebQuickJsEngine` (byte-for-byte host globals + envelopes). A process-wide
    singleton engine + `probeQuickJsReadiness()` readiness gate (awaited in
    `ScriptAppHost._boot` / `ScriptRunner.run`) loads the WASM once; loading /
    unavailable states surface honestly via the busy/error UI. `native_bridge_web.dart`
    routes through a conditional-import access module (VM-pure stub on IO) so the
    R-2/R-4 web-crypto VM tests keep passing.
  - **Parity evidence:** `just verify-quickjs-web-parity` runs **51 golden vectors**
    (32 execution: every `execute_js_json` + `js_app_*` Rust test, plus the shipped
    `01_hello_world.js`; 19 validation/lint: every `validate_js_comprehensive`/
    `lint_js` Rust test) on headless Chromium — identical envelopes. `just verify-quickjs-web-app` runs the SAME
    bundle through the REAL production stack (`probeQuickJsReadiness →
    RustScriptBridge → ScriptAppRuntime`).
  - **R-3a complete (execution + lint/validate) ✅.** Only R-3b (IC HTTP agent)
    pending.
- **Testing posture:** the engine is browser-only (`dart:js_interop` can't be
  imported in `flutter test` VM). The headless-Chrome harness
  (`scripts/quickjs_web_probe/` — `verify.js`, `verify_parity.js`,
  `verify_app.js`) is the parity test path. Pure-Dart logic (golden-vector
  catalogues, the readiness types) is VM-tested. See
  `docs/specs/2026-07-09-r3-web-script-execution.md` §2.3.

## CORS

The backend (`backend/src/main.rs`) applies poem's `Cors::new()` to every
route group. With no explicit configuration, poem's defaults are permissive
enough for browser access (verified against `poem-3.1.12/src/middleware/cors.rs`
and its `default_cors` test):

- **Origins**: any `Origin` header is accepted and echoed back in
  `Access-Control-Allow-Origin`.
- **Methods**: preflight advertises all methods (GET, POST, PUT, DELETE, HEAD,
  OPTIONS, CONNECT, PATCH, TRACE).
- **Headers**: preflight echoes back `Access-Control-Request-Headers`
  (so `Authorization`, `Content-Type`, etc. are allowed).

No backend change is required for the Web client.

## Secure storage

`flutter_secure_storage: ^9.2.2` pulls in `flutter_secure_storage_web` (IndexedDB
+ AES via SubtleCrypto). It compiles into the Web bundle (confirmed by
`flutter build web`). A live browser round-trip is recommended but the backend
is the standard, audited implementation.

## Passkeys

`passkeys: ^2.1.0` uses `navigator.credentials` and is browser-capable. On Web
it compiles and `PasskeyPlatform.isSupported` returns `true` (unlike Linux
desktop, where it is `false`). Full WebAuthn E2E (registration / login /
hybrid QR) requires a real browser session with an authenticator (KeePassXC,
Android hybrid, YubiKey, etc.) and cannot be exercised headlessly in CI.

The backend Relying-Party origin configuration should include the Web origin
served by `flutter run -d chrome` (e.g. `http://localhost:<port>` in dev).

## Track items

- **R-1** ✅ Conditional-import split (`native_bridge.dart` facade).
- **R-2** ✅ Ed25519 keygen / sign / ICP principal (pure Dart, cross-compatible).
- **R-4** ✅ Vault crypto — Argon2id + AES-256-GCM (pure Dart, cross-compatible).
- **R-5** ✅ CORS verified; secure-storage + passkeys wired for Web.
- **R-3** ✅ QuickJS-WASM script runtime — **R-3a ✅ (execution + lint/validate)**: jsExec + init/view/update + jsLint/validateJsComprehensive run on Web with native parity (51 golden vectors + production-path probe green). **R-3b ✅ (IC HTTP agent)**: `fetchCandid`/`parseCandid`/`callAnonymous`/`callAuthenticated` via `@dfinity/agent@3.4.3` + backend byte-relay CORS proxy; ICP ledger `symbol() → "ICP"` proven live.
- **IC-agent** ✅ Web-native canister HTTP agent — done (R-3b above).

## See also

- [`AGENTS.md` — Passkey Testing on Linux](../AGENTS.md#passkey-testing-on-linux)
- [`docs/build-native.md`](build-native.md) — native library build (IO platforms).
- `apps/autorun_flutter/test/features/web/` — Web cross-compat tests.
