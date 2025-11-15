# Justfile for ICP-CC project
# Modern replacement for Makefile with better features and cross-platform support
#
# Install Just: https://just.systems/
# Usage: just [target] [args...]

# Global settings
set shell := ["bash", "-euo", "pipefail", "-c"]
root := `pwd`
scripts_dir := root + "/scripts"
logs_dir := root + "/logs"
flutter_dir := root + "/apps/autorun_flutter"
api_dir := root + "/poem-backend"

# Platform detection
platform := if `uname` == "Darwin" { "macos" } else if `uname` == "Linux" { "linux" } else { "unknown" }

# API server configuration
api_port_file := "/tmp/icp-api.port"
api_pid_file := "/tmp/icp-api.pid"

# =============================================================================
# Default Target
# =============================================================================

# Default target - show help
default:
   @{{scripts_dir}}/dynamic-just-help.sh

# =============================================================================
# Quick Start / Common Commands
# =============================================================================

# Build all platforms
all: linux android

# Run all tests (Rust + Flutter)
test:
    @echo "==> Running tests (output saved to logs/test-output.log)"
    @mkdir -p {{logs_dir}}
    @just rust-tests
    @just flutter-tests
    @echo "✅ All tests passed! Full output saved to logs/test-output.log"

# Clean build artifacts
clean:
    @echo "==> Cleaning build artifacts..."
    rm -rf {{flutter_dir}}/android/app/src/main/jniLibs/* || true
    rm -rf {{flutter_dir}}/build || true
    rm -f {{flutter_dir}}/build/linux/x64/*/bundle/lib/libicp_core.* || true
    rm -rf {{flutter_dir}}/linux/flutter/ephemeral || true
    rm -rf {{api_dir}}/target/debug || true

# Deep clean including dependencies
distclean: clean
    @echo "==> Deep cleaning all artifacts and dependencies..."
    rm -rf {{root}}/target || true
    rm -rf {{flutter_dir}}/.dart_tool || true
    rm -rf {{flutter_dir}}/.gradle || true
    rm -rf {{api_dir}}/target || true

# =============================================================================
# API Server Management (Local Cargo)
# =============================================================================

# Start the Poem API server in background (optionally specify port)
api-up port="0":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Starting ICP Marketplace API server"

    # Check if already running
    if [ -f "{{api_pid_file}}" ]; then
        pid=$(cat "{{api_pid_file}}")
        if kill -0 "$pid" 2>/dev/null; then
            api_port=$(cat "{{api_port_file}}")
            echo "==> API server already running with PID $pid on port $api_port"
            exit 0
        fi
    fi

    # Determine port to use (0 = auto-assign, or use specified port)
    PORT={{port}}

    # Start server in background with port specification
    cd {{api_dir}} && PORT=$PORT cargo run --release > {{logs_dir}}/api-server.log 2>&1 &
    echo $! > {{api_pid_file}}

    # Wait for server to start and extract the actual port from logs
    echo "==> Waiting for API server to start..."
    timeout=30
    elapsed=0
    api_port=""
    while [ $elapsed -lt $timeout ]; do
        if [ -f "{{logs_dir}}/api-server.log" ]; then
            # Extract port from log line like "listening addr=socket://127.0.0.1:8080"
            # Look for the "listening" line specifically
            # Use -a to treat binary files (with ANSI codes) as text
            api_port=$(grep -aoP 'listening.*?127\.0\.0\.1:\K\d+' {{logs_dir}}/api-server.log | tail -1 || true)
            if [ -n "$api_port" ]; then
                echo "$api_port" > {{api_port_file}}
                # Test if server is responding
                if timeout 5 curl -s "http://127.0.0.1:$api_port/api/v1/health" >/dev/null 2>&1; then
                    echo "==> ✅ API server is healthy and ready!"
                    echo "==> API Endpoint: http://127.0.0.1:$api_port"
                    echo "==> Health Check: http://127.0.0.1:$api_port/api/v1/health"
                    echo "==> Server logs: {{logs_dir}}/api-server.log"
                    exit 0
                fi
            fi
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "==> ❌ API server failed to start within $timeout seconds"
    echo "==> Check logs at: {{logs_dir}}/api-server.log"
    exit 1

# Stop the API server
api-down:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Stopping API server"

    # Clean up processes by port first (before deleting port file)
    if [ -f "{{api_port_file}}" ]; then
        api_port=$(cat "{{api_port_file}}")
        pids=$(lsof -ti:$api_port 2>/dev/null || true)
        if [ -n "$pids" ]; then
            for pid in $pids; do
                echo "==> Cleaning up process $pid on port $api_port"
                kill -TERM "$pid" 2>/dev/null || true
                sleep 1
                # Force kill if still running
                if kill -0 "$pid" 2>/dev/null; then
                    kill -KILL "$pid" 2>/dev/null || true
                fi
            done
        fi
    fi

    # Clean up by PID and kill child processes
    if [ -f "{{api_pid_file}}" ]; then
        pid=$(cat "{{api_pid_file}}")
        if kill -0 "$pid" 2>/dev/null; then
            echo "==> Stopping API server wrapper with PID $pid"
            # Kill all child processes first
            pkill -P "$pid" 2>/dev/null || true
            sleep 1
            # Then kill the parent
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                echo "==> Force killing API server"
                kill -KILL "$pid" 2>/dev/null || true
            fi
            echo "==> ✅ API server stopped"
        else
            echo "==> API server process not found"
        fi
        rm -f "{{api_pid_file}}"
        rm -f "{{api_port_file}}"
    else
        echo "==> No API server PID file found"
        # Still remove port file if it exists
        rm -f "{{api_port_file}}"
    fi

# Restart the API server
api-restart: api-down api-up

# Show API server logs
api-logs:
    @tail -f {{logs_dir}}/api-server.log

# Test API endpoints
api-test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Testing API endpoints"

    # Get the API port
    if [ ! -f "{{api_port_file}}" ]; then
        echo "❌ API server not running (no port file found)"
        exit 1
    fi
    api_port=$(cat "{{api_port_file}}")

    # Check if jq is available
    if command -v jq >/dev/null 2>&1; then
        JQ_CMD="jq ."
    else
        JQ_CMD="cat"
        echo "==> Note: jq not installed, showing raw JSON"
    fi

    echo "==> Testing health endpoint..."
    if curl -s "http://127.0.0.1:$api_port/api/v1/health" | $JQ_CMD; then
        echo "✅ Health check passed"
    else
        echo "❌ Health check failed"
    fi

    echo "==> Testing marketplace stats..."
    if curl -s "http://127.0.0.1:$api_port/api/v1/marketplace-stats" | $JQ_CMD; then
        echo "✅ Stats endpoint passed"
    else
        echo "❌ Stats endpoint failed"
    fi

    echo "==> Testing scripts listing..."
    if curl -s "http://127.0.0.1:$api_port/api/v1/scripts" | $JQ_CMD; then
        echo "✅ Scripts listing passed"
    else
        echo "❌ Scripts listing failed"
    fi

    echo "==> ✅ All endpoint tests completed"

# Build API server in release mode
api-build:
    @echo "==> Building API server (release mode)"
    cd {{api_dir}} && cargo build --release
    @echo "==> ✅ API server built successfully"

# Run API server in foreground (for development)
api-dev:
    @echo "==> Starting API server in development mode"
    cd {{api_dir}} && cargo run

# Reset API database (development only)
api-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Resetting API database"

    # Get the API port
    if [ ! -f "{{api_port_file}}" ]; then
        echo "❌ API server not running (no port file found)"
        exit 1
    fi
    api_port=$(cat "{{api_port_file}}")

    if command -v jq >/dev/null 2>&1; then
        curl -X POST -s "http://127.0.0.1:$api_port/api/dev/reset-database" | jq .
    else
        curl -X POST -s "http://127.0.0.1:$api_port/api/dev/reset-database"
    fi

