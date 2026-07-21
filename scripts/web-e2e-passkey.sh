#!/usr/bin/env bash
# WEB-1 — Passkey-on-Web PoC + production e2e harness driver.
#
# Brings up a DEDICATED backend instance (separate from `api-dev-up`) with the
# WebAuthn RP origin matching the test page URL, builds the Flutter Web bundle
# against that backend, serves it on http://localhost:8099, and runs the
# Playwright passkey spec against it.
#
# Why a dedicated backend: the dev backend (`api-dev-up`) defaults
# WEBAUTHN_RP_ORIGIN to http://localhost:58000. For WebAuthn the RP_ORIGIN
# MUST match the page origin exactly; the spec serves the page on
# http://localhost:8099 (so the WebAuthn challenge's `origin` field reads
# `http://localhost:8099` and the backend's verifier accepts it). Restarting
# the shared dev backend with a different RP_ORIGIN would break any other
# flow currently using it; a dedicated backend on a separate port leaves the
# dev backend untouched.
#
# Idempotent: re-uses a running dedicated instance if its port-file exists;
# otherwise starts one. Tear down via trap on exit (no orphan processes).
#
# Usage:
#   scripts/web-e2e-passkey.sh             # build + run
#   scripts/web-e2e-passkey.sh --no-build  # skip build (assume bundle exists)
#   scripts/web-e2e-passkey.sh --keep-servers # don't tear down (debug)
#
# Exposed env overrides (rarely needed):
#   WEB_E2E_BACKEND_PORT  default 41098
#   WEB_E2E_BUNDLE_PORT   default 8099
#   WEB_E2E_BACKEND_BIN   default <root>/target/release/icp-marketplace-api
#   WEB_E2E_BACKEND_DB    default <root>/.just-tmp/web-e2e-passkey.db
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="$ROOT/apps/autorun_flutter"
PW_DIR="$FLUTTER_DIR/web_e2e_playwright"
BACKEND_BIN="${WEB_E2E_BACKEND_BIN:-$ROOT/target/release/icp-marketplace-api}"
BACKEND_DB="${WEB_E2E_BACKEND_DB:-$ROOT/.just-tmp/web-e2e-passkey.db}"
BACKEND_PORT="${WEB_E2E_BACKEND_PORT:-41098}"
BUNDLE_PORT="${WEB_E2E_BUNDLE_PORT:-8099}"
BACKEND_PORT_FILE="$ROOT/.just-tmp/web-e2e-passkey.port"
BACKEND_PID_FILE="$ROOT/.just-tmp/web-e2e-passkey.pid"

NO_BUILD=0
KEEP_SERVERS=0
for arg in "$@"; do
  case "$arg" in
    --no-build) NO_BUILD=1 ;;
    --keep-servers) KEEP_SERVERS=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$ROOT/.just-tmp" "$ROOT/logs"

# --- 1. Toolchain checks (fail LOUD, never auto-install) -------------------
[[ -f "$BACKEND_BIN" ]] || {
  echo "❌ Backend binary missing: $BACKEND_BIN" >&2
  echo "   Build with: (cd $ROOT && cargo build --release)" >&2
  exit 1
}
command -v flutter >/dev/null || { echo "❌ flutter not on PATH" >&2; exit 1; }
command -v node    >/dev/null || { echo "❌ node not on PATH" >&2; exit 1; }
command -v npx    >/dev/null 2>&1 || { echo "❌ npx not on PATH (install Node.js)" >&2; exit 1; }

# --- 2. Dedicated backend (RP origin = http://localhost:<bundle_port>) -----
start_backend() {
  rm -f "$BACKEND_DB" "${BACKEND_DB}-shm" "${BACKEND_DB}-wal"
  echo "==> Starting dedicated backend on :$BACKEND_PORT"
  echo "    WEBAUTHN_RP_ID=localhost"
  echo "    WEBAUTHN_RP_ORIGIN=http://localhost:$BUNDLE_PORT"
  PORT="$BACKEND_PORT" \
  DATABASE_URL="sqlite:$BACKEND_DB?mode=rwc" \
  WEBAUTHN_RP_ID=localhost \
  WEBAUTHN_RP_ORIGIN="http://localhost:$BUNDLE_PORT" \
  PAYMENT_PROVIDER=stub \
  ENVIRONMENT=development \
  RUST_LOG=info \
  "$BACKEND_BIN" >"$ROOT/logs/web-e2e-passkey-backend.log" 2>&1 &
  BACKEND_PID=$!
  echo "$BACKEND_PID" >"$BACKEND_PID_FILE"
  echo "$BACKEND_PORT" >"$BACKEND_PORT_FILE"
  # Poll for readiness (≤30s — matches justfile api-dev-up).
  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if curl -sf "http://127.0.0.1:$BACKEND_PORT/api/v1/health" >/dev/null 2>&1; then
      echo "    backend healthy (pid $BACKEND_PID)"
      return 0
    fi
    if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
      echo "❌ Backend died during startup. Log:" >&2
      tail -50 "$ROOT/logs/web-e2e-passkey-backend.log" >&2 || true
      exit 1
    fi
    sleep 0.25
  done
  echo "❌ Backend did not become healthy within 30s. Log:" >&2
  tail -50 "$ROOT/logs/web-e2e-passkey-backend.log" >&2 || true
  exit 1
}

