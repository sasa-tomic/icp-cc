# Claude Code Docker Setup for ICP-CC Project

This directory contains a complete Docker setup for running Claude Code safely with the ICP-CC (ICP Autorun/Script Marketplace) project. The container provides isolation while giving Claude full access to the project, effectively replacing the need for `--dangerously-skip-permissions` on the host system.

## Quick Start

**Run Claude Code:**
   ```bash
   ./run-container.sh claude
   ```

## Files Overview

- **`Dockerfile`** - Customized for ICP-CC project with Flutter, Rust, ICP, and Cloudflare Workers tooling
- **`docker-compose.yml`** - Container orchestration with volumes and networking for ICP-CC
- **`run-container.sh`** - Wrapper script for easy usage with ICP-CC workflow

## Architecture

This setup is specifically tailored for the ICP-CC project, providing:
- **Rust** - Latest stable with wasm32 target for ICP development
- **Flutter SDK** - With web support for the Flutter app
- **Internet Computer SDK** - dfx for ICP development
- **Pocket IC** - Local ICP testing
- **Cloudflare Wrangler** - For Workers API development
- **Just build system** - Modern build tool used by ICP-CC project
- **Node.js 22** - For Cloudflare Workers and frontend tooling
- **Claude Code** - Installed globally

## Usage Examples

### Basic Usage
```bash
# Start Claude Code with full project access
./run-container.sh claude

# Start Happy Coder
./run-container.sh happy

# Start a bash shell
./run-container.sh bash

# Rebuild the image first
./run-container.sh claude --rebuild

# Run in background
./run-container.sh claude --detach
```

### ICP-CC Development Workflow
```bash
# Run ICP-CC tests
./run-container.sh claude "just test"

# Build for Linux
./run-container.sh claude "just linux"

# Start Cloudflare Workers for local development
./run-container.sh claude "just cloudflare-local-up"

# Start Flutter app with local API
./run-container.sh claude "just flutter-local"
```

### Custom Commands
```bash
# Run a shell in the container
./run-container.sh bash

# Run specific commands
./run-container.sh claude "cargo test"
./run-container.sh claude "cd apps/autorun_flutter && flutter doctor"
./run-container.sh claude "just cloudflare-local-test"
```

## What's Included in the Container

### Development Tools
- **Rust** - Latest stable with wasm32 target
- **Flutter SDK** - Latest stable with web support enabled
- **Node.js 22** - With npm and Cloudflare Wrangler
- **Python 3** - With UV package manager
- **Just** - Modern build system
- **Claude Code** - Installed globally via npm

### ICP-CC Specific Tools
- **Internet Computer SDK** - dfx for ICP development
- **Pocket IC** - Local ICP testing environment
- **Cargo tools** - make, nextest, wasm-pack
- **Cloudflare Wrangler** - For Workers API development
- **Project dependencies** - Pre-built and cached

### Safety Features
- **Non-root user** - Container runs as 'ubuntu' user
- **Isolated filesystem** - Only project directory is mounted
- **Network isolation** - Bridge network with port mapping
- **Cached volumes** - Separate caches for dependencies

## Port Mapping

The container exposes these ports for ICP-CC development:
- **8787** - Cloudflare Workers API
- **3000** - Flutter web development server

## Benefits vs Host `--dangerously-skip-permissions`

| Feature | Host Dangerous Mode | Docker Container |
|---------|-------------------|------------------|
| **Safety** | ❌ Full host access | ✅ Container isolation |
| **Cleanup** | ❌ Manual cleanup | ✅ Delete container |
| **Reproducibility** | ❌ Host-dependent | ✅ Consistent environment |
| **Resource Limits** | ❌ Unlimited | ✅ Configurable |
| **Networking** | ❌ Full access | ✅ Bridge network |

## Volumes

The setup uses several volumes for caching and persistence:

- **`cargo-cache`** - Cargo registry cache
- **`rustup-cache`** - Rust toolchain cache
- **`home-cache`** - User home directory cache
- **Project mount** - Your entire project directory at `/code`

## Troubleshooting

### Common Issues

1. **Permission denied on script**
   ```bash
   chmod +x run-container.sh
   # If that fails due to sandbox restrictions, run:
   bash run-container.sh
   ```

2. **Docker not running**
   ```bash
   # Start Docker daemon
   sudo systemctl start docker
   ```

3. **Port conflicts**
   ```bash
   # Check what's using port 8787 or 3000
   lsof -i :8787
   lsof -i :3000
   # Or modify docker-compose.yml to use different ports
   ```

### Debug Mode

To run the container with more debugging:
```bash
docker-compose -f docker-compose.yml up agent
```

### Rebuilding

If you make changes to the project:
```bash
./run-container.sh claude --rebuild
```

Or completely rebuild without cache:
```bash
docker-compose build --no-cache
```

## ICP-CC Development Workflow

### Daily Development
```bash
# 1. Start Claude Code
./run-container.sh claude

# 2. Run tests
just test

# 3. Start local development environment
just cloudflare-local-up
just flutter-local
```

### Building and Testing
```bash
# Build specific platforms
just linux
just android
just macos

# Run full test suite
just test

# Test Cloudflare Workers endpoints
just cloudflare-local-test
```

### API Development
```bash
# Start local Cloudflare Workers
just cloudflare-local-up

# Initialize database
just cloudflare-local-init

# Test API endpoints
curl http://localhost:8787/api/v1/health
```

## Security Notes

- ✅ Container runs as non-root user
- ✅ Only project directory is mounted
- ✅ Network access limited to bridge network
- ✅ No access to host system files or credentials
- ✅ Container can be easily recreated if compromised

## Advanced Usage

### Custom Docker Compose Files

```bash
# Use different compose file
./run-container.sh -f docker-compose.dev.yml
```

### Running Multiple Services

The docker-compose setup can be extended to include additional services like databases, redis, etc.

### Resource Limits

Add resource limits to docker-compose.yml:
```yaml
services:
  agent:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
        reservations:
          cpus: '1.0'
          memory: 2G
```

This Docker setup provides a safe, reproducible environment for running Claude Code with full ICP-CC project access while maintaining security through container isolation.