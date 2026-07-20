#!/usr/bin/env bash
# Seed the marketplace backend with N bulk-seed scripts so pagination-
# dependent e2e flows (scripts.load_more) can exercise the page threshold.
#
# Usage:
#   scripts/seed-marketplace.sh [N]      # default N=25
#   scripts/seed-marketplace.sh 30
#   scripts/seed-marketplace.sh --purge  # delete all bulk_seed scripts first
#
# Wraps `dart run apps/autorun_flutter/tool/seed_marketplace.dart`. Reads
# the backend port from $MARKETPLACE_API_PORT (exported by `just api-dev-up`)
# or `backend/.api-dev-port` (whichever is set). Idempotent — running it
# twice with the same N uploads exactly N scripts total (skips already-seeded
# indices).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLUTTER_DIR="$ROOT/apps/autorun_flutter"

# Resolve the backend port the same way the e2e harness does.
if [[ -z "${MARKETPLACE_API_PORT:-}" ]]; then
    PORT_FILE="$ROOT/backend/.api-dev-port"
    if [[ -f "$PORT_FILE" ]]; then
        # File format: MARKETPLACE_API_PORT=NNNNN
        MARKETPLACE_API_PORT="$(grep -E '^MARKETPLACE_API_PORT=' "$PORT_FILE" \
            | head -1 | cut -d= -f2)"
    fi
fi
if [[ -z "${MARKETPLACE_API_PORT:-}" ]]; then
    echo "❌ $0: MARKETPLACE_API_PORT not set and $ROOT/backend/.api-dev-port missing." >&2
    echo "   Run 'just api-dev-up' first, or export MARKETPLACE_API_PORT=<port>." >&2
    exit 1
fi
export MARKETPLACE_API_PORT

ENDPOINT="http://127.0.0.1:${MARKETPLACE_API_PORT}"
echo "==> seed-marketplace: backend=$ENDPOINT"

# Default count (overridable via $1).
COUNT=25
ARGS=()
if [[ $# -ge 1 ]]; then
    case "$1" in
        --purge)  ARGS+=("--purge"); shift ;;
        --clean)  ARGS+=("--clean"); COUNT="${2:-$COUNT}"; shift 2 2>/dev/null || shift ;;
        --count=*) COUNT="${1#--count=}"; shift ;;
        *)        COUNT="$1"; shift ;;
    esac
fi
ARGS+=("--count=$COUNT" "--endpoint=$ENDPOINT")

cd "$FLUTTER_DIR"
exec dart run tool/seed_marketplace.dart "${ARGS[@]}"
