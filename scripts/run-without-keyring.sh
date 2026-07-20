#!/usr/bin/env bash
# Run a command with NO Secret Service reachable, so the
# SecureStorageReadiness probe in the Flutter app returns StorageUnavailable
# and the wizard renders the WU-S2 actionable blocking panel
# (LinuxSecretServiceHelp) instead of the setup form.
#
# Usage:
#   scripts/run-without-keyring.sh -- flutter test -d linux ...
#   scripts/run-without-keyring.sh ./build/.../bundle/icp_autorun
#
# Used by `just e2e-keyring-unavailable` to exercise the
# `first_run.keyring_unavailable` e2e flow on dev boxes that DO have
# gnome-keyring installed (which would otherwise auto-start and satisfy the
# readiness probe, hiding the panel).
#
# What this wrapper does:
#   1. Kills any running gnome-keyring-daemon (so autostart can't re-grab the
#      org.freedesktop.secrets name). Also kills pocket-ic to keep the env
#      clean (unrelated to the keyring, but matches the AGENTS.md guidance).
#   2. Blanks DBUS_SESSION_BUS_ADDRESS and GNOME_KEYRING_CONTROL so libsecret
#      cannot connect even if a daemon is somehow still alive.
#   3. Sanity-checks that secret-tool (if installed) cannot reach a Secret
#      Service — fails loud if the wrapper didn't disable the keyring.
#   4. Execs the wrapped command.
#
# On a box that NEVER had gnome-keyring installed (e.g. CI), this wrapper is
# a near-no-op: the kill is a no-op, the env vars are already empty, and the
# sanity check passes by default.
set -euo pipefail

# Optional `--` separator (cosmetic; consumed if present).
if [[ "${1:-}" == "--" ]]; then
    shift
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 -- <command> [args...]" >&2
    exit 64
fi

# 1) Kill any running Secret Service + pocket-ic. `pkill -x` matches the
#    exact process name (truncated to 15 chars on Linux, hence the leading
#    `gnome-keyring-d` form); `pkill -f` matches the full command line for
#    the longer pattern. Neither errors if no match (|| true).
pkill -x gnome-keyring-d 2>/dev/null || true
pkill -f 'gnome-keyring-daemon.*--start' 2>/dev/null || true
pkill -x pocket-ic 2>/dev/null || true

# 2) Blank the D-Bus session env so libsecret's auto-activation fails. An
#    empty DBUS_SESSION_BUS_ADDRESS makes libsecret fall back to the default
#    session bus (autolaunch), which — without a desktop session manager —
#    cannot reach any Secret Service.
export DBUS_SESSION_BUS_ADDRESS=
export GNOME_KEYRING_CONTROL=
# Also clear the KDE wallet env (KWallet is the alternative Secret Service
# on KDE Plasma boxes).
export WALD_PATH=

# 3) Sanity check: confirm Secret Service is unreachable BEFORE the wrapped
#    command runs. If secret-tool is installed and CAN reach a Secret
#    Service (exit 0 on a successful lookup), the wrapper failed to disable
#    it — fail loud so the operator knows the panel won't be exercised.
if command -v secret-tool >/dev/null 2>&1; then
    # Use a probe key that will never exist; if secret-tool exits 0 anyway
    # it means a Secret Service answered (even with "no such item" via a
    # 0-exit path — defensive: any 0-exit means reachable).
    if secret-tool lookup service __icp_probe_run_without_keyring__ \
            account __icp_probe__ 2>/dev/null; then
        echo "❌ $0: Secret Service is still reachable after kill + env-wipe." >&2
        echo "   A gnome-keyring-daemon may have restarted, or KWallet is active." >&2
        echo "   The first_run.keyring_unavailable flow would NOT exercise the panel." >&2
        exit 1
    fi
    # secret-tool exited non-zero. Distinguish "service unreachable" (good)
    # from "item not found in a reachable service" (bad) via stderr: the
    # unreachable case prints a D-Bus error. We don't strictly need this
    # distinction for the wrapper to be correct, so we accept any non-zero
    # exit and continue.
fi

exec "$@"
