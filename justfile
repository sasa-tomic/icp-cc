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
cloudflare_dir := root + "/cloudflare-api"
agent_dir := root + "/agent"

# Platform detection
platform := if `uname` == "Darwin" { "macos" } else if `uname` == "Linux" { "linux" } else { "unknown" }

# Cloudflare configuration
cloudflare_port := "8787"
cloudflare_health_url := "http://localhost:" + cloudflare_port + "/api/v1/health"
cloudflare_test_pid := "/tmp/wrangler-test.pid"

# =============================================================================
# Default Target
# =============================================================================

# Default target - show help
default:
   @{{scripts_dir}}/dynamic-just-help.sh

# =============================================================================
# Utility Functions
# =============================================================================

# Wait for Cloudflare Workers to be healthy
wait-for-cloudflare-internal timeout="30":
    #!/usr/bin/env bash
    set -euo pipefail
    timeout_val="{{timeout}}"
    elapsed=0
    while [ $elapsed -lt $timeout_val ]; do
        if timeout 5 curl -s "{{cloudflare_health_url}}" >/dev/null 2>&1; then
            echo "==> ✅ Cloudflare Workers is healthy and ready!"
            echo "==> API Endpoint: http://localhost:{{cloudflare_port}}"
            echo "==> Health Check: {{cloudflare_health_url}}"
            exit 0
        fi
        echo "==> Waiting for server... ($elapsed/$timeout_val seconds)"
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "==> ❌ Cloudflare Workers failed to start within $timeout_val seconds"
    exit 1

# Stop Cloudflare Workers by PID or port
_stop-cloudflare-workers:
    #!/usr/bin/env bash
    set -euo pipefail

    # Stop by PID if file exists
    if [ -f "{{cloudflare_test_pid}}" ]; then
        pid=$(cat "{{cloudflare_test_pid}}")
        if kill -0 "$pid" 2>/dev/null; then
            echo "==> Stopping Cloudflare Workers with PID $pid"
            kill -TERM "$pid"
            sleep 2
            if kill -0 "$pid" 2>/dev/null; then
                echo "==> Force killing Cloudflare Workers with PID $pid"
                kill -KILL "$pid"
            fi
            echo "==> ✅ Cloudflare Workers stopped"
        else
            echo "==> Cloudflare Workers process $pid not found"
        fi
        rm -f "{{cloudflare_test_pid}}"
    fi

    # Clean up any remaining wrangler processes on the port
    pids=$(lsof -ti:{{cloudflare_port}} 2>/dev/null || true)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if ps -p "$pid" -o command= | grep -q "wrangler dev"; then
                echo "==> Cleaning up additional wrangler process $pid"
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
    fi

# =============================================================================
# Main Targets
# =============================================================================

# =============================================================================
# Build Targets
# =============================================================================

# Build all platforms
all: linux android

# Platform-specific builds
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
# Lua Script Validation
# =============================================================================



# =============================================================================
# Testing
# =============================================================================

test:
    @echo "==> Running tests (output saved to logs/test-output.log)"
    @mkdir -p {{logs_dir}}
    @just _rust-tests
    @just _flutter-tests
    @echo "✅ All tests passed! Full output saved to logs/test-output.log"

# Internal Rust testing target
_rust-tests:
    @echo "==> Rust linting and tests..."
    @cargo clippy --benches --tests --all-features --quiet 2>&1 | tee {{logs_dir}}/test-output.log
    @if grep -E "(error|warning)" {{logs_dir}}/test-output.log > /dev/null; then echo "❌ Rust clippy found issues!"; exit 1; fi
    @echo "✅ No clippy issues found"
    @cargo fmt --all --quiet 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if grep -E "(error|warning)" {{logs_dir}}/test-output.log > /dev/null; then echo "❌ Rust formatting issues found!"; exit 1; fi
    @echo "✅ No formatting issues found"
    @cargo nextest run 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if grep -E "(FAILED|error)" {{logs_dir}}/test-output.log > /dev/null; then echo "❌ Rust tests failed!"; exit 1; fi
    @echo "✅ All Rust tests passed"



# Internal Flutter testing target
_flutter-tests:
    @echo "==> Running Flutter tests with Cloudflare Workers..."
    @just test-with-cloudflare

