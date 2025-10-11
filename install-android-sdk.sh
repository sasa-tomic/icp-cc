#!/usr/bin/env bash
set -eExuo pipefail

# ---------- settings (override via env) ----------
SDK_ROOT="${ANDROID_SDK_ROOT:-${HOME}/Android/Sdk}"
JAVA_PKG="${JAVA_PKG:-openjdk-21-jdk}"   # AGP 8.x requires JDK 17; 21 works for newer, 17 is safe default
NONINTERACTIVE="${NONINTERACTIVE:-true}" # set to false to see prompts
PROFILE_BLOCK_FILE="${HOME}/.android-sdk-env.sh"  # will be sourced from your shell rc
UPDATE_ONLY="${UPDATE_ONLY:-false}"      # set true to skip fresh tools download (just update)
# -------------------------------------------------

say()  { printf "\033[1;32m[+] %s\033[0m\n" "$*" >&2; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*" >&2; }
die()  { printf "\033[1;31m[x] %s\033[0m\n" "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

if [[ "${EUID}" -eq 0 ]]; then
  warn "Running as root is unnecessary. Use a normal user; sudo will be used where needed."
fi

say "Installing base dependencies (curl, unzip, JDK, udev rules for adb)…"
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  "${JAVA_PKG}" curl unzip zip ca-certificates \
  libstdc++6 libgcc-s1 \
  android-sdk-platform-tools-common # provides udev rules for adb on Debian/Ubuntu

mkdir -p "${SDK_ROOT}"

# Optional: keep system adb udev rules, but prefer our SDK's platform-tools first in PATH later.
# Detect newest Command-line Tools ZIP from official repo manifest (no hardcoded build number).
fetch_latest_cmdline_tools() {
  local manifest fname url tmpdir out
  manifest="https://dl.google.com/android/repository/repository2-1.xml"
  say "Querying latest Command-line Tools from: ${manifest}"

  fname="$(curl -fsSL "${manifest}" \
            | grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' \
            | sort -V | tail -n1 || true)"
  [[ -n "${fname}" ]] || die "Could not resolve latest Command-line Tools from manifest."

  url="https://dl.google.com/android/repository/${fname}"
  say "Latest Command-line Tools: ${fname}"

  tmpdir="$(mktemp -d)"
  out="${tmpdir}/${fname}"
  say "Downloading ${url}"
  curl -fL -sS --retry 3 --retry-delay 2 -o "${out}" "${url}"

  # Make sure we really got a zip
  unzip -tq "${out}" >/dev/null 2>&1 || die "Downloaded file is not a valid zip: ${out}"

  # IMPORTANT: print only the path on stdout
  printf '%s\n' "${out}"
}

rm -rf "${SDK_ROOT}/cmdline-tools/latest"

install_cmdline_tools() {
  local zipfile="$1" tmpdir
  tmpdir="$(mktemp -d)"
  say "Unpacking Command-line Tools into ${SDK_ROOT}/cmdline-tools/latest"
  unzip -q "${zipfile}" -d "${tmpdir}"
  mkdir -p "${SDK_ROOT}/cmdline-tools/latest"
  # The zip has a top-level "cmdline-tools/" dir; copy its contents into "latest/"
  cp -a "${tmpdir}/cmdline-tools/." "${SDK_ROOT}/cmdline-tools/latest/"
}

ensure_cmdline_tools() {
  local sdkmgr
  sdkmgr="${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
  if [[ "${UPDATE_ONLY}" == "true" && -x "${sdkmgr}" ]]; then
    say "UPDATE_ONLY=true and cmdline-tools already present — skipping re-download."
    return 0
  fi
  if [[ -x "${sdkmgr}" ]]; then
    say "Existing cmdline-tools found — refreshing to latest."
  fi
  local zipfile
  zipfile="$(fetch_latest_cmdline_tools)"
  # Clean any prior "latest" to avoid leftovers
  rm -rf "${SDK_ROOT}/cmdline-tools/latest"
  install_cmdline_tools "${zipfile}"
}

write_shell_profile_block() {
  cat > "${PROFILE_BLOCK_FILE}" <<'EOF'
# ---- Android SDK (auto-generated) ----
export ANDROID_SDK_ROOT="${HOME}/Android/Sdk"
export ANDROID_HOME="${ANDROID_SDK_ROOT}"   # some tools still read this
# Prefer our SDK first:
export PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}"
# Auto-detect JAVA_HOME if possible
if command -v javac >/dev/null 2>&1; then
  JAVA_BIN="$(readlink -f "$(command -v javac)" 2>/dev/null || true)"
  if [ -n "$JAVA_BIN" ]; then export JAVA_HOME="$(dirname "$(dirname "$JAVA_BIN")")"; fi
fi
# ---- End Android SDK block ----
EOF

  # Append to common shells if not already sourced
  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    if [[ -f "${rc}" ]]; then
      if ! grep -qF ". \"${PROFILE_BLOCK_FILE}\"" "${rc}"; then
        printf '\n# Android SDK env\n[ -f "%s" ] && . "%s"\n' "${PROFILE_BLOCK_FILE}" "${PROFILE_BLOCK_FILE}" >> "${rc}"
        say "Added SDK env sourcing to ${rc}"
      fi
    fi
  done
}

# Main
ensure_cmdline_tools
write_shell_profile_block

# Use explicit paths so current shell PATH doesn't matter
SDKMGR="${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"

require_cmd "${SDKMGR}" || die "sdkmanager not found after install."
# shellcheck disable=SC1090
. "${PROFILE_BLOCK_FILE}"

say "sdkmanager version: $("${SDKMGR}" --version || true)"

if [[ "${NONINTERACTIVE}" == "true" ]]; then
  say "Accepting SDK licenses non-interactively…"
  yes | "${SDKMGR}" --sdk_root="${SDK_ROOT}" --licenses >/dev/null || true
else
  "${SDKMGR}" --sdk_root="${SDK_ROOT}" --licenses || true
fi

say "Refreshing package lists…"
"${SDKMGR}" --sdk_root="${SDK_ROOT}" --update || true

say "Determining latest platform and build-tools…"
# Parse available versions from sdkmanager --list (format can vary slightly; keep it defensive)
LATEST_PLATFORM="$("${SDKMGR}" --sdk_root="${SDK_ROOT}" --list \
  | sed -n 's/^[[:space:]]*platforms;\(android-[0-9][0-9]*\).*/\1/p' \
  | sort -V | tail -n1)"
LATEST_BUILD_TOOLS="$("${SDKMGR}" --sdk_root="${SDK_ROOT}" --list \
  | sed -n 's/^[[:space:]]*build-tools;\([0-9][0-9]*\(\.[0-9][0-9]*\)\{1,2\}\).*/\1/p' \
  | sort -V | tail -n1)"

[[ -n "${LATEST_PLATFORM}" ]] || die "Could not detect latest platform from sdkmanager --list."
[[ -n "${LATEST_BUILD_TOOLS}" ]] || die "Could not detect latest build-tools from sdkmanager --list."

say "Installing core packages:"
echo "  - platform-tools"
echo "  - platforms;${LATEST_PLATFORM}"
echo "  - build-tools;${LATEST_BUILD_TOOLS}"
if [[ "${NONINTERACTIVE}" == "true" ]]; then
  yes | "${SDKMGR}" --sdk_root="${SDK_ROOT}" \
    "platform-tools" "platforms;${LATEST_PLATFORM}" "build-tools;${LATEST_BUILD_TOOLS}"
else
  "${SDKMGR}" --sdk_root="${SDK_ROOT}" \
    "platform-tools" "platforms;${LATEST_PLATFORM}" "build-tools;${LATEST_BUILD_TOOLS}"
fi

say "Verifying installation…"
"${SDK_ROOT}/platform-tools/adb" version || true
"${SDKMGR}" --sdk_root="${SDK_ROOT}" --list | grep -E "platform-tools|platforms;${LATEST_PLATFORM}|build-tools;${LATEST_BUILD_TOOLS}" || true

cat <<EOF

Done.

Environment is written to:
  ${PROFILE_BLOCK_FILE}

Open a NEW shell or run:
  . "${PROFILE_BLOCK_FILE}"

Android SDK root:
  ${SDK_ROOT}

Tip: to update later, run:
  UPDATE_ONLY=true bash $(basename "$0")

EOF

