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
	setsid omnigent host --server "$OMNIGENT_SERVER_URL" --non-interactive \
		>"$OMNI_CFG_DIR/logs/host-register.log" 2>&1 &
	echo "[omnigent] registering host '$HOST_NAME' with $OMNIGENT_SERVER_URL (log: $OMNI_CFG_DIR/logs/host-register.log)"
fi

# Execute command as the host user (we already are ubuntu)
exec "$@"