# =============================================================================
# Flutter App Builds
# =============================================================================

# Platform-specific builds (Flutter)
linux:
    @echo "==> Building Linux target..."
    {{scripts_dir}}/build_linux.sh
    cd {{flutter_dir}} && flutter build linux
    @if [ -n "${DISPLAY:-}" ]; then \
        echo "==> DISPLAY is set, running the built app..."; \
        if [ -f {{flutter_dir}}/build/linux/x64/release/bundle/icp_autorun ]; then \
            {{flutter_dir}}/build/linux/x64/release/bundle/icp_autorun; \
        else \
            echo "ERROR: Built executable not found at expected path"; \
            exit 1; \
        fi; \
    else \
        echo "==> DISPLAY not set, skipping app execution"; \
    fi

android:
    @echo "==> Building Android target..."
    {{scripts_dir}}/build_android.sh
    cd {{flutter_dir}} && flutter build apk
    @echo "==> Copying APK to sync directory..."
    if [ -d ~/sync/sasa-privatno/icp-autorun/ ]; then cp -v {{flutter_dir}}/build/app/outputs/flutter-apk/app-release.apk ~/sync/sasa-privatno/icp-autorun/; fi

android-emulator:
    @echo "==> Starting Android emulator..."
    {{scripts_dir}}/run_android_emulator.sh

macos:
    @echo "==> Building macOS target..."
    {{scripts_dir}}/build_macos.sh
    cd {{flutter_dir}} && flutter build macos

ios:
    @echo "==> Building iOS target..."
    {{scripts_dir}}/build_ios.sh
    cd {{flutter_dir}} && flutter build ios --no-codesign

windows:
    @echo "==> Building Windows target..."
    {{scripts_dir}}/build_windows.sh
    cd {{flutter_dir}} && flutter build windows

# =============================================================================
# Testing (Internal)
# =============================================================================

# Internal Rust testing target
rust-tests:
    @echo "==> Rust linting and tests..."
    @cargo clippy --benches --tests --all-features --quiet 2>&1 | tee {{logs_dir}}/test-output.log
    @if grep -E "(error|warning)" {{logs_dir}}/test-output.log > /dev/null; then echo "❌ Rust clippy found issues!"; exit 1; fi
    @echo "✅ No clippy issues found"
    @cargo fmt --all --quiet 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if grep -E "(error|warning)" {{logs_dir}}/test-output.log > /dev/null; then echo "❌ Rust formatting issues found!"; exit 1; fi
    @echo "✅ No formatting issues found"
    @cargo nextest run 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if grep -E "\\bFAILED\\b|\\berror\\b:\\s" {{logs_dir}}/test-output.log > /dev/null; then echo "❌ Rust tests failed!"; exit 1; fi
    @echo "✅ All Rust tests passed"

# Internal Flutter testing target
flutter-tests:
    @echo "==> Running Flutter tests with API server..."
    @just api-up
    @echo "==> Running Flutter analysis..."
    @cd {{flutter_dir}} && flutter analyze 2>&1 | grep -v "✅ " | tee -a {{logs_dir}}/test-output.log
    @if grep -E "(info •|warning •|error •)" {{logs_dir}}/test-output.log > /dev/null; then echo "❌ Flutter analysis found issues!"; exit 1; fi
    @echo "✅ No Flutter analysis issues found"
    @echo "==> Running Flutter tests..."
    @cd {{flutter_dir}} && flutter test --reporter=github --concurrency=$(nproc) --timeout=360s 2>&1 | grep -v "✅ " | tee -a {{logs_dir}}/test-output.log
    @if grep -qiE "❌ " {{logs_dir}}/test-output.log > /dev/null; then echo "❌ Flutter tests failed!"; exit 1; fi
    @echo "✅ All Flutter tests passed"
    @just api-down

# =============================================================================
# Flutter App Development
# =============================================================================

# Run Flutter app with local API server
flutter-local +args="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Starting Flutter app with local API server"

    # Get the API port
    if [ ! -f "{{api_port_file}}" ]; then
        echo "❌ API server not running. Start it with: just api-up"
        exit 1
    fi
    api_port=$(cat "{{api_port_file}}")

    echo "==> Using API endpoint: http://127.0.0.1:$api_port"
    cd {{flutter_dir}} && flutter run -d chrome --dart-define=API_ENDPOINT=http://127.0.0.1:$api_port {{args}}

# Run Flutter app with production environment
flutter-production +args="":
    @echo "==> Starting Flutter app with production environment"
    cd {{flutter_dir}} && flutter run -d chrome --dart-define=API_ENDPOINT=https://api.icp-marketplace.example.com {{args}}

# =============================================================================
# Docker Deployment (API Server)
# =============================================================================

# Compose file selection
compose_prod := "docker compose -f docker-compose.yml -f docker-compose.prod.yml"
compose_dev := "docker compose -f docker-compose.yml -f docker-compose.dev.yml"

# --- Main Deployment Commands ---

# Deploy to production with Docker Compose and Cloudflare Tunnel
docker-deploy-prod:
    @echo "==> Deploying to PRODUCTION with Docker Compose + Cloudflare Tunnel"
    cd {{api_dir}} && ./scripts/start-tunnel.sh

# Deploy to local development (no tunnel)
docker-deploy-dev:
    @echo "==> Deploying to DEVELOPMENT (local only)"
    cd {{api_dir}} && ./scripts/start-dev.sh

# Default deploy (use prod)
docker-deploy: docker-deploy-prod

# --- Container Management ---

# Start production Docker containers
docker-up-prod:
    @echo "==> Starting production Docker containers"
    cd {{api_dir}} && export $$(cat .env | xargs) && {{compose_prod}} up -d

# Start development Docker containers
docker-up-dev:
    @echo "==> Starting development Docker containers"
    cd {{api_dir}} && {{compose_dev}} up -d

# Stop production Docker containers
docker-down-prod:
    @echo "==> Stopping production Docker containers"
    cd {{api_dir}} && {{compose_prod}} down

# Stop development Docker containers
docker-down-dev:
    @echo "==> Stopping development Docker containers"
    cd {{api_dir}} && {{compose_dev}} down

# Stop all Docker containers (both prod and dev)
docker-down:
    @echo "==> Stopping all Docker containers"
    cd {{api_dir}} && {{compose_prod}} down && {{compose_dev}} down

# --- Logs & Status ---

# View production Docker logs
docker-logs-prod:
    @echo "==> Viewing production Docker logs (Ctrl+C to stop)"
    cd {{api_dir}} && {{compose_prod}} logs -f

# View development Docker logs
docker-logs-dev:
    @echo "==> Viewing development Docker logs (Ctrl+C to stop)"
    cd {{api_dir}} && {{compose_dev}} logs -f

# View Docker logs (default to dev)
docker-logs: docker-logs-dev

# --- Rebuild Commands ---

# Rebuild and restart production Docker containers
docker-rebuild-prod:
    @echo "==> Rebuilding and restarting production Docker containers"
    cd {{api_dir}} && export $$(cat .env | xargs) && {{compose_prod}} up -d --build

# Rebuild and restart development Docker containers
docker-rebuild-dev:
    @echo "==> Rebuilding and restarting development Docker containers"
    cd {{api_dir}} && {{compose_dev}} up -d --build

# --- Status Commands ---

# Check production Docker container status
docker-status-prod:
    @echo "==> Checking production Docker container status"
    cd {{api_dir}} && {{compose_prod}} ps

# Check development Docker container status
docker-status-dev:
    @echo "==> Checking development Docker container status"
    cd {{api_dir}} && {{compose_dev}} ps

# Check all Docker container status
docker-status:
    @echo "==> Checking all Docker container status"
    @echo "Production:"
    cd {{api_dir}} && {{compose_prod}} ps
    @echo ""
    @echo "Development:"
    cd {{api_dir}} && {{compose_dev}} ps

# =============================================================================
# Help and Information
# =============================================================================
