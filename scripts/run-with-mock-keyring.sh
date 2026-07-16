#!/usr/bin/env bash
# Run a command (e.g. the Flutter app) against a working Secret Service on a
# headless Linux box, so flutter_secure_storage can persist keys.
#
# Usage:
#   scripts/run-with-mock-keyring.sh flutter run -d linux
#   scripts/run-with-mock-keyring.sh --display :99 ./build/.../bundle/icp_autorun
#
# Two backends are auto-selected by what's installed:
#
#   1. REAL gnome-keyring (preferred when installed) — unlocked with an empty
#      password via stdin so the GUI prompter never fires. This is the
#      production-realistic Secret Service path: libsecret talks to the real
#      daemon, exercising the same code the user's desktop session would.
#
#   2. MOCK Secret Service (scripts/mock_secret_service.py) — a tiny
#      dev/CI-only implementation of the org.freedesktop.secrets D-Bus
#      interface, used on containers WITHOUT gnome-keyring (e.g. CI images).
#      Secrets are plain JSON — never use in production.
#
# In BOTH cases we start a PRIVATE D-Bus session (dbus-run-session) so the
# test/CI Secret Service is fully isolated from any host/session bus.
#
# Requires: dbus-daemon. Plus EITHER gnome-keyring-daemon OR python3+dbus-next.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOCK="${SCRIPT_DIR}/mock_secret_service.py"

# --display VALUE  : forward DISPLAY into the inner shell (for Xvfb)
DISPLAY_ARG=()
if [[ "${1:-}" == "--display" ]]; then
    DISPLAY_ARG=("$1" "$2")
    shift 2
fi

if [[ $# -eq 0 ]]; then
    echo "usage: $0 [--display :N] <command...>" >&2
    exit 2
fi

# Pick the backend. gnome-keyring is preferred (production-realistic).
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    BACKEND="gnome-keyring"
else
    BACKEND="mock"
    # Resolve a Python interpreter with dbus_next. venv pythons often lack it,
    # so include /usr/bin paths explicitly.
    if [[ -n "${MOCK_PYTHON:-}" ]] && "$MOCK_PYTHON" -c 'import dbus_next' >/dev/null 2>&1; then
        PY="$MOCK_PYTHON"
    else
        PY=""
        for c in python3.13 python3.12 python3.11 python3 \
                 /usr/bin/python3.13 /usr/bin/python3.12 /usr/bin/python3; do
            if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import dbus_next' >/dev/null 2>&1; then
                PY="$c"; break
            fi
        done
    fi
    if [[ -z "$PY" ]]; then
        echo "❌ Mock backend needs python3+dbus-next. Install dbus-next, set MOCK_PYTHON, or install gnome-keyring." >&2
        exit 1
    fi
fi

# Helper that brings up the chosen backend and waits for the secrets name.
# Called INSIDE the dbus-run-session by the inner bash below.
bring_up_backend() {
    if [[ "$BACKEND" == "gnome-keyring" ]]; then
        # Unlock an empty keyring via stdin so the GUI prompter never fires.
        # CRITICAL: use an ISOLATED $XDG_DATA_HOME so gnome-keyring creates a
        # FRESH empty-password keyring in our temp dir, never touching the
        # user's real ~/.local/share/keyrings/login.keyring (which has a real
        # password and would trigger the GUI prompter).
        export XDG_DATA_HOME="${MOCK_KEYRING_DATA_DIR:-/tmp/icp-keyring-$$}"
        mkdir -p "$XDG_DATA_HOME/keyrings"
        eval "$(echo -n "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null)"
    else
        # Launch the mock — it claims org.freedesktop.secrets directly.
        "$PY" "$MOCK" &
    fi
    # Poll for the secrets name to be reachable. 6s ceiling — fails LOUD below
    # if neither backend came up.
    for _ in $(seq 1 60); do
        if gdbus call -e -d org.freedesktop.secrets -o /org/freedesktop/secrets \
                -m org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    echo "❌ Secret Service (org.freedesktop.secrets) never came up (backend=$BACKEND)" >&2
    return 1
}

# Export so the inner bash -c can call it.
export -f bring_up_backend
export BACKEND MOCK PY

# Forward DISPLAY if given.
DISPLAY_EXPORT=()
if [[ "${#DISPLAY_ARG[@]}" -eq 2 ]]; then
    DISPLAY_EXPORT=("DISPLAY=${DISPLAY_ARG[1]}")
fi

# Run inside an isolated dbus session. We use `bash -c` to wire up the backend,
# then `exec "$@"` to hand control to the user's command (preserving PID/sigs).
exec dbus-run-session -- env "${DISPLAY_EXPORT[@]}" bash -c '
    set -euo pipefail
    bring_up_backend
    echo "secret service: ready (backend='"$BACKEND"')" >&2
    exec "$@"
' _ "$@"
