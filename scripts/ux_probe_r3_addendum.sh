#!/usr/bin/env bash
# Launcher for the ICP Autorun desktop app under the mock Secret Service +
# Xvfb, with a guaranteed-clean teardown.
#
# UX Round-3 ADDENDUM verification harness. Launches the REAL app (release
# bundle) against the committed mock Secret Service so flutter_secure_storage
# (libsecret) works on this keyring-less box, then screenshots the live GTK
# window via ImageMagick `import -window root`.
#
# We CANNOT synthesize taps on the GTK window (no xdotool/tmux on this box), so
# this harness proves the LAUNCH + secure-storage-readiness path empirically:
#   - wizard renders the profile-creation FORM (not the WU-S2 blocking panel),
#     proving SecureStorageReadiness == StorageReady under the mock;
#   - the app's libsecret probe round-trips into the mock's secrets.json,
#     proving the real libsecret <-> mock path works for the running app.
#
# Usage:
#   scripts/ux_probe_r3_addendum.sh launch  <screenshot.png> [run_seconds]
#   scripts/ux_probe_r3_addendum.sh shot    <screenshot.png>
#   scripts/ux_probe_r3_addendum.sh kill
#
# Env (optional overrides):
#   UX_APP_BINARY  (default: release bundle)
#   UX_DATA_DIR    (default: /tmp/icp-data)
#   UX_API_ENDPOINT (default: http://127.0.0.1:0  -> unreachable, no marketplace)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BINARY="${UX_APP_BINARY:-$REPO/apps/autorun_flutter/build/linux/x64/release/bundle/icp_autorun}"
DATA_DIR="${UX_DATA_DIR:-/tmp/icp-data}"
MOCK_DIR="$DATA_DIR/mock-secret"
API_ENDPOINT="${UX_API_ENDPOINT:-http://127.0.0.1:0}"
PIDFILE="$DATA_DIR/.app.pid"
LOGFILE="$DATA_DIR/app.log"

export XDG_DATA_HOME="$DATA_DIR"
export MOCK_SECRET_DATA_DIR="$MOCK_DIR"
export PYTHONPATH="/home/ubuntu/.local/lib/python3.13/site-packages"
export DISPLAY=:99
export PUBLIC_API_ENDPOINT="$API_ENDPOINT"

mkdir -p "$DATA_DIR" "$MOCK_DIR"

cmd_launch() {
  local shot="${1:?screenshot path required}"
  local secs="${2:-12}"

  if [[ ! -x "$APP_BINARY" ]]; then
    echo "ERROR: app binary not found/executable: $APP_BINARY" >&2
    exit 1
  fi
  if ! pgrep -x Xvfb >/dev/null 2>&1; then
    echo "ERROR: Xvfb not running on :99. Start with: Xvfb :99 -screen 0 1440x900x24 &" >&2
    exit 1
  fi

  # Kill any previous instance tracked by the pidfile.
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill -TERM "-$(cat "$PIDFILE")" 2>/dev/null || true
    sleep 1
  fi

  # Launch the app + mock together in a NEW session (process group) so we can
  # tear the whole tree down by PGID. Fully detached from this shell.
  #
  # NOTE: we deliberately do NOT pass `--display :99` to run-with-mock-keyring.sh
  # — that flag has a quoting bug (sets DISPLAY to the literal "DISPLAY=:99",
  # which GTK rejects with "cannot open display"). Instead we export DISPLAY=:99
  # here (done at the top of this script) and let the wrapper inherit it.
  setsid bash -c "
    exec '$REPO/scripts/run-with-mock-keyring.sh' '$APP_BINARY'
  " >"$LOGFILE" 2>&1 &
  local pgid=$!
  echo "$pgid" >"$PIDFILE"
  echo "Launched app (PGID=$pgid). Waiting ${secs}s for it to settle..." >&2

  sleep "$secs"
  cmd_shot "$shot"
  echo "Screenshot: $shot" >&2
  echo "App log tail:" >&2
  tail -n 15 "$LOGFILE" >&2 || true
}

cmd_shot() {
  local shot="${1:?screenshot path required}"
  DISPLAY=:99 import -window root "$shot"
  identify "$shot" >&2
}

cmd_kill() {
  if [[ -f "$PIDFILE" ]]; then
    local pgid
    pgid="$(cat "$PIDFILE")"
    kill -TERM "-$pgid" 2>/dev/null || true
    sleep 1
    kill -KILL "-$pgid" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "Killed app process group $pgid" >&2
  fi
}

case "${1:-}" in
  launch) shift; cmd_launch "$@";;
  shot)   shift; cmd_shot "$@";;
  kill)   cmd_kill;;
  *) echo "usage: $0 {launch <png> [secs]|shot <png>|kill}" >&2; exit 2;;
esac
