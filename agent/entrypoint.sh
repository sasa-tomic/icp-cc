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

# Execute command as the host user (we already are ubuntu)
exec "$@"
