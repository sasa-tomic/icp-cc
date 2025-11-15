#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
ensure_tools
ensure_rust_targets_ios

# Build iOS static libs for xcframework assembly
(cd "${CRATE_DIR}" && cargo build --target aarch64-apple-ios --release)
(cd "${CRATE_DIR}" && cargo build --target x86_64-apple-ios --release)

A_LIB="${REPO_ROOT}/target/aarch64-apple-ios/release/libicp_core.a"
S_LIB="${REPO_ROOT}/target/x86_64-apple-ios/release/libicp_core.a"
if [[ ! -f "${A_LIB}" || ! -f "${S_LIB}" ]]; then
  echo "ERROR: Missing one or more iOS static libs: ${A_LIB}, ${S_LIB}" >&2
  exit 3
fi

echo "iOS: static libs built. Assemble xcframework via Xcode if needed."
