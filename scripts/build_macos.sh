#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
ensure_tools
ensure_rust_targets_macos

# Build macOS dylib
(cd "${CRATE_DIR}" && cargo build --release)

DYLIB="${REPO_ROOT}/target/release/libicp_core.dylib"
if [[ ! -f "${DYLIB}" ]]; then
  echo "ERROR: Missing ${DYLIB}" >&2
  exit 3
fi
# Copy near typical Flutter macOS build output; actual app bundle copy step may be needed in Xcode
cp_into "${DYLIB}" "${DART_APP_DIR}/build/macos/Build/Products/Debug/libicp_core.dylib"
cp_into "${DYLIB}" "${DART_APP_DIR}/build/macos/Build/Products/Release/libicp_core.dylib"
echo "macOS: libicp_core.dylib built and copied."
