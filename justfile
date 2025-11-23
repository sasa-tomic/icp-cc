# Justfile for ICP-CC project
# Modern replacement for Makefile with better features and cross-platform support
#
# Install Just: https://just.systems/
# Usage: just [target] [args...]

# =============================================================================
# Global Settings
# =============================================================================

set shell := ["bash", "-euo", "pipefail", "-c"]

root := `pwd`
scripts_dir := root + "/scripts"
logs_dir := root + "/logs"
flutter_dir := root + "/apps/autorun_flutter"
api_dir := root + "/backend"

# API server runtime state
tmp_dir := root + "/.just-tmp"
api_port_file := tmp_dir + "/icp-api.port"
api_pid_file := tmp_dir + "/icp-api.pid"

# Docker compose files - completely separated environments
compose_prod := "docker compose -f docker-compose.prod.yml"
compose_dev := "docker compose -f docker-compose.dev.yml"

# =============================================================================
# Default Target
# =============================================================================

# Show help
default:
    @{{scripts_dir}}/dynamic-just-help.sh

# =============================================================================
# Build Commands
# =============================================================================

# Build all platforms
all: linux android

# Build for Linux
linux:
    @echo "==> Building Linux target..."
    {{scripts_dir}}/build_linux.sh
    cd {{flutter_dir}} && flutter build linux
    @if [ -n "${DISPLAY:-}" ]; then \
        echo "==> DISPLAY is set, running the built app..."; \
        {{flutter_dir}}/build/linux/x64/release/bundle/icp_autorun; \
    else \
        echo "==> DISPLAY not set, skipping app execution"; \
    fi

# Build for Android
android:
    @echo "==> Building Android target..."
    {{scripts_dir}}/build_android.sh
    cd {{flutter_dir}} && flutter build apk
    @if [ -d ~/sync/sasa-privatno/icp-autorun/ ]; then \
        cp -v {{flutter_dir}}/build/app/outputs/flutter-apk/app-release.apk ~/sync/sasa-privatno/icp-autorun/; \
    fi

# Build for macOS
macos:
    @echo "==> Building macOS target..."
    {{scripts_dir}}/build_macos.sh
    cd {{flutter_dir}} && flutter build macos

# Build for iOS (without code signing)
ios:
    @echo "==> Building iOS target..."
    {{scripts_dir}}/build_ios.sh
    cd {{flutter_dir}} && flutter build ios --no-codesign

# Build for Windows
windows:
    @echo "==> Building Windows target..."
    {{scripts_dir}}/build_windows.sh
    cd {{flutter_dir}} && flutter build windows

# =============================================================================
# Testing
# =============================================================================

# Run all tests (Rust + Flutter)
test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Running tests (output saved to logs/test-output.log)"
    mkdir -p "{{logs_dir}}"
    mkdir -p "{{root}}/.tmp"
    tmp_dir=$(mktemp -d "{{root}}/.tmp/just-test-XXXXXX")
    cleanup() {
        [ "$1" -ne 0 ] && echo "==> Preserving temp dir for debugging: $tmp_dir" >&2 || rm -rf "$tmp_dir"
    }
    trap 'cleanup "$?"' EXIT
    export TMPDIR="$tmp_dir" TEMP="$tmp_dir" TMP="$tmp_dir" XDG_RUNTIME_DIR="$tmp_dir"
    echo "Using temp dir: $tmp_dir"
    just rust-tests
    just flutter-tests
    echo "✅ All tests passed! Full output saved to logs/test-output.log"

# Run Rust tests and linting
rust-tests:
    @echo "==> Rust linting and tests..."
    @cargo clippy --benches --tests --all-features --quiet 2>&1 | tee {{logs_dir}}/test-output.log
    @if grep -qE "(error|warning)" {{logs_dir}}/test-output.log; then echo "❌ Rust clippy found issues!"; exit 1; fi
    @echo "✅ No clippy issues found"
    @cargo fmt --all --quiet 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if grep -qE "(error|warning)" {{logs_dir}}/test-output.log; then echo "❌ Rust formatting issues found!"; exit 1; fi
    @echo "✅ No formatting issues found"
    @cargo nextest run 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if grep -qE "\\bFAILED\\b|\\berror\\b:\\s" {{logs_dir}}/test-output.log; then echo "❌ Rust tests failed!"; exit 1; fi
    @echo "✅ All Rust tests passed"

# Run Flutter tests
flutter-tests:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Running Flutter tests with API server..."
    api_started=0
    cleanup() {
        if [ "$api_started" -eq 1 ]; then
            just api-dev-down
        fi
    }
    trap cleanup EXIT
    echo "==> Building native library for Flutter tests..."
    just linux
    just api-dev-up
    api_started=1
    # Source API environment variables
    if [ -f "{{tmp_dir}}/api-env.sh" ]; then
        source "{{tmp_dir}}/api-env.sh"
        echo "==> Using MARKETPLACE_API_PORT=$MARKETPLACE_API_PORT"
    fi
    echo "==> Running Flutter analysis..."
    cd {{flutter_dir}} && flutter analyze 2>&1 | grep -v "✅ " | tee -a {{logs_dir}}/test-output.log
    if grep -qE "(info •|warning •|error •)" {{logs_dir}}/test-output.log; then echo "❌ Flutter analysis found issues!"; exit 1; fi
    echo "✅ No Flutter analysis issues found"
    echo "==> Running Flutter tests..."
    cd {{flutter_dir}} && flutter test --reporter=github --concurrency=$(nproc) --timeout=360s 2>&1 | grep -v "✅ " | tee -a {{logs_dir}}/test-output.log
    if grep -qiE "❌ " {{logs_dir}}/test-output.log; then echo "❌ Flutter tests failed!"; exit 1; fi
    echo "✅ All Flutter tests passed"

# =============================================================================
# Development API Server (Local Cargo-based)
# =============================================================================

# Helper to get API port with error checking
_api-dev-port:
    @if [ ! -f "{{api_port_file}}" ]; then echo "❌ API server not running" >&2; exit 1; fi; cat "{{api_port_file}}"

# Start local development API server in background (port=0 for auto-assign)
api-dev-up port="0":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Starting ICP Marketplace API server"
    mkdir -p "{{tmp_dir}}"

    # Check if already running
    if [ -f "{{api_pid_file}}" ]; then
        pid=$(cat "{{api_pid_file}}")
        if kill -0 "$pid" 2>/dev/null; then
            if [ -f "{{api_port_file}}" ]; then
                api_port=$(cat "{{api_port_file}}")
                echo "==> API server already running with PID $pid on port $api_port"
                exit 0
            else
                echo "==> Warning: PID file exists but port file missing, cleaning up..."
                rm -f "{{api_pid_file}}"
            fi
        else
            echo "==> Cleaning up stale PID file..."
            rm -f "{{api_pid_file}}" "{{api_port_file}}"
        fi
    fi

    # Start server in background
    cd {{api_dir}} && PORT={{port}} cargo run --release > {{logs_dir}}/api-server.log 2>&1 &
    echo $! > {{api_pid_file}}

    # Wait for server to start and extract port from logs
    echo "==> Waiting for API server to start..."
    timeout=30
    for ((i=0; i<timeout; i++)); do
        if [ -f "{{logs_dir}}/api-server.log" ]; then
            api_port=$(grep -aoP 'listening.*?(\[::\]|127\.0\.0\.1|0\.0\.0\.0):\K\d+' {{logs_dir}}/api-server.log | tail -1 || true)
            if [ -n "$api_port" ]; then
                echo "$api_port" > {{api_port_file}}
                export MARKETPLACE_API_PORT="$api_port"
                if timeout 5 curl -s "http://127.0.0.1:$api_port/api/v1/health" >/dev/null 2>&1; then
                    echo "==> ✅ API server is healthy and ready!"
                    echo "==> API Endpoint: http://127.0.0.1:$api_port"
                    echo "==> Health Check: http://127.0.0.1:$api_port/api/v1/health"
                    echo "==> Server logs: {{logs_dir}}/api-server.log"
                    echo "export MARKETPLACE_API_PORT=$api_port" > {{tmp_dir}}/api-env.sh
                    exit 0
                fi
            fi
        fi
        sleep 1
    done
    echo "==> ❌ API server failed to start within $timeout seconds"
    echo "==> Check logs at: {{logs_dir}}/api-server.log"
    # Cleanup on failure
    if [ -f "{{api_pid_file}}" ]; then
        kill -TERM $(cat "{{api_pid_file}}") 2>/dev/null || true
        rm -f "{{api_pid_file}}" "{{api_port_file}}"
    fi
    exit 1

# Stop local development API server
api-dev-down:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Stopping API server"

    # Kill processes by port
    if [ -f "{{api_port_file}}" ]; then
        api_port=$(cat "{{api_port_file}}")
        pids=$(lsof -ti:$api_port 2>/dev/null || true)
        if [ -n "$pids" ]; then
            for pid in $pids; do
                echo "==> Cleaning up process $pid on port $api_port"
                kill -TERM "$pid" 2>/dev/null || true
                sleep 1
                kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
            done
        fi
    fi

    # Kill by PID file
    if [ -f "{{api_pid_file}}" ]; then
        pid=$(cat "{{api_pid_file}}")
        if kill -0 "$pid" 2>/dev/null; then
            echo "==> Stopping API server wrapper with PID $pid"
            pkill -P "$pid" 2>/dev/null || true
            sleep 1
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
            echo "==> ✅ API server stopped"
        fi
    fi

    rm -f "{{api_pid_file}}" "{{api_port_file}}"

# Restart local development API server
api-dev-restart: api-dev-down api-dev-up

# Show local development API server logs
api-dev-logs:
    @tail -f {{logs_dir}}/api-server.log

# Run local development API server in foreground (for debugging)
api-dev:
    @echo "==> Starting API server in development mode"
    cd {{api_dir}} && cargo run

# Build API server in release mode
api-dev-build:
    @echo "==> Building API server (release mode)"
    cd {{api_dir}} && cargo build --release
    @echo "==> ✅ API server built successfully"

# Test local development API endpoints
api-dev-test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Testing API endpoints"
    api_port=$(just _api-dev-port)
    JQ_CMD=$(command -v jq >/dev/null 2>&1 && echo "jq ." || echo "cat")
    [ "$JQ_CMD" = "cat" ] && echo "==> Note: jq not installed, showing raw JSON"

    echo "==> Testing health endpoint..."
    curl -s "http://127.0.0.1:$api_port/api/v1/health" | $JQ_CMD && echo "✅ Health check passed"

    echo "==> Testing marketplace stats..."
    curl -s "http://127.0.0.1:$api_port/api/v1/marketplace-stats" | $JQ_CMD && echo "✅ Stats endpoint passed"

    echo "==> Testing scripts listing..."
    curl -s "http://127.0.0.1:$api_port/api/v1/scripts" | $JQ_CMD && echo "✅ Scripts listing passed"

    echo "==> ✅ All endpoint tests completed"

# Reset local development API database
api-dev-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Resetting API database"
    api_port=$(just _api-dev-port)
    JQ_CMD=$(command -v jq >/dev/null 2>&1 && echo "jq ." || echo "cat")
    curl -X POST -s "http://127.0.0.1:$api_port/api/dev/reset-database" | $JQ_CMD

# =============================================================================
# Flutter Development
# =============================================================================

# Run Flutter app with local development API server
flutter-dev-local +args="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Starting Flutter app with local API server"
    api_port=$(just _api-dev-port)
    echo "==> Using API endpoint: http://127.0.0.1:$api_port"
    cd {{flutter_dir}} && flutter run -d chrome --dart-define=API_ENDPOINT=http://127.0.0.1:$api_port {{args}}

