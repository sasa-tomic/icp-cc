# ICP Identity Manager + Canister Client

This repository contains a Flutter app (`icp_identity_manager/`) and a Rust crate (`rust/icp_core/`). The Rust crate provides identity utilities and a lightweight ICP canister client.

## Prerequisites
- Rust (latest stable). Recommended: rustup toolchain up to date.
- Flutter SDK (3.22+).
- Android/iOS toolchains as needed for mobile.

## Build Rust
- Format, lint, and test all Rust crates:
```bash
cargo fmt --all
cargo clippy --benches --tests --manifest-path rust/icp_core/Cargo.toml
cargo nextest run --manifest-path rust/icp_core/Cargo.toml
```

## Flutter app
From `icp_identity_manager/`:
```bash
flutter pub get
flutter run
```

## Canister client (Rust API)
- Fetch candid:
```rust
let did = icp_core::canister_client::fetch_candid("ryjl3-tyaaa-aaaaa-aaaba-cai", None)?;
```
- Parse interface:
```rust
let parsed = icp_core::canister_client::parse_candid_interface(&did)?; // list methods
```
- Call canister:
```rust
use icp_core::canister_client::MethodKind;
let out = icp_core::canister_client::call_anonymous(
  "ryjl3-tyaaa-aaaaa-aaaba-cai",
  "greet",
  MethodKind::Query,
  "()",
  None,
)?;
```

## Notes
- Args currently accept "()" for empty or "base64:<candid_encoded_bytes>".
- Favorites are stored at `$XDG_CONFIG_HOME/icp-cc/favorites.json`.
