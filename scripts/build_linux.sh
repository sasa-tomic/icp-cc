#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
ensure_tools

# Build Linux cdylib
(cd "${CRATE_DIR}" && cargo build --release)

# Verify artifact exists and copy into bundle path used by flutter linux run/build
LINUX_SO="${REPO_ROOT}/target/release/libicp_core.so"
if [[ ! -f "${LINUX_SO}" ]]; then
  echo "ERROR: Linux libicp_core.so not produced at ${LINUX_SO}" >&2
  exit 3
fi
cp_into "${LINUX_SO}" "${DART_APP_DIR}/build/linux/x64/debug/bundle/lib/libicp_core.so"
cp_into "${LINUX_SO}" "${DART_APP_DIR}/build/linux/x64/release/bundle/lib/libicp_core.so"
echo "Linux: libicp_core.so built and copied."
