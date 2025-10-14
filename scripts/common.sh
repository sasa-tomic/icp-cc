#!/usr/bin/env bash
set -euo pipefail

# Common helpers for building Rust FFI across platforms

# Resolve repo root (assumes this script is under repo_root/scripts)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
CRATE_DIR="${REPO_ROOT}/crates/icp_core"
DART_APP_DIR="${REPO_ROOT}/apps/autorun_flutter"

ensure_tools() {
  if ! command -v rustup >/dev/null 2>&1; then
    echo "ERROR: rustup is required (https://rustup.rs)." >&2
    exit 2
  fi
  if ! command -v cargo >/dev/null 2>&1; then
    echo "ERROR: cargo not found on PATH (install Rust toolchain)." >&2
    exit 2
  fi
}

ensure_rust_targets_android() {
  rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android >/dev/null
}

ensure_rust_targets_macos() {
  rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null || true
}

ensure_rust_targets_ios() {
  rustup target add aarch64-apple-ios x86_64-apple-ios >/dev/null || true
}

# Build for a given target triple in release
cargo_build_target() {
  local triple="$1"
  (cd "${CRATE_DIR}" && cargo build --release --target "${triple}")
}

# Copy helper with mkdir -p
cp_into() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "${dst}")"
  install -m 0755 "${src}" "${dst}"
}

# Detect Android SDK/NDK and set CC_* env vars so crates like ring find clang
setup_android_ndk_env() {
  : "${ANDROID_HOME:=${HOME}/Android/Sdk}"
  : "${ANDROID_SDK_ROOT:=${ANDROID_HOME}}"
  if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    # Try to detect latest NDK installed
    if [[ -d "${ANDROID_HOME}/ndk" ]]; then
      ANDROID_NDK_HOME=$(ls -d "${ANDROID_HOME}/ndk"/* 2>/dev/null | sort -V | tail -n1 || true)
      export ANDROID_NDK_HOME
    fi
  fi
  if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "${ANDROID_NDK_HOME}" ]]; then
    echo "ERROR: ANDROID_NDK_HOME not set and NDK not found. Run: ./scripts/bootstrap.sh" >&2
    exit 4
  fi
  local ndk_bin="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
  if [[ ! -d "${ndk_bin}" ]]; then
    echo "ERROR: Expected NDK bin not found at ${ndk_bin}" >&2
    exit 4
  fi
  # Pick any available API level wrapper
  pick() { ls "$ndk_bin"/$1*-clang 2>/dev/null | sort -V | tail -n1 || true; }
  local AARCH64
  AARCH64=$(pick aarch64-linux-android)
  local ARMV7
  ARMV7=$(pick armv7a-linux-androideabi)
  local X86_64
  X86_64=$(pick x86_64-linux-android)
  local I686
  I686=$(pick i686-linux-android)
  local LLVM_AR="$ndk_bin/llvm-ar"
  if [[ -z "$AARCH64" || -z "$ARMV7" || -z "$X86_64" || -z "$I686" ]]; then
    echo "ERROR: Could not find target clang wrappers in NDK bin. Run: ./scripts/bootstrap.sh" >&2
    exit 4
  fi
  export CC_aarch64_linux_android="$AARCH64"
  export CC_armv7_linux_androideabi="$ARMV7"
  export CC_x86_64_linux_android="$X86_64"
  export CC_i686_linux_android="$I686"
  export AR_aarch64_linux_android="$LLVM_AR"
  export AR_armv7_linux_androideabi="$LLVM_AR"
  export AR_x86_64_linux_android="$LLVM_AR"
  export AR_i686_linux_android="$LLVM_AR"
  export PATH="$ndk_bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
}
