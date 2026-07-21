# Building native libraries (Android/iOS)

## Android

Requirements:
- Rust stable with targets: `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`
- Android NDK r26+ (verified against **r27 / `27.0.12077973`**)

### Canonical path: `scripts/build_android.sh`

This is the supported entry point. It sources `scripts/common.sh`, installs the
Rust Android targets (`ensure_rust_targets_android`), auto-detects the NDK
(`setup_android_ndk_env` → resolves `ANDROID_NDK_HOME` + `CC_*`/`AR_*` for
aarch64/armv7/x86_64, including the rquickjs bindgen), builds all three ABIs in
release, and copies each `libicp_core.so` into the matching `jniLibs/<ABI>/`
folder consumed by the Flutter app:

```bash
./scripts/build_android.sh
```

### In the agent container (Docker)

The NDK is **not** baked into the image (~2 GB uncompressed). It is provided to
the container by a **read-only host mount** of `~/Android`
(`agent/docker-compose.yml`: `${HOME}/Android:/home/ubuntu/Android:ro`), with
`ANDROID_HOME=/home/ubuntu/Android/Sdk`. As long as the host has an NDK under
`~/Android/Sdk/ndk/<version>`, `setup_android_ndk_env` resolves it inside the
container and the cross-compile works unchanged. Verified 2026-07-21:
`aarch64-linux-android` `libicp_core.so` (13.6 MB) built in ~4m15s inside the
container (`file`: `... ARM aarch64 ... built by NDK r27 (12077973)`).

On a host **without** `~/Android` (e.g. a fresh CI runner), install the NDK
first:

```bash
sdkmanager "ndk;27.0.12077973"   # or mount a host ~/Android that already has it
```

### Manual / single-target (alternative)

For a single ABI without the wrapper:

```bash
rustup target add aarch64-linux-android
source scripts/common.sh && setup_android_ndk_env
(cd crates/icp_core && cargo build --release --target aarch64-linux-android)
# artifact: target/aarch64-linux-android/release/libicp_core.so
```

> The older `cargo-ndk` recipe (`cargo ndk -t ... build`) is **not** the
> project's path — `scripts/build_android.sh` (plain `cargo build --target` +
> `CC_*`/`AR_*` env from `setup_android_ndk_env`) is canonical. Prefer it.

## iOS
Requirements:
- Xcode toolchain

Build universal static lib and wrap into xcframework:
```bash
cd crates/icp_core
cargo build --target aarch64-apple-ios --release
cargo build --target x86_64-apple-ios --release

rm -rf icp_core.xcframework
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libicp_core.a \
  -library target/x86_64-apple-ios/release/libicp_core.a \
  -output icp_core.xcframework
```
Integrate the xcframework into the iOS Runner project and ensure it’s embedded and signed. Expose symbols are C ABI.

## Tests & Lints
From `crates/icp_core`:
```bash
cargo clippy --benches --tests --all-features && cargo clippy && cargo fmt --all && cargo nextest run
```
All must pass with no warnings.
