#!/usr/bin/env bash
set -eEuo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
ensure_tools
ensure_rust_targets_android
setup_android_ndk_env

# Build Android ABIs
for t in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android; do
  cargo_build_target "$t"
  SO_PATH="${REPO_ROOT}/target/${t}/release/libicp_core.so"
  if [[ ! -f "${SO_PATH}" ]]; then
    echo "ERROR: Missing ${SO_PATH}" >&2
    exit 3
  fi
  case "$t" in
    aarch64-linux-android) ABI=arm64-v8a ;;
    armv7-linux-androideabi) ABI=armeabi-v7a ;;
    x86_64-linux-android) ABI=x86_64 ;;
  esac
  cp_into "${SO_PATH}" "${DART_APP_DIR}/android/app/src/main/jniLibs/${ABI}/libicp_core.so"
done

echo "Android: all ABIs built and copied into jniLibs/."
