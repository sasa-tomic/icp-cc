## Objectives
- Replace Dart identity logic with a Rust core for key generation and principal derivation, keeping Flutter as UI.
- Prioritize Android and iOS; then enable Web (Wasm) and Desktop.
- Keep the Rust API small and stable to extend later (Candid/Agent).

## Scope of Work
- Rust crate `rust/icp_core`:
  - `generate_ed25519_identity(mnemonic?: String) -> IdentityData`
  - `generate_secp256k1_identity(mnemonic?: String) -> IdentityData`
  - `principal_from_public_key(alg: "ed25519"|"secp256k1", public_key: &[u8]) -> String`
  - `IdentityData { public_key_b64, private_key_b64, principal_text }`
  - Crates: `bip39`, `bitcoin`, `ed25519-dalek`, `candid`, `base64`, `sha2`.
- Bridge & Platforms
  - Use FFI now with a minimal C-ABI (`icp_generate_identity`) and plan FRB/Wasm later.
  - Android/iOS via `dart:ffi`. Web keeps current Dart path short-term.
- Flutter integration
  - Add a Dart facade that calls FFI on native and falls back to Dart on Web.
  - Update `IdentityGenerator.generate(...)` to use the Rust-backed path.
- Tests (TDD)
  - Rust: unit tests for known vectors and principal text.
  - Dart: existing tests remain unchanged and must pass.
- Build/Dev
  - Android: `cargo-ndk` for all ABIs.
  - iOS: `xcframework` build.
  - Web: wasm path planned with FRB.

## Definition of Done (DoD)
- Functional
  - `cargo nextest run` and `cargo clippy --benches --tests --all-features && cargo clippy && cargo fmt --all` are clean with no warnings.
  - Rust unit tests pass; vectors/principals match existing Dart tests.
  - `flutter test` passes unchanged.
  - Android/iOS builds succeed, app outputs identical identities/principals.
  - Web runs with Dart fallback initially.
- Non-functional
  - Minimal, DRY Rust API with typed interface; deterministic outputs for given mnemonics.
  - Concise build docs for Android/iOS/Web; single Dart facade.
- Safety
  - No unsafe across boundary beyond minimal FFI; documented safety contracts.