# Run Flutter tests with Cloudflare Workers (includes Lua validation)
test-with-cloudflare:
    @echo "==> Cleaning up any existing test databases..."
    @{{scripts_dir}}/test_db_manager.sh cleanup
    @echo "==> Starting Cloudflare Workers for tests..."
    @just cloudflare-test-up
    @echo "==> Generating Cloudflare Workers types..."
    @just cloudflare-types
    @echo "==> Validating Lua example scripts..."
    @{{scripts_dir}}/validation/validate_lua.sh 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if [ $$? -ne 0 ]; then echo "❌ Lua script validation failed!"; exit 1; fi
    @echo "==> Running Flutter analysis..."
    @cd {{flutter_dir}} && flutter analyze 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if grep -E "(info •|warning •|error •)" {{logs_dir}}/test-output.log > /dev/null; then echo "❌ Flutter analysis found issues!"; exit 1; fi
    @echo "✅ No Flutter analysis issues found"
    @echo "==> Running Flutter tests..."
    @cd {{flutter_dir}} && flutter test --concurrency=$(nproc) --timeout=360s 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if grep -qiE "(FAIL|ERROR)" {{logs_dir}}/test-output.log > /dev/null; then echo "❌ Flutter tests failed!"; exit 1; fi
    @echo "✅ All Flutter tests passed"
    @just cloudflare-test-down

# =============================================================================
# Cleanup
# =============================================================================

# Clean build artifacts
clean:
    @echo "==> Cleaning build artifacts..."
    rm -rf {{flutter_dir}}/android/app/src/main/jniLibs/* || true
    rm -rf {{flutter_dir}}/build || true
    rm -f {{flutter_dir}}/build/linux/x64/*/bundle/lib/libicp_core.* || true
    rm -rf {{flutter_dir}}/linux/flutter/ephemeral || true

# Deep clean including dependencies
distclean: clean
    @echo "==> Deep cleaning all artifacts and dependencies..."
    rm -rf {{root}}/target || true
    rm -rf {{flutter_dir}}/.dart_tool || true
    rm -rf {{flutter_dir}}/.gradle || true

# =============================================================================
# Cloudflare Workers Deployment
# =============================================================================

# Setup Cloudflare CLI and build deployment tools
server-setup:
    @echo "==> Setting up Cloudflare Workers tools"
    @if command -v wrangler >/dev/null 2>&1; then \
        echo "==> ✅ Wrangler CLI already installed"; \
    else \
        echo "==> Installing Wrangler CLI..."; \
        npm install -g wrangler || { echo "❌ Failed to install Wrangler CLI. Please install manually: npm install -g wrangler"; exit 1; }; \
    fi
    @echo "==> Building Rust deployment tool"
    cd {{root}}/server-deploy && cargo build --release

# Deploy to Cloudflare with flexible arguments
server +args="":
    cd {{root}}/server-deploy && cargo run --bin server-deploy -- {{args}}

# Deploy to Cloudflare with flexible arguments
# Usage: just server-deploy --target local|prod [additional args]
server-deploy +args="":
    @echo "==> Deploying ICP Script Marketplace to Cloudflare Workers"
    cd {{root}}/server-deploy && cargo run --bin server-deploy -- deploy {{args}}

# Test Cloudflare deployment configuration
# Usage: just server-test --target local|prod [additional args]
server-test +args="":
    @echo "==> Testing Cloudflare deployment configuration"
    cd {{root}}/server-deploy && cargo run --bin server-deploy -- test {{args}}

# Show Cloudflare configuration
# Usage: just server-config --target local|prod
server-config +args="":
    @echo "==> Showing Cloudflare configuration"
    cd {{root}}/server-deploy && cargo run --bin server-deploy -- config {{args}}

# Bootstrap fresh Cloudflare instance
# Usage: just server-bootstrap --target local|prod [additional args]
server-bootstrap +args="":
    @echo "==> Bootstrapping fresh Cloudflare Workers instance"
    cd {{root}}/server-deploy && cargo run --bin server-deploy -- bootstrap {{args}}

# Initialize Cloudflare configuration
# Usage: just server-init --target local|prod [additional args]
server-init +args="":
    @echo "==> Initializing Cloudflare configuration"
    cd {{root}}/server-deploy && cargo run --bin server-deploy -- init {{args}}


# =============================================================================
# Local Development Environment
# =============================================================================

# Start Cloudflare Workers for testing with process management
cloudflare-test-up:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Starting Cloudflare Workers with process isolation for tests"

    # Check if running in container environment
    if [[ -f "/.dockerenv" ]]; then
        echo "==> Container environment detected - using process isolation"

        # Setup test environment
        echo "==> Setting up test database..."
        TEST_DB_NAME=$({{scripts_dir}}/test_db_manager.sh create "default")
        export TEST_DB_NAME
        echo "==> Using test database: $TEST_DB_NAME"

        # Use wrangler manager script for fail-fast process management
        exec {{agent_dir}}/wrangler-manager.sh start

    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        echo "==> Docker detected - running in container with process isolation"

        # Start the development container
        cd "{{root}}" && docker compose -f {{agent_dir}}/docker-compose.yml up -d agent

        # Execute wrangler start inside container
        cd "{{root}}" && docker compose -f {{agent_dir}}/docker-compose.yml exec -T agent {{agent_dir}}/wrangler-manager.sh start

    else
        echo "==> ❌ NEITHER CONTAINER NOR DOCKER AVAILABLE"
        echo "==> ❌ FAIL FAST - Cannot ensure proper isolation and cleanup"
        echo "==> ❌ Either run inside container or provide Docker"
        exit 1
    fi

# Stop Cloudflare Workers process and cleanup test database
cloudflare-test-down:
    @echo "==> Stopping Cloudflare Workers process..."
    @if [[ -f "/.dockerenv" ]]; then \
        echo "==> Container environment detected - stopping wrangler process"; \
        {{agent_dir}}/wrangler-manager.sh stop || echo "⚠️  Wrangler process was not running"; \
    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then \
        echo "==> Docker detected - stopping wrangler process in container"; \
        cd "{{root}}" && docker compose -f {{agent_dir}}/docker-compose.yml exec -T agent {{agent_dir}}/wrangler-manager.sh stop || echo "⚠️  Wrangler process was not running"; \
        cd "{{root}}" && docker compose -f {{agent_dir}}/docker-compose.yml stop agent || echo "⚠️  Agent container was not running"; \
    else \
        echo "⚠️  Neither container nor Docker available - cannot stop wrangler cleanly"; \
    fi
    @echo "==> Cleaning up test database..."
    @{{scripts_dir}}/test_db_manager.sh cleanup
    @echo "==> Cloudflare Workers process stopped and test database cleaned up"

# Show local Cloudflare Workers process logs
cloudflare-local-logs:
    @if [[ -f "/.dockerenv" ]]; then \
        echo "==> Showing Cloudflare Workers process logs"; \
        {{agent_dir}}/wrangler-manager.sh logs; \
    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then \
        echo "==> Showing Cloudflare Workers process logs from container"; \
        cd "{{root}}" && docker compose -f {{agent_dir}}/docker-compose.yml exec -T agent {{agent_dir}}/wrangler-manager.sh logs; \
    else \
        echo "❌ Neither container nor Docker available - cannot show logs"; \
        exit 1; \
    fi

# Reset local Cloudflare Workers environment (wipes all data)
cloudflare-local-reset:
    @if [[ -f "/.dockerenv" ]]; then \
        echo "==> Resetting local Cloudflare Workers environment (wipes all data)"; \
        cd {{cloudflare_dir}} && wrangler d1 execute --config wrangler.local.jsonc icp-marketplace-test --command="DELETE FROM scripts;" || echo "Database already empty"; \
        cd {{cloudflare_dir}} && wrangler d1 execute --config wrangler.local.jsonc icp-marketplace-test --command="DELETE FROM reviews;" || echo "Database already empty"; \
        cd {{cloudflare_dir}} && wrangler d1 execute --config wrangler.local.jsonc icp-marketplace-test --command="DELETE FROM script_stats;" || echo "Database already empty"; \
        echo "==> Local Cloudflare Workers environment reset complete"; \
    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then \
        echo "==> Resetting local Cloudflare Workers environment (wipes all data)"; \
        cd "{{root}}" && docker compose -f {{agent_dir}}/docker-compose.yml exec -T agent bash -c 'cd {{cloudflare_dir}} && wrangler d1 execute --config wrangler.local.jsonc icp-marketplace-test --command="DELETE FROM scripts;"' || echo "Database already empty"; \
        cd "{{root}}" && docker compose -f {{agent_dir}}/docker-compose.yml exec -T agent bash -c 'cd {{cloudflare_dir}} && wrangler d1 execute --config wrangler.local.jsonc icp-marketplace-test --command="DELETE FROM reviews;"' || echo "Database already empty"; \
        cd "{{root}}" && docker compose -f {{agent_dir}}/docker-compose.yml exec -T agent bash -c 'cd {{cloudflare_dir}} && wrangler d1 execute --config wrangler.local.jsonc icp-marketplace-test --command="DELETE FROM script_stats;"' || echo "Database already empty"; \
        echo "==> Local Cloudflare Workers environment reset complete"; \
    else \
        echo "❌ Neither container nor Docker available - cannot reset database"; \
        exit 1; \
    fi