# Start Android emulator
android-emulator:
    @echo "==> Starting Android emulator..."
    {{scripts_dir}}/run_android_emulator.sh

# =============================================================================
# Docker Deployment
# =============================================================================

# Deploy to production with Docker Compose and Cloudflare Tunnel
docker-deploy-prod:
    @echo "==> Deploying to PRODUCTION with Docker Compose + Cloudflare Tunnel"
    cargo build --release
    cd {{api_dir}} && ./scripts/start-tunnel.sh

# Deploy to local development (no tunnel)
docker-deploy-dev:
    @echo "==> Deploying to DEVELOPMENT (local only)"
    cargo build --release
    cd {{api_dir}} && ./scripts/start-dev.sh

# Start production Docker containers
docker-prod-up:
    @echo "==> Starting production Docker containers"
    cd {{api_dir}} && export $(cat .env | xargs) && {{compose_prod}} up -d

# Start development Docker containers
docker-dev-up:
    @echo "==> Starting development Docker containers"
    cd {{api_dir}} && {{compose_dev}} up -d

# Stop production Docker containers
docker-prod-down:
    @echo "==> Stopping production Docker containers"
    cd {{api_dir}} && {{compose_prod}} down

# Stop development Docker containers
docker-dev-down:
    @echo "==> Stopping development Docker containers"
    cd {{api_dir}} && {{compose_dev}} down

# Stop all Docker containers (both prod and dev)
docker-all-down:
    @echo "==> Stopping all Docker containers"
    cd {{api_dir}} && {{compose_prod}} down 2>/dev/null || true
    cd {{api_dir}} && {{compose_dev}} down 2>/dev/null || true

# View production Docker logs
docker-prod-logs:
    @echo "==> Viewing production Docker logs (Ctrl+C to stop)"
    cd {{api_dir}} && {{compose_prod}} logs -f

# View development Docker logs
docker-dev-logs:
    @echo "==> Viewing development Docker logs (Ctrl+C to stop)"
    cd {{api_dir}} && {{compose_dev}} logs -f

# Check production Docker container status
docker-prod-status:
    @echo "==> Production Docker container status"
    cd {{api_dir}} && {{compose_prod}} ps

# Check development Docker container status
docker-dev-status:
    @echo "==> Development Docker container status"
    cd {{api_dir}} && {{compose_dev}} ps

# Check all Docker container status (both prod and dev)
docker-all-status:
    @echo "==> Production:"
    cd {{api_dir}} && {{compose_prod}} ps
    @echo ""
    @echo "==> Development:"
    cd {{api_dir}} && {{compose_dev}} ps

# Rebuild and restart production Docker containers
docker-prod-rebuild:
    @echo "==> Rebuilding and restarting production Docker containers"
    cd {{api_dir}} && export $(cat .env | xargs) && {{compose_prod}} up -d --build

# Rebuild and restart development Docker containers
docker-dev-rebuild:
    @echo "==> Rebuilding and restarting development Docker containers"
    cd {{api_dir}} && {{compose_dev}} up -d --build

# =============================================================================
# Maintenance
# =============================================================================

# Clean build artifacts
clean:
    @echo "==> Cleaning build artifacts..."
    rm -rf {{flutter_dir}}/android/app/src/main/jniLibs/* || true
    rm -rf {{flutter_dir}}/build || true
    rm -rf {{flutter_dir}}/linux/flutter/ephemeral || true
    rm -rf {{api_dir}}/target/debug || true

# Deep clean including dependencies
distclean: clean
    @echo "==> Deep cleaning all artifacts and dependencies..."
    rm -rf {{root}}/target || true
    rm -rf {{flutter_dir}}/.dart_tool || true
    rm -rf {{flutter_dir}}/.gradle || true
    rm -rf {{api_dir}}/target || true
