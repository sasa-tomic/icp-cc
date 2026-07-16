#!/bin/bash
# Entrypoint: runs AS the host user (UID 1000 = ubuntu), so files created on
# bind mounts are never root-owned. No privilege escalation/drop (no gosu).
# Docker socket access is granted by the supplementary group (group_add in compose).
set -euo pipefail

# Guard: target/ volume must be writable by the host user. Fail loud with the
# remediation command instead of a confusing later write failure.
mkdir -p /code/icp-cc/target
if ! touch /code/icp-cc/target/.write-test 2>/dev/null; then
	echo "ERROR: /code/icp-cc/target is not writable (owned by $(stat -c '%U:%G' /code/icp-cc/target))" >&2
	echo "Fix: docker volume rm \$(docker volume ls -q | grep target-cache) then restart" >&2
	exit 1
fi
rm -f /code/icp-cc/target/.write-test

# Set up SSH key for remote node access
if [ -f /tmp/claude-ssh/claude-code ]; then
	mkdir -p "$HOME/.ssh"
	cp /tmp/claude-ssh/claude-code "$HOME/.ssh/claude-code"
	cp /tmp/claude-ssh/claude-code.pub "$HOME/.ssh/claude-code.pub"
	chmod 700 "$HOME/.ssh"
	chmod 600 "$HOME/.ssh/claude-code"
	chmod 644 "$HOME/.ssh/claude-code.pub"
	# Configure SSH to use this key by default and auto-accept new host keys
	cat >"$HOME/.ssh/config" <<'SSHEOF'
Host *
    IdentityFile ~/.ssh/claude-code
    StrictHostKeyChecking accept-new
SSHEOF
	chmod 600 "$HOME/.ssh/config"
fi

# Clean old build artifacts (files not accessed in 1 day)
cargo sweep --time 1 --installed /code/icp-cc/target 2>/dev/null || true

# Sync Python dependencies from project if pyproject.toml exists
if [ -f /code/icp-cc/pyproject.toml ]; then
	uv sync --project /code/icp-cc 2>/dev/null || true
fi

# --- Omnigent: auto-register this container as a host ---
# Registers the container with an Omnigent server so agent sessions launched
# from the Web UI land here. Runs as a background daemon alongside whatever
# tool (claude/happy/opencode/bash) the user invoked; the host goes offline
# when the container stops (the foreground tool's exit tears down PID 1).
#
# Host name defaults to the repo (parent of agent/) basename, e.g. "icp-cc";
# override with OMNIGENT_HOST_NAME. Server URL defaults to the LAN host;
# override with OMNIGENT_SERVER_URL. Disable with OMNIGENT_AUTO_REGISTER=0.
#
# A stable host_id is seeded from the name so an ephemeral (--rm) container
# reconnects as the SAME host across restarts instead of piling up duplicates
# on the server. If the server is down the daemon retries in the background
# (never blocks the dev container); auth/perm failures are loud in the log.
OMNIGENT_SERVER_URL="${OMNIGENT_SERVER_URL:-http://192.168.0.2:6767}"
if [ "${OMNIGENT_AUTO_REGISTER:-1}" = "1" ] && command -v omnigent >/dev/null 2>&1; then
	HOST_NAME="${OMNIGENT_HOST_NAME:-$(basename "$(pwd)")}"
	OMNI_CFG_DIR="$HOME/.omnigent"
	mkdir -p "$OMNI_CFG_DIR/logs"
	if [ ! -f "$OMNI_CFG_DIR/config.yaml" ]; then
		HOST_ID="host_$(printf '%s' "$HOST_NAME" | sha256sum | cut -c1-32)"
		cat >"$OMNI_CFG_DIR/config.yaml" <<YAML
host:
  host_id: $HOST_ID
  name: $HOST_NAME
