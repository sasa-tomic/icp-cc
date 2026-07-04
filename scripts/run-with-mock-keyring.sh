#!/usr/bin/env bash
# Run a command (e.g. the Flutter app) against the mock Secret Service,
# so flutter_secure_storage works on a headless Linux box without gnome-keyring.
#
# Usage:
#   scripts/run-with-mock-keyring.sh flutter run -d linux
#   scripts/run-with-mock-keyring.sh --display :99 ./build/.../bundle/icp_autorun
#
# Starts a private D-Bus session (dbus-run-session), launches the mock secret
# service inside it, then runs your command. Secrets persist in
# $MOCK_SECRET_DATA_DIR (default: a temp dir). Clean up is automatic on exit.
#
# Requires: dbus-run-session (debian: dbus-daemon), python3 + dbus-next.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOCK="${SCRIPT_DIR}/mock_secret_service.py"

# --display VALUE  : forward DISPLAY into the inner shell (for Xvfb)
DISPLAY_ENV=()
if [[ "${1:-}" == "--display" ]]; then
    DISPLAY_ENV=("DISPLAY=${2}")
    shift 2
fi

if [[ $# -eq 0 ]]; then
    echo "usage: $0 [--display :N] <command...>" >&2
    exit 2
fi

cleanup() {
    [[ -n "${MOCK_PID:-}" ]] && kill "$MOCK_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

dbus-run-session -- bash -c "
    set -euo pipefail
    ${DISPLAY_ENV[0]:+export ${DISPLAY_ENV[0]}}
    python3 '${MOCK}' &
    MOCK_PID=\$!
    # give the mock a moment to claim its D-Bus name
    for i in {1..30}; do
        if ! kill -0 \$MOCK_PID 2>/dev/null; then
            echo 'mock secret service died' >&2; exit 1
        fi
        sleep 0.1
        # gsettings/libsecret reachability check via a tiny dbus call
        if gdbus call -e -d org.freedesktop.secrets \
                      -o /org/freedesktop/secrets \
                      -m org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
            break
        fi
    done
    echo 'mock secret service: ready' >&2
    exec \"\$@\"
" _ "$@"