# Initialize local Cloudflare Workers database
cloudflare-local-init:
    @if [[ -f "/.dockerenv" ]]; then \
        echo "==> Initializing local Cloudflare Workers database"; \
        cd {{cloudflare_dir}} && wrangler d1 execute --config wrangler.local.jsonc icp-marketplace-test --file=migrations/0001_initial_schema.sql; \
        echo "==> Database initialized successfully"; \
    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then \
        echo "==> Initializing local Cloudflare Workers database"; \
        cd "{{root}}" && docker compose -f {{agent_dir}}/docker-compose.yml exec -T agent bash -c 'cd {{cloudflare_dir}} && wrangler d1 execute --config wrangler.local.jsonc icp-marketplace-test --file=migrations/0001_initial_schema.sql'; \
        echo "==> Database initialized successfully"; \
    else \
        echo "❌ Neither container nor Docker available - cannot initialize database"; \
        exit 1; \
    fi

# Test local Cloudflare Workers endpoints
cloudflare-local-test:
    @echo "==> Testing Cloudflare Workers endpoints"
    @echo "==> Testing health endpoint..."
    @curl -s {{cloudflare_health_url}} | jq . || echo "Health check failed"
    @echo "==> Testing marketplace stats..."
    @curl -s http://localhost:{{cloudflare_port}}/api/v1/marketplace-stats | jq . || echo "Stats endpoint failed"
    @echo "==> Testing featured scripts..."
    @curl -s http://localhost:{{cloudflare_port}}/api/v1/scripts/featured | jq . || echo "Featured scripts failed"
    @echo "==> Testing search endpoint..."
    @curl -s -X POST -H "Content-Type: application/json" -d '{"query":"test","limit":5}' http://localhost:{{cloudflare_port}}/api/v1/scripts/search | jq . || echo "Search endpoint failed"
    @echo "==> ✅ All endpoint tests completed"

# Generate Cloudflare Workers types
cloudflare-types:
    @if [[ -f "/.dockerenv" ]]; then \
        echo "==> Generating Cloudflare Workers types..."; \
        cd {{cloudflare_dir}} && wrangler types --config wrangler.local.jsonc; \
        echo "==> ✅ Types generated successfully"; \
    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then \
        echo "==> Generating Cloudflare Workers types..."; \
        cd "{{root}}" && docker compose -f {{agent_dir}}/docker-compose.yml exec -T agent bash -c 'cd {{cloudflare_dir}} && wrangler types --config wrangler.local.jsonc'; \
        echo "==> ✅ Types generated successfully"; \
    else \
        echo "❌ Neither container nor Docker available - cannot generate types"; \
        exit 1; \
    fi

# Show local Cloudflare Workers configuration
cloudflare-local-config:
    @echo "==> Local Cloudflare Workers Configuration"
    @echo "==> API Endpoint: http://localhost:{{cloudflare_port}}"
    @echo "==> Database: icp-marketplace-test (local D1)"
    @echo "==> Environment: development"
    @cd {{cloudflare_dir}} && wrangler whoami



# =============================================================================
# Flutter App Development
# =============================================================================

# Run Flutter app with local development environment
flutter-local +args="":
    @echo "==> Starting Flutter app with local Cloudflare Workers environment"
    cd {{flutter_dir}} && flutter run -d chrome --dart-define=USE_CLOUDFLARE=true --dart-define=CLOUDFLARE_ENDPOINT=http://localhost:{{cloudflare_port}} {{args}}

# Run Flutter app with production environment
flutter-production +args="":
    @echo "==> Starting Flutter app with production environment"
    cd {{flutter_dir}} && flutter run -d chrome --dart-define=CLOUDFLARE_ENDPOINT=https://icp-mp.kalaj.org {{args}}

# =============================================================================
# Help and Information
# =============================================================================
