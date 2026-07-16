#!/usr/bin/env bash
# Run a command (e.g. the Flutter app) against the mock Secret Service,
# so flutter_secure_storage works on a headless Linux box.
#
# Usage:
#   scripts/run-with-mock-keyring.sh flutter run -d linux
#   scripts/run-with-mock-keyring.sh --display :99 ./build/.../bundle/icp_autorun
#
# Starts a private, isolated D-Bus session (dbus-run-session) and launches the
# mock Secret Service (scripts/mock_secret_service.py) inside it. The mock
# claims the `org.freedesktop.secrets` name FIRST, before any client call can
# autostart a host gnome-keyring — so a host-installed gnome-keyring cannot
# race the mock for the name and trigger its GUI unlock prompter. (That race
# was a real bug on boxes that had gnome-keyring installed: the prompter
# blocked the e2e suite indefinitely.)
#
# Secrets persist in $MOCK_SECRET_DATA_DIR
# (default: ~/.local/share/mock-secret-service). Cleanup is automatic on exit.
#
# Requires: dbus-daemon (debian: dbus-daemon) + python3 with dbus-next.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOCK="${SCRIPT_DIR}/mock_secret_service.py"

# Resolve a Python interpreter that has dbus_next installed. On a box where the
# default `python3` is a venv without dbus_next (common on dev machines), this
# auto-discovers one (e.g. /usr/bin/python3.13) instead of failing opaquely.
# Override explicitly with MOCK_PYTHON=/path/to/python.
resolve_python() {
    local candidates=()
    if [[ -n "${MOCK_PYTHON:-}" ]]; then
        candidates+=("$MOCK_PYTHON")
    fi
    # Prefer a more-specific version, then the default. Include /usr/bin paths
    # explicitly because a venv's `python3.13` can shadow the system one that
    # actually has dbus_next installed.
    candidates+=("python3.13" "python3.12" "python3.11" "python3"
                 "/usr/bin/python3.13" "/usr/bin/python3.12" "/usr/bin/python3")
    for c in "${candidates[@]}"; do
        if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import dbus_next' >/dev/null 2>&1; then
            command -v "$c"
            return 0
        fi
    done
    echo "❌ No Python with dbus_next found. Tried: ${candidates[*]}" >&2
    echo "   Install:  $c -m pip install dbus-next" >&2
    echo "   Or set:   MOCK_PYTHON=/path/to/python" >&2
    return 1
}
PY="$(resolve_python)"

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

# IMPORTANT ORDERING: start the mock BEFORE anything else touches the secrets
# name. dbus-run-session creates an empty private bus; launching the mock
# inside it first means the mock's RequestName races against nothing — even
# if a host gnome-keyring service file is visible on this bus, autostart only
# fires when a client calls a method on the unowned name, and the mock owns
# it within ~300ms of python startup. The NameHasOwner poll below never
# triggers autostart (it's a bus-daemon call, not a name call).
DISPLAY_EXPORT="${DISPLAY_ENV[0]:-}"
exec dbus-run-session -- bash -c '
    set -euo pipefail
    '"${DISPLAY_EXPORT:+export $DISPLAY_EXPORT}"'
    "'"$PY"'" "'"$MOCK"'" 2>/tmp/mock-secret-stderr.log &
    MOCK_PID=$!
    # Wait for the mock to claim the name. NameHasOwner is a call to the bus
    # daemon itself, NOT to org.freedesktop.secrets, so it does NOT trigger
    # service autostart. 6s ceiling. Note: gdbus parses a dotted name with the
    # `string:` prefix as the literal value (e.g. `string:foo.bar`), so pass
    # the name as a plain shell-quoted string instead.
    for _ in $(seq 1 120); do
        if ! kill -0 $MOCK_PID 2>/dev/null; then
            echo "mock secret service died during startup:" >&2
            cat /tmp/mock-secret-stderr.log >&2
            exit 1
        fi
        if gdbus call -e -d org.freedesktop.DBus -o /org/freedesktop/DBus \
                -m org.freedesktop.DBus.NameHasOwner "org.freedesktop.secrets" \
                2>/dev/null | grep -q true; then
            break
        fi
        sleep 0.05
    done
    # LOUD reachability check — fails fast if the mock never claimed the name.
    gdbus call -e -d org.freedesktop.DBus -o /org/freedesktop/DBus \
        -m org.freedesktop.DBus.NameHasOwner "org.freedesktop.secrets" \
        2>/dev/null | grep -q true \
        || { echo "❌ mock Secret Service never claimed org.freedesktop.secrets" >&2
             cat /tmp/mock-secret-stderr.log >&2; exit 1; }
    echo "mock secret service: ready" >&2
    exec "$@"
' _ "$@"
