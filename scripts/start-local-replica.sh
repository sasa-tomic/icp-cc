#!/usr/bin/env bash
# Start a local dfx replica + deploy the example Poll canister, so the
# `dapps.run_poll` + `dapps.create_profile_to_vote` e2e flows can exercise a
# REAL end-to-end canister round-trip (Path B: backend direct).
#
# Usage:
#   scripts/start-local-replica.sh           # start + deploy, idempotent
#   scripts/start-local-replica.sh --check   # exit 0 if running, 1 if not
#                                             #   (do NOT start)
#
# Idempotent: if `dfx ping local` already succeeds, the replica is reused and
# only the canister deploy is re-attempted (dfx deploy is itself idempotent —
# a no-op when the wasm hasn't changed).
#
# Fails LOUD on any misconfiguration (AGENTS.md: no silent failures). If the
# replica doesn't boot within the readiness budget, exits non-zero with a
# clear message — the calling e2e suite must surface this as a test failure,
# NOT skip silently.
#
# Layout: this script MUST be self-contained — no `cd` chains, no
# `source`ing repo shells. It writes a sentinel file ($STATE_FILE) with the
# canister id + host on success, so the e2e suite can verify the pre-state
# without forking dfx again.
#
# Why `setsid` + full redirection: bash hangs on `dfx start --background`
# because pocket-ic doesn't fully detach from the persistent shell session
# (keeps stdout pipe open). Wrapping with `setsid bash -c '... </dev/null
# >log 2>&1' &` fully detaches it from the controlling terminal so the
# caller returns immediately.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLL_DIR="$ROOT/examples/icp_poll_dapp"
STATE_DIR="$ROOT/.just-tmp"
STATE_FILE="$STATE_DIR/local-replica.env"
DFX_LOG="$ROOT/logs/dfx-start.log"

mkdir -p "$STATE_DIR" "$(dirname "$DFX_LOG")"

# Expected canister id — must match
# `kLocalPollBackendCanisterId` in apps/autorun_flutter/lib/config/example_dapps.dart.
# dfx derives deterministic ids for the first non-asset canister on a fresh
# replica, so a `dfx start --clean` + `dfx deploy backend` always yields this
# exact id. If dfx ever changes its id derivation, update BOTH this constant
# AND the Dart side.
EXPECTED_BACKEND_ID="uxrrr-q7777-77774-qaaaq-cai"
EXPECTED_HOST="http://127.0.0.1:4943"

# ------------------------------------------------------------------------------
# --check: report readiness without starting anything.
# ------------------------------------------------------------------------------
if [[ "${1:-}" == "--check" ]]; then
    if (cd "$POLL_DIR" && dfx ping local >/dev/null 2>&1) \
        && grep -q "^BACKEND_CANISTER_ID=$EXPECTED_BACKEND_ID$" "$STATE_FILE" 2>/dev/null; then
        echo "local-replica: READY (sentinel: $STATE_FILE)"
        exit 0
    fi
    echo "local-replica: NOT READY (no running replica or stale sentinel)" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 1: ensure dfx is on PATH.
# ------------------------------------------------------------------------------
if ! command -v dfx >/dev/null 2>&1; then
    DFX_BIN="$HOME/.cache/data/dfx/bin/dfx"
    if [[ -x "$DFX_BIN" ]]; then
        export PATH="$HOME/.cache/data/dfx/bin:$PATH"
    else
        echo "❌ dfx not found on PATH nor at $DFX_BIN" >&2
        echo "   Install dfx (see https://internetcomputer.org/docs/current/developer-docs/setup/install/)" >&2
        exit 2
    fi
fi

# ------------------------------------------------------------------------------
# Step 2: start the replica (idempotent — skip if `dfx ping local` already OK).
# ------------------------------------------------------------------------------
needs_start=1
if (cd "$POLL_DIR" && dfx ping local >/dev/null 2>&1); then
    echo "==> dfx replica already running — reusing"
    needs_start=0
fi

if [[ "$needs_start" -eq 1 ]]; then
    echo "==> starting dfx replica (dfx start --clean --background)"
    # CRITICAL: do NOT inline `dfx start --background` here. The persistent
    # bash session hangs because pocket-ic keeps the stdout pipe open. Use
    # `setsid` to detach from the controlling terminal and fully redirect
    # stdin/stdout/stderr so the parent shell returns immediately.
    (cd "$POLL_DIR" && rm -rf .dfx && \
        setsid bash -c "dfx start --clean --background </dev/null >'$DFX_LOG' 2>&1" \
        </dev/null >/dev/null 2>&1 &)

    # Poll for readiness (dfx ping local needs >60s sometimes).
    ready=0
    for i in $(seq 1 60); do
        if (cd "$POLL_DIR" && dfx ping local >/dev/null 2>&1); then
            ready=1
            echo "==> replica ready after ${i}s"
            break
        fi
        sleep 1
    done
    if [[ "$ready" -ne 1 ]]; then
        echo "❌ dfx replica did not become ready within 60s" >&2
        echo "   see $DFX_LOG for details" >&2
        exit 3
    fi
fi

# ------------------------------------------------------------------------------
# Step 3: deploy the poll backend canister (idempotent — dfx deploy no-ops
# when the wasm hasn't changed). The frontend asset canister is intentionally
# NOT deployed (Path B doesn't need it; saves a build).
# ------------------------------------------------------------------------------
echo "==> deploying backend canister"
if ! (cd "$POLL_DIR" && dfx deploy backend >/dev/null 2>&1); then
    echo "❌ dfx deploy backend failed" >&2
    echo "   run manually: cd $POLL_DIR && dfx deploy backend" >&2
    exit 4
fi

# ------------------------------------------------------------------------------
# Step 4: verify the canister id matches the constant the app expects. If
# this fails, the app would point at the wrong canister id and the e2e flows
# would silently degrade to "Canister unreachable" UI.
# ------------------------------------------------------------------------------
actual_id="$(cd "$POLL_DIR" && dfx canister id backend 2>/dev/null | tr -d '[:space:]')"
if [[ "$actual_id" != "$EXPECTED_BACKEND_ID" ]]; then
    echo "❌ backend canister id mismatch:" >&2
    echo "   expected: $EXPECTED_BACKEND_ID" >&2
    echo "   actual:   $actual_id" >&2
    echo "   This breaks the e2e flows — the app points at $EXPECTED_BACKEND_ID." >&2
    echo "   Fix: wipe the replica state (rm -rf $POLL_DIR/.dfx) and re-run." >&2
    exit 5
fi

# ------------------------------------------------------------------------------
# Step 5: sanity-check the canister is callable (listPolls query).
# ------------------------------------------------------------------------------
if ! (cd "$POLL_DIR" && dfx canister call backend listPolls >/dev/null 2>&1); then
    echo "❌ backend.listPolls call failed — canister deployed but not responding" >&2
    exit 6
fi

# ------------------------------------------------------------------------------
# Step 6: write the sentinel state file. The e2e suite reads this in setUpAll
# to fail-fast if the pre-state is wrong (no silent skipping).
# ------------------------------------------------------------------------------
cat > "$STATE_FILE" <<EOF
# Written by scripts/start-local-replica.sh — do not edit.
# Source with: set -a; source $STATE_FILE; set +a
BACKEND_CANISTER_ID=$actual_id
HOST=$EXPECTED_HOST
REPLICA_VERSION=$(dfx --version 2>&1 | head -1 | tr -d '\n')
EOF

echo "✅ local replica ready"
echo "   backend canister: $actual_id"
echo "   host:             $EXPECTED_HOST"
echo "   sentinel:         $STATE_FILE"
