#!/usr/bin/env bash
# Seed the marketplace backend so e2e flows can exercise pagination +
# purchase paths.
#
# Usage:
#   scripts/seed-marketplace.sh [N]            # bulk-seed N free scripts (default 25)
#   scripts/seed-marketplace.sh 30
#   scripts/seed-marketplace.sh --purge        # delete all bulk_seed + paid_seed first
#   scripts/seed-marketplace.sh --paid         # upload one paid-seed script (slug
#                                              # 'paid-seed-script', price $4.99)
#
# Wraps `dart run apps/autorun_flutter/tool/seed_marketplace.dart`. Reads
# the backend port from $MARKETPLACE_API_PORT (exported by `just api-dev-up`)
# or $ROOT/.just-tmp/icp-api.port (written by `just api-dev-up`). Idempotent
# — running it twice with the same N uploads exactly N scripts total (skips
# already-seeded indices); --paid skips upload if the paid seed exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLUTTER_DIR="$ROOT/apps/autorun_flutter"

# Resolve the backend port the same way the e2e harness does. The justfile
# recipe writes the port to $ROOT/.just-tmp/icp-api.port (api_port_file :=
# tmp_dir + "/icp-api.port"; tmp_dir := root + "/.just-tmp"). Accept the
# legacy $ROOT/backend/.api-dev-port location too in case a stale doc
# references it.
if [[ -z "${MARKETPLACE_API_PORT:-}" ]]; then
    for PORT_FILE in "$ROOT/.just-tmp/icp-api.port" "$ROOT/backend/.api-dev-port"; do
        if [[ -f "$PORT_FILE" ]]; then
            # File format: MARKETPLACE_API_PORT=NNNNN
            MARKETPLACE_API_PORT="$(grep -E '^MARKETPLACE_API_PORT=' "$PORT_FILE" \
                | head -1 | cut -d= -f2)"
            break
        fi
    done
fi
if [[ -z "${MARKETPLACE_API_PORT:-}" ]]; then
    echo "❌ $0: MARKETPLACE_API_PORT not set and no port file at" >&2
    echo "   $ROOT/.just-tmp/icp-api.port or $ROOT/backend/.api-dev-port." >&2
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
        --paid)   ARGS+=("--paid"); shift ;;
        --clean)  ARGS+=("--clean"); COUNT="${2:-$COUNT}"; shift 2 2>/dev/null || shift ;;
        --count=*) COUNT="${1#--count=}"; shift ;;
        *)        COUNT="$1"; shift ;;
    esac
fi
# When --paid or --purge was the first arg, the dart tool ignores --count
# (paid-seed path uploads a single script; purge path doesn't seed). Pass
# --count anyway for the default bulk-seed path.
if [[ " ${ARGS[*]} " != *" --paid "* ]] && [[ " ${ARGS[*]} " != *" --purge "* ]]; then
    ARGS+=("--count=$COUNT")
fi
ARGS+=("--endpoint=$ENDPOINT")

cd "$FLUTTER_DIR"
exec dart run tool/seed_marketplace.dart "${ARGS[@]}"
