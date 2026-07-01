# Browser Support

This document records the supported Flutter targets and the current status of
Flutter Web. It is the authoritative reference for the R-1 deferral decision.

## Status

Flutter Web is **not a supported target today** and is not on the near-term path.
The product ships Linux desktop + Android; macOS/Windows desktop build cleanly.

| Target | Status |
|--------|--------|
| Linux desktop | Supported (primary dev target) |
| Android | Supported |
| macOS desktop | Builds; supported |
| Windows desktop | Builds; supported |
| iOS | Untested |
| **Flutter Web** | **Unbuildable — deferred (R-1)** |

## Why Flutter Web is unbuildable

The Flutter app loads its Rust core (QuickJS runtime, crypto, ICP client) via
`dart:ffi`. `apps/autorun_flutter/lib/rust/native_bridge.dart:2` imports
`dart:ffi` unconditionally, and `apps/autorun_flutter/lib/main.dart:11` pulls it
in transitively. `dart:ffi` does not exist on the Web target, so
`flutter build web` and `flutter run -d chrome` fail to compile. There is no
conditional-import split today — the FFI binding is unconditional, so the Web
target cannot even start to compile.

## What re-enabling Web would take

This is a large, separate initiative tracked as **R-1 / TODO.md F-0**, out of
scope for the current prod-readiness work. The minimum required:

1. **Conditional imports** — split `native_bridge.dart` (and any other `dart:ffi`
   surface) into a `*_io.dart` FFI implementation and a `*_web.dart` stub,
   selected via `dart:io`'s `Platform.isWeb` at compile time.
2. **Web-native script runtime** — port QuickJS to WebAssembly and route script
   execution through it instead of the native cdylib.
3. **WebCrypto for keys** — replace the Rust keypair-generation / signing path
   with the browser WebCrypto API (or a WASM equivalent), since `dart:ffi` crypto
   is unavailable on Web.
4. **A Web passkey strategy** — the `passkeys` package is browser-capable, so Web
   is the natural passkey target; it just needs the three items above to compile
   first.

## Impact on passkey testing

On a Linux dev box, **neither** route can exercise a real passkey authenticator:

- **Linux desktop** (`flutter run -d linux`) — the `passkeys` package does not
  support Linux desktop, so `PasskeyPlatform.isSupported` is `false`. The passkey
  UI degrades gracefully; a real authenticator cannot be driven.
- **Flutter Web** — would be the supported target (KeePassXC / Android hybrid /
  YubiKey / Titan Key via the browser), but it is unbuildable (above).

Genuine passkey testing (registration / login / hybrid QR) requires macOS,
Windows, or Android — or a future resolution of R-1. See
[AGENTS.md — Passkey Testing on Linux](../AGENTS.md#passkey-testing-on-linux)
for the practical dev workflow.

## See also

- [docs/specs/PROD_READINESS_PLAN.md](specs/PROD_READINESS_PLAN.md) — R-1
  decision and PR-4 work unit.
- [AGENTS.md — Passkey Testing on Linux](../AGENTS.md#passkey-testing-on-linux)
- [docs/build-native.md](build-native.md) — Android/iOS native library build.
