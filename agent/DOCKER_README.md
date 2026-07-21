# AI Coding Agent Docker Setup for ICP-CC Project

This directory contains a complete Docker setup for running AI coding agents (Claude Code, Happy Coder, OpenCode) safely with the ICP-CC (ICP Autorun/Script Marketplace) project. The container provides isolation while giving the AI agent full access to the project.

## Quick Start

**Run Claude Code:**
```bash
./run-container.sh claude
```

**Run Happy Coder:**
```bash
./run-container.sh happy
```

**Run OpenCode:**
```bash
./run-container.sh opencode
```

**Run Omnigent:**
```bash
./run-container.sh omni
```

## Files Overview

- **`Dockerfile`** - Customized for ICP-CC project with Flutter, Rust, ICP tooling
- **`docker-compose.yml`** - Container orchestration with volumes and networking
- **`run-container.sh`** - Wrapper script for easy usage
- **`entrypoint.sh`** - Container entrypoint with permission fixes
- **`git-hooks/`** - Git hooks for the container environment

## Architecture

This setup provides:
- **Rust 1.91** - Latest stable with wasm32 target for ICP development
- **Flutter SDK** - With web support for the Flutter app
- **Internet Computer SDK** - dfx for ICP development
- **Pocket IC** - Local ICP testing
- **Node.js 22** - For frontend tooling
- **Python 3** - With UV package manager and virtual environment
- **Just** - Build system used by ICP-CC project
- **Claude Code** - Installed globally via npm
- **Happy Coder** - Installed globally via npm
- **OpenCode** - Installed via official installer
- **Omnigent** - Installed via `uv tool` (the `omni`/`omnigent` CLI)
- **Docker CLI & Compose** - For running containers from within the container
- **PostgreSQL client** - For database operations

## Usage Examples

### Basic Usage
```bash
# Start Claude Code with full project access
./run-container.sh claude

# Start Happy Coder
./run-container.sh happy

# Start OpenCode
./run-container.sh opencode

# Start a bash shell
./run-container.sh bash

# Run without rebuilding (--no-build)
./run-container.sh claude --no-build

# Run in background
./run-container.sh claude --detach

# Run with a specific name (for concurrent agents)
./run-container.sh -n agent1 claude
```

### ICP-CC Development Workflow
```bash
# Run ICP-CC tests
./run-container.sh claude "just test"

# Build for Linux
./run-container.sh claude "just linux"

# Start Flutter app with local API
./run-container.sh claude "just flutter-local"
```

### Custom Commands
```bash
# Run specific commands in the container
./run-container.sh claude "cargo test"
./run-container.sh claude "flutter doctor"
./run-container.sh bash "just build"
```

## Omnigent Host Auto-Registration

The container automatically registers itself as an [Omnigent](https://omnigent.ai) **cloud sandbox host** on startup, so agent sessions launched from the Omnigent Web UI run inside this container. Registration happens in the background alongside whichever tool you invoke (`claude`/`happy`/`opencode`/`bash`); the host goes offline when the container stops.

- **Server**: `http://192.168.0.2:6767` (override with `OMNIGENT_SERVER_URL`)
- **Host name**: the repo basename, e.g. `icp-cc` (override with `OMNIGENT_HOST_NAME`)
- **Disable**: `OMNIGENT_AUTO_REGISTER=0`
- **Logs**: `~/.omnigent/logs/host-register.log` inside the container

A stable host id is derived from the name, so an ephemeral (`--rm`) container reconnects as the same host across restarts. Host identity + credentials persist in the `omnigent-state` volume.

If the server requires authentication, the background daemon fails loud with an `omnigent login` hint in the log. Run this once interactively to persist credentials:

```bash
./run-container.sh bash
# inside the container:
omnigent login --server http://192.168.0.2:6767
```

## opencode Config & Credential Injection

When opencode is launched through Omnigent (Web UI / `omni opencode`), Omnigent
runs it with a private per-session config that hides your global one — so none
of your host MCP servers reach the session. Separately, provider credentials are
masked by the container's `home-cache` volume (opencode reads keys from
`$XDG_DATA_HOME/opencode/auth.json`, which the volume hides), causing opencode to
silently fall back to its built-in default model `glm-5v-turbo`.

The container's entrypoint fixes both, **derived from your host config at runtime
(no committed secrets)**:

1. **Credential sync** — copies your host `~/.local/share/opencode/auth.json`
   into the `$XDG_DATA_HOME` location opencode actually reads, so your own
   providers/models authenticate (instead of falling back to `glm-5v-turbo`).
2. **Config injection** — generates `opencode.json` (model + full `mcp` block +
   `variant`) from your host `~/.config/opencode/opencode.json`, written to both
   plausible session working dirs (`/home/ubuntu` and the repo), so opencode
   merges it on top of Omnigent's synthesized config.
3. **Skills / agents / commands injection** — copies your host
   `~/.config/opencode/{skills,agents,commands}` into the same `.opencode/` dirs,
   since Omnigent's privatized config hides those too. (Skills under
   `~/.claude/skills/` already survive — a fixed path Omnigent doesn't hide.)
   **Plugins are not injected**: Omnigent replaces your plugin with its own policy
   bridge regardless, a known limitation.

