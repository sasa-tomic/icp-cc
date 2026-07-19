#!/usr/bin/env bash
# Build the Flutter Web bundle for Playwright e2e (Phase C Tier B).
#
# Wraps `flutter build web` with the local dev backend endpoint baked in via
# `--dart-define=PUBLIC_API_ENDPOINT=...`. Mirrors `just web-dev-build`; this
# script is the CI-friendly form (no just dependency, single output dir).
#
# Output: apps/autorun_flutter/build/web/  (static bundle — index.html + JS +
# canvaskit wasm + assets). Serve with any static HTTP server (the harness
# uses `python3 -m http.server 8099` for local runs; CI uses whatever it
# likes).
#
# Usage:
#   scripts/web-e2e-build.sh                # builds with :35735 (or whatever
#                                            # the api-dev-port says)
#   scripts/web-e2e-build.sh --serve 8099   # builds + serves on :8099
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="$ROOT/apps/autorun_flutter"
PORT_FILE="$ROOT/.just-tmp/icp-api.port"

if [[ ! -f "$PORT_FILE" ]]; then
  echo "❌ Backend not running (no $PORT_FILE). Start with: just api-dev-up" >&2
  exit 1
fi
API_PORT="$(cat "$PORT_FILE")"

echo "==> Building Flutter Web against http://127.0.0.1:$API_PORT"
cd "$FLUTTER_DIR" && flutter build web \
  --dart-define=PUBLIC_API_ENDPOINT="http://127.0.0.1:$API_PORT" \
  --dart-define=ICP_E2E=1 \
  --dart-define=ICP_E2E_MOCK_ICPAY=1

BUNDLE="$FLUTTER_DIR/build/web"
echo "✅ Bundle: $BUNDLE"
echo "   Serve:  cd \"$BUNDLE\" && python3 -m http.server 8099"

if [[ "${1:-}" == "--serve" ]]; then
  PORT="${2:-8099}"
  echo "==> Serving on http://127.0.0.1:$PORT"
  echo "   Ctrl-C to stop."
  cd "$BUNDLE" && python3 -m http.server "$PORT"
fi