YAML
		echo "[omnigent] seeded host identity: $HOST_NAME ($HOST_ID)"
	fi
	# --non-interactive: never launch a browser login (we're headless). If the
	# server requires auth the daemon fails loud with the `omnigent login` hint
	# in host-register.log; run that interactively once to persist credentials
	# (omnigent-state volume keeps them across --rm runs).
	# PYTHONUNBUFFERED=1: stream the daemon's banner/errors to the log as they
	# happen instead of block-buffering into 4KB chunks — so a healthy connect
	# shows up immediately AND a fast fatal failure is flushed before the grace
	# check's `tail` below reads the (otherwise empty) log.
	PYTHONUNBUFFERED=1 setsid omnigent host --server "$OMNIGENT_SERVER_URL" --non-interactive \
		>"$OMNI_CFG_DIR/logs/host-register.log" 2>&1 &
	echo "[omnigent] registering host '$HOST_NAME' with $OMNIGENT_SERVER_URL (log: $OMNI_CFG_DIR/logs/host-register.log)"
	# Surface fatal registration failures WITHOUT blocking the dev container.
	# A healthy connect (or a transient retry loop) keeps the daemon alive past
	# this grace window; a fatal failure (omnigent missing, auth refused, server
	# permanently unreachable) kills it almost immediately. If it's already dead
	# we print its output to stderr so the user knows WHY the host shows offline.
	# Registration is always best-effort: the foreground tool runs regardless.
	# (We can't use $! because `setsid` forks and its parent exits at once; we
	# probe liveness with pgrep on the known command line instead.)
	sleep 3
	if ! pgrep -f "omnigent host --server" >/dev/null 2>&1; then
		echo "[omnigent] WARNING: host daemon exited during registration. Output:" >&2
		tail -n 25 "$OMNI_CFG_DIR/logs/host-register.log" >&2 2>/dev/null || true
		echo "[omnigent] (registration skipped; continuing to your tool)" >&2
	fi
fi

# --- opencode: inject model + MCP servers + variant into omnigent sessions ---
# Omnigent launches each opencode session with a private per-session
# XDG_CONFIG_HOME and SYNTHESIZES a fresh opencode.json there (model +
# permission + omnigent's own tool-relay MCP). It deliberately does NOT carry
# over the host's MCP servers (only provider entries are merged), so none of
# the user's MCP servers (plasmate/zai-vision/web-*/zread) reach the session.
#
# opencode, however, MERGES a project opencode.json from the cwd ON TOP of that
# synthesized config. So we generate /code/icp-cc/.opencode/opencode.json,
# DERIVED from the host global config (single source of truth — no committed
# secret), containing model + the host's mcp block + a default model variant.
# This injects them into EVERY opencode session here, whether launched by
# `omni opencode`, `omni run`, or the Web UI. .opencode/ is gitignored (see
# repo .gitignore) so the derived token-bearing file is never committed; it
# appears on the host working tree via the bind mount and also benefits the
# host TUI (same config the host already uses).
#
# Disable with OPENCODE_INJECT_PROJECT_CONFIG=0. Override the default variant
# with OPENCODE_MODEL_VARIANT (default: max).
if [ "${OPENCODE_INJECT_PROJECT_CONFIG:-1}" = "1" ]; then
	GLOBAL_OC="/home/ubuntu/.config/opencode/opencode.json"
	PROJ_OC_DIR="/code/icp-cc/.opencode"
	if [ -f "$GLOBAL_OC" ] && command -v python3 >/dev/null 2>&1; then
		python3 - "$GLOBAL_OC" "$PROJ_OC_DIR" "${OPENCODE_MODEL_VARIANT:-max}" <<'PY' || echo "[opencode] WARNING: project config generation failed" >&2
import json, os, sys
src, outdir, variant = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    g = json.load(open(src))
except Exception as e:
    print(f"[opencode] could not read global config {src}: {e}", file=sys.stderr)
    sys.exit(0)  # nothing to inject; continue silently
proj = {}
if g.get("model"):
    proj["model"] = g["model"]
if g.get("mcp"):
    proj["mcp"] = g["mcp"]
proj["agent"] = {"build": {"variant": variant}}
os.makedirs(outdir, exist_ok=True)
with open(os.path.join(outdir, "opencode.json"), "w") as f:
    json.dump(proj, f, indent=2)
print(f"[opencode] injected project config: model={proj.get('model')} variant={variant} mcp={len(proj.get('mcp', {}))} server(s)")
PY
	fi
fi

# Execute command as the host user (we already are ubuntu)
exec "$@"