Knobs (set in `docker-compose.yml` or override at `docker compose run`):

- `OPENCODE_INJECT_PROJECT_CONFIG=1` — set `0` to skip config injection.
- `OPENCODE_MODEL_VARIANT=max` — default model variant for the `build` agent.

The repo copy (`.opencode/opencode.json`) is gitignored; it appears on the host
working tree via the bind mount and also benefits the host TUI. The home copy is
container-only (ephemeral, regenerated each start). See
[`REUSE_GUIDE.md`](REUSE_GUIDE.md) for the full mechanism.

## What's Included in the Container

### Development Tools
- **Rust 1.91** - Latest stable with wasm32 target
- **Flutter SDK** - Latest stable with web support enabled
- **Node.js 22** - With npm
- **Python 3** - With pip, venv, and UV package manager
- **Claude Code** - Installed globally via npm
- **Happy Coder** - Installed globally via npm
- **OpenCode** - Installed via official installer
- **Omnigent** - Installed via `uv tool`
- **Docker CLI & Compose** - For running containers from within the container

### Project-Specific Tools
- **Internet Computer SDK** - dfx for ICP development
- **Pocket IC** - Local ICP testing environment
- **Cargo tools** - make, nextest, wasm-pack, sqlx-cli
- **Just** - Modern build system
- **PostgreSQL client** - For database operations
- **Android NDK (host-mounted)** - r27+ for cross-compiling `libicp_core.so`
  (incl. the rquickjs cdylib). **Not baked into the image** (~2 GB); provided
  read-only from the host's `~/Android` via the volume mount below. When the
  host has an NDK at `~/Android/Sdk/ndk/<version>`,
  `scripts/common.sh::setup_android_ndk_env` auto-detects it inside the
  container. Build with `./scripts/build_android.sh` (see
  `docs/build-native.md`). On a host without `~/Android`, install the NDK
  first (`sdkmanager "ndk;27.0.12077973"`).

### Safety Features
- **Non-root user** - Container runs as 'ubuntu' user
- **Isolated filesystem** - Only project directory is mounted
- **Network isolation** - Bridge network with port mapping
- **Cached volumes** - Separate caches for dependencies

## Volumes

The setup uses several volumes for caching and persistence:

- **`cargo-cache`** - Cargo registry cache
- **`rustup-cache`** - Rustup toolchain cache
- **`home-cache`** - Home directory cache (npm, uv, etc.)
- **`target-cache`** - Build artifacts (per-project)
- **Project mount** - Your entire project directory at `/code/icp-cc`
- **Android SDK + NDK (read-only)** - Host's `~/Android` mounted at
  `/home/ubuntu/Android:ro`; `ANDROID_HOME=/home/ubuntu/Android/Sdk`. Drives
  the Android cross-compile (`scripts/build_android.sh`) when the host has an
  NDK installed. Not present on hosts without `~/Android`.
- **Docker socket** - Mounted at `/var/run/docker.sock` for Docker-in-Docker access
- **Config mounts** - `~/.claude`, `~/.happy`, `~/.opencode` for AI tool configs

## Port Mapping

The container exposes these ports for ICP-CC development:
- **3000** - Flutter web development server

## Running Multiple Agents Concurrently

The script supports running multiple agents in parallel using unique project names:

```bash
# Terminal 1: Start Claude Code
./run-container.sh claude

# Terminal 2: Start OpenCode (will use icp-cc-agent-2)
./run-container.sh opencode

# Or explicitly name them:
./run-container.sh -n claude1 claude
./run-container.sh -n opencode1 opencode
```

## Troubleshooting

### Common Issues

1. **Permission denied on script**
   ```bash
   chmod +x run-container.sh
   # If that fails due to sandbox restrictions, run:
   bash run-container.sh claude
   ```

2. **Docker not running**
   ```bash
   # Start Docker daemon
   sudo systemctl start docker
   ```

3. **Port conflicts**
   ```bash
   # Check what's using port 3000
   lsof -i :3000
   # Or modify docker-compose.yml to use different ports
   ```

### Rebuilding

If you make changes to the project:
```bash
./run-container.sh claude  # Rebuilds by default
```

Or completely rebuild without cache:
```bash
docker compose -f agent/docker-compose.yml build --no-cache
```

## Development Workflow

### Daily usage:
```bash
./run-container.sh claude
```

### Running tests:
```bash
./run-container.sh claude "just test"
```

### Building:
```bash
./run-container.sh claude "just linux"
```

### Cleanup:
```bash
# Stop and remove container
docker compose -p icp-cc-agent-1 -f agent/docker-compose.yml down

# Remove cached volumes (if needed)
docker volume rm icp-cc-agent-1_cargo-cache icp-cc-agent-1_rustup-cache icp-cc-agent-1_home-cache
```

## Security Notes

- Container runs as non-root user
- Only project directory is mounted
- Network access limited to bridge network
- No access to host system files or credentials
- Container can be easily recreated if compromised
- AI tool configs are mounted read-only from host