# Reuse a healthy dedicated backend if its port-file says one's running.
BACKEND_PID=""
if [[ -f "$BACKEND_PID_FILE" && -f "$BACKEND_PORT_FILE" ]]; then
  maybe_pid="$(cat "$BACKEND_PID_FILE")"
  maybe_port="$(cat "$BACKEND_PORT_FILE")"
  if [[ "$maybe_port" == "$BACKEND_PORT" ]] && kill -0 "$maybe_pid" 2>/dev/null; then
    if curl -sf "http://127.0.0.1:$BACKEND_PORT/api/v1/health" >/dev/null 2>&1; then
      BACKEND_PID="$maybe_pid"
      echo "==> Reusing dedicated backend (pid $BACKEND_PID) on :$BACKEND_PORT"
    fi
  fi
fi
if [[ -z "$BACKEND_PID" ]]; then
  start_backend
fi

# Tear down on exit unless --keep-servers (NO orphan processes).
STATIC_PID=""
cleanup() {
  set +e
  if [[ -n "$STATIC_PID" ]]; then
    kill "$STATIC_PID" 2>/dev/null
    wait "$STATIC_PID" 2>/dev/null
  fi
  if [[ "$KEEP_SERVERS" -eq 0 && -n "$BACKEND_PID" ]]; then
    # Only kill the backend WE started (not a reused one).
    if [[ ! -f "$BACKEND_PID_FILE" || "$(cat "$BACKEND_PID_FILE")" == "$BACKEND_PID" ]]; then
      kill "$BACKEND_PID" 2>/dev/null
      wait "$BACKEND_PID" 2>/dev/null
      rm -f "$BACKEND_PID_FILE" "$BACKEND_PORT_FILE"
    fi
  fi
}
trap cleanup EXIT

# --- 3. Build the bundle (idempotent) -------------------------------------
BUNDLE_DIR="$FLUTTER_DIR/build/web"
if [[ "$NO_BUILD" -eq 0 ]]; then
  echo "==> Building Flutter Web bundle (tool/web_probe_passkey_main.dart)"
  (cd "$FLUTTER_DIR" && flutter build web \
      --target=tool/web_probe_passkey_main.dart \
      --dart-define=PUBLIC_API_ENDPOINT="http://127.0.0.1:$BACKEND_PORT" \
      --dart-define=ICP_E2E=1)
fi
[[ -f "$BUNDLE_DIR/index.html" ]] || {
  echo "❌ Bundle missing: $BUNDLE_DIR/index.html" >&2
  exit 1
}

# --- 4. Playwright deps (idempotent) --------------------------------------
[[ -d "$PW_DIR/node_modules" ]] || (cd "$PW_DIR" && npm install --no-audit --no-fund)
# Verify Playwright version supports the modern credentials API (>=1.61).
pw_version="$(node -e "console.log(require('$PW_DIR/node_modules/playwright/package.json').version)" 2>/dev/null || echo "0")"
pw_major="$(echo "$pw_version" | cut -d. -f1)"
pw_minor="$(echo "$pw_version" | cut -d. -f2)"
if [[ "$pw_major" -lt 1 ]] || { [[ "$pw_major" -eq 1 ]] && [[ "$pw_minor" -lt 61 ]]; }; then
  echo "❌ Playwright $pw_version is too old. Need >= 1.61 for context.credentials." >&2
  echo "   Upgrade: (cd $PW_DIR && npm install playwright@^1.61)" >&2
  exit 1
fi
echo "    Playwright $pw_version ✓"
# Ensure Chromium is installed (Playwright-managed cache).
[[ -d "$HOME/.cache/ms-playwright/chromium"* ]] || (cd "$PW_DIR" && npx playwright install chromium)

# --- 5. Serve the bundle on http://localhost:<bundle_port>/ ----------------
# `localhost` (not 127.0.0.1) so the WebAuthn RP ID `localhost` matches the
# page origin — a 127.0.0.1 origin would make the backend reject the
# credential assertion (origin mismatch).
echo "==> Serving bundle on http://localhost:$BUNDLE_PORT/"
(cd "$BUNDLE_DIR" && python3 -m http.server "$BUNDLE_PORT" --bind localhost) \
  >"$ROOT/logs/web-e2e-passkey-static.log" 2>&1 &
STATIC_PID=$!
# Poll for readiness (≤30s with a loud error if it can't bind).
static_deadline=$((SECONDS + 30))
while (( SECONDS < static_deadline )); do
  if curl -sf "http://localhost:$BUNDLE_PORT/" >/dev/null 2>&1; then break; fi
  if ! kill -0 "$STATIC_PID" 2>/dev/null; then
    echo "❌ Static server died during startup. Log:" >&2
    tail -50 "$ROOT/logs/web-e2e-passkey-static.log" >&2 || true
    exit 1
  fi
  sleep 0.25
done
if ! curl -sf "http://localhost:$BUNDLE_PORT/" >/dev/null 2>&1; then
  echo "❌ Static server did not become healthy within 30s." >&2
  echo "   (port $BUNDLE_PORT busy? override with WEB_E2E_BUNDLE_PORT=…)" >&2
  exit 1
fi

# --- 6. Run the Playwright passkey spec ------------------------------------
echo "==> Running Playwright passkey spec"
export BASE_URL="http://localhost:$BUNDLE_PORT/"
(cd "$PW_DIR" && npx playwright test --reporter=list --workers=1 specs/passkey.spec.ts)

echo "✅ WEB-1 passkey-on-web e2e PASSED"
