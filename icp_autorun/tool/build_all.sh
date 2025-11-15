#!/usr/bin/env bash
set -euo pipefail

# Build Rust libs for all platforms (where possible from this host) and place/copy into app bundles.
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
CRATE_DIR="$ROOT_DIR/../rust/icp_core"
WORKSPACE_ROOT="$ROOT_DIR/.."

if [ ! -d "$CRATE_DIR" ]; then
  echo "Rust crate dir not found: $CRATE_DIR" >&2
  exit 1
fi

# Linux
if [[ "$(uname -s)" == "Linux" ]]; then
  echo "Building Linux cdylib..."
  (cd "$CRATE_DIR" && cargo build --release)
  install -m 0755 "$WORKSPACE_ROOT/target/release/libicp_core.so" "$ROOT_DIR/build/linux/x64/release/bundle/lib/" 2>/dev/null || true
fi

# Android
if command -v cargo-ndk >/dev/null 2>&1; then
  echo "Building Android ABIs via cargo-ndk..."
  (cd "$WORKSPACE_ROOT" && cargo ndk -t armeabi-v7a -t arm64-v8a -t x86 -t x86_64 -o "$ROOT_DIR/android/app/src/main/jniLibs" build -p icp_core --release)
else
  echo "cargo-ndk not found; skipping Android ndk build"
fi

# macOS (dylib)
if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "Building macOS dylib..."
  (cd "$CRATE_DIR" && cargo build --release)
  mkdir -p "$ROOT_DIR/build/macos/Build/Products/Release/"
  cp "$WORKSPACE_ROOT/target/release/libicp_core.dylib" "$ROOT_DIR/build/macos/Build/Products/Release/" 2>/dev/null || true
fi

# iOS xcframework (manual integration still required)
if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "Building iOS static libs..."
  (cd "$CRATE_DIR" && cargo build --target aarch64-apple-ios --release && cargo build --target x86_64-apple-ios --release)
  echo "Create/refresh xcframework per docs/build-native.md as needed."
fi

# Windows (dll) — requires cross toolchain if not on Windows
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == CYGWIN* || "$(uname -s)" == MSYS* ]]; then
  echo "Building Windows dll..."
  (cd "$CRATE_DIR" && cargo build --release)
fi
