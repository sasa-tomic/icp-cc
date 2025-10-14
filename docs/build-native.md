# Building native libraries (Android/iOS)

## Android
Requirements:
- Rust stable with targets: aarch64-linux-android, armv7-linux-androideabi, i686-linux-android, x86_64-linux-android
- Android NDK r26+

Steps:
1. Install targets:
```bash
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
```
2. Build with cargo-ndk:
```bash
cargo install cargo-ndk
cargo ndk -t armeabi-v7a -t arm64-v8a -t x86 -t x86_64 -o ../apps/autorun_flutter/android/app/src/main/jniLibs build -p icp_core --release
```
This will place `libicp_core.so` into ABI folders under `jniLibs`.

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
