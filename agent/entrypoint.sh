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

# --- opencode: sync host credentials so custom providers authenticate ---
# opencode reads provider API keys from $XDG_DATA_HOME/opencode/auth.json.
# Here XDG_DATA_HOME=/home/ubuntu/.cache/data (set for dfx caches), but the
# host's real auth.json is bind-mounted at ~/.local/share/opencode/auth.json
# (compose volume). opencode — and omnigent's per-session auth copy (it sources
# from the same $XDG_DATA_HOME path, opencode_native_bridge.py) — look under
# .cache/data, find nothing, and CANNOT authenticate custom providers (e.g.
# zai-coding-plan/glm-5.2). opencode then silently falls back to its built-in
# default model (glm-5v-turbo). Copy the credentials into the expected location
# so every opencode session (direct container path AND omnigent sessions) can
# use the user's own providers/models. Best-effort: skip silently if absent.
OC_AUTH_SRC="/home/ubuntu/.local/share/opencode/auth.json"
OC_AUTH_DST="${XDG_DATA_HOME:-/home/ubuntu/.local/share}/opencode/auth.json"
if [ -f "$OC_AUTH_SRC" ] && [ "$OC_AUTH_SRC" != "$OC_AUTH_DST" ]; then
	mkdir -p "$(dirname "$OC_AUTH_DST")"
	cp -f "$OC_AUTH_SRC" "$OC_AUTH_DST" && echo "[opencode] synced provider credentials -> $OC_AUTH_DST"
fi

# --- opencode: inject model + MCP servers + variant into omnigent sessions ---
# opencode loads config in TWO layers: a GLOBAL one ($XDG_CONFIG_HOME/opencode/
# opencode.json) and a PROJECT one (the first opencode.json / .opencode found by
# walking UP from the working directory). Omnigent privatizes the GLOBAL layer
# only: it sets a per-session XDG_CONFIG_HOME and writes a synthesized config
# there (model OMITTED, permission:ask, omnigent's own tool-relay MCP, your
# provider entries merged). The omitted model is why we re-add it here; the
# synthesized mcp is why only the omnigent relay shows up without our injection.
# (Credentials must ALSO be synced — see the block above — or opencode can't
# authenticate the configured provider and falls back to glm-5v-turbo anyway.)
#
# Omnigent does NOT touch the PROJECT layer — opencode always walks the real cwd
# at startup, so a project config there merges ON TOP of omnigent's synthesized
# global. We exploit that seam.
#
# The catch: opencode's cwd is the SESSION'S WORKSPACE, which defaults to
# /home/ubuntu (the home dir) for Web-UI sessions — NOT the repo at /code/icp-cc
# (different directory trees). A project config placed only at /code/icp-cc is
# invisible to a home-cwd session. So we write the derived config to BOTH
# plausible session cwds: /home/ubuntu (Web-UI default + `omni opencode` from
# home) and /code/icp-cc/.opencode (`omni opencode` from the repo + host TUI).
#
# All derived from the host global config (single source of truth — no committed
# secret). The repo copy is gitignored (.opencode/ in repo .gitignore); the home
# copy is container-only (ephemeral, regenerated each start). Disable with
# OPENCODE_INJECT_PROJECT_CONFIG=0; override the variant with
# OPENCODE_MODEL_VARIANT (default: max).
if [ "${OPENCODE_INJECT_PROJECT_CONFIG:-1}" = "1" ]; then
	GLOBAL_OC="/home/ubuntu/.config/opencode/opencode.json"
	if [ -f "$GLOBAL_OC" ] && command -v python3 >/dev/null 2>&1; then
		python3 - "$GLOBAL_OC" "${OPENCODE_MODEL_VARIANT:-max}" \
			/home/ubuntu/opencode.json \
			/code/icp-cc/.opencode/opencode.json <<'PY' || echo "[opencode] WARNING: project config generation failed" >&2
import json, os, sys
src, variant = sys.argv[1], sys.argv[2]
targets = sys.argv[3:]
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
for t in targets:
    os.makedirs(os.path.dirname(t) or ".", exist_ok=True)
    with open(t, "w") as f:
        json.dump(proj, f, indent=2)
print(f"[opencode] injected project config: model={proj.get('model')} variant={variant} mcp={len(proj.get('mcp', {}))} server(s) -> {len(targets)} location(s)")
PY
	fi

	# Surface host skills/agents/commands that omnigent's privatized XDG hides.
	# opencode discovers these from a project `.opencode/` (cwd walk), so copying
	# them into the same two session-cwd dirs as the config makes them visible in
	# omnigent sessions. (Plain markdown instruction files — no secrets.) Note
	# ~/.claude/skills/ is a fixed non-XDG path that omnigent does NOT hide, so
	# skills living only there survive without this. Best-effort: never blocks.
	for sub in skills agents commands; do
		src_dir="/home/ubuntu/.config/opencode/$sub"
		[ -d "$src_dir" ] || continue
		mkdir -p "/home/ubuntu/.opencode/$sub" "/code/icp-cc/.opencode/$sub"
		if cp -af "$src_dir/." /home/ubuntu/.opencode/$sub/ 2>/dev/null \
			&& cp -af "$src_dir/." /code/icp-cc/.opencode/$sub/ 2>/dev/null; then
			echo "[opencode] injected $sub -> 2 location(s)"
		else
			echo "[opencode] WARNING: $sub copy incomplete (non-fatal)" >&2
		fi
	done
fi

# Execute command as the host user (we already are ubuntu)
exec "$@"
