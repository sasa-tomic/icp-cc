#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
ensure_tools

# Build Windows dll (requires building on Windows or cross toolchain)
(cd "${CRATE_DIR}" && cargo build --release)

DLL="${REPO_ROOT}/target/release/icp_core.dll"
if [[ ! -f "${DLL}" ]]; then
  echo "ERROR: Missing ${DLL}" >&2
  exit 3
fi
cp_into "${DLL}" "${DART_APP_DIR}/build/windows/x64/runner/Release/icp_core.dll"
cp_into "${DLL}" "${DART_APP_DIR}/build/windows/x64/runner/Debug/icp_core.dll"
echo "Windows: icp_core.dll built and copied."
