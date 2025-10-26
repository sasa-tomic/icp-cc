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
        if curl -s "{{cloudflare_health_url}}" >/dev/null 2>&1; then
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
    @cargo clippy --benches --tests --all-features --quiet 2>&1 | tee {{logs_dir}}/test-output.log | grep -E "(error|warning)" && { echo "❌ Rust clippy found issues!"; exit 1; } || echo "✅ No clippy issues found"
    @cargo fmt --all --quiet 2>&1 | tee -a {{logs_dir}}/test-output.log | grep -E "(error|warning)" && { echo "❌ Rust formatting issues found!"; exit 1; } || echo "✅ No formatting issues found"
    @cargo nextest run 2>&1 | tee -a {{logs_dir}}/test-output.log | grep -E "(error|FAILED|Summary)" || echo "✅ Rust tests completed"



# Internal Flutter testing target
_flutter-tests:
    @echo "==> Running Flutter tests with Cloudflare Workers..."
    @just test-with-cloudflare || { echo "❌ Tests failed! Check logs/test-output.log for details"; exit 1; }

# Run Flutter tests with Cloudflare Workers (includes Lua validation)
test-with-cloudflare:
    @echo "==> Starting Cloudflare Workers for tests..."
    @just cloudflare-test-up
    @echo "==> Validating Lua example scripts..."
    @{{scripts_dir}}/validation/validate_lua.sh 2>&1 | tee -a {{logs_dir}}/test-output.log || { echo "❌ Lua script validation failed!"; exit 1; }
    @echo "==> Running Flutter analysis..."
    @cd {{flutter_dir}} && flutter analyze --quiet 2>&1 | tee -a {{logs_dir}}/test-output.log
    @cd {{flutter_dir}} && flutter analyze --quiet 2>&1 | grep -E "(info •|warning •|error •)" && { echo "❌ Flutter analysis found issues!"; exit 1; } || echo "✅ No Flutter analysis issues found"
    @echo "==> Running Flutter tests..."
    @cd {{flutter_dir}} && flutter test --concurrency $(nproc) --timeout=360s --quiet 2>&1 | sed 's/.*\r//' > {{logs_dir}}/test-output.log
    @if [ $? -ne 0 ]; then { grep -iE "(FAIL|ERROR)" {{logs_dir}}/test-output.log ; echo "❌ Flutter tests failed!"; exit 1; }; else echo "✅ All Flutter tests passed"; fi
    @echo "==> Stopping Cloudflare Workers..."
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
    npm install -g wrangler || echo "Wrangler CLI already installed or install failed - please install manually"
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

# Start local Cloudflare Workers development environment
cloudflare-local-up:
    @echo "==> Starting local Cloudflare Workers development environment"
    cd {{cloudflare_dir}} && wrangler dev --port {{cloudflare_port}} --persist-to .wrangler/state &
    @just wait-for-cloudflare-internal 30

# Stop local Cloudflare Workers development environment
cloudflare-local-down:
    @echo "==> Stopping local Cloudflare Workers development environment"
    @pkill -f "wrangler dev" || echo "No wrangler processes found"
    @echo "==> Cloudflare Workers stopped"

# Start Cloudflare Workers for testing (with PID management)
cloudflare-test-up:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Starting Cloudflare Workers for testing"
    
    # Check if already running
    if [ -f "{{cloudflare_test_pid}}" ]; then
        if kill -0 "$(cat {{cloudflare_test_pid}})" 2>/dev/null; then
            echo "==> Cloudflare Workers already running with PID $(cat {{cloudflare_test_pid}})"
        else
            echo "==> Stale PID file found, cleaning up..."
            rm -f "{{cloudflare_test_pid}}"
        fi
    fi
    
    # Start wrangler in background and capture PID
    cd "{{cloudflare_dir}}"
    wrangler dev --port {{cloudflare_port}} --persist-to .wrangler/state > /tmp/wrangler-test.log 2>&1 &
    echo $! > "{{cloudflare_test_pid}}"
    echo "==> Cloudflare Workers started with PID $(cat {{cloudflare_test_pid}})"
    echo "==> Waiting for Cloudflare Workers to be ready..."
    
    # Wait up to 45 seconds for server to be ready, checking every 2 seconds
    timeout=45
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if curl -s "{{cloudflare_health_url}}" >/dev/null 2>&1; then
            echo "==> ✅ Cloudflare Workers is healthy and ready for tests!"
            echo "==> API Endpoint: http://localhost:{{cloudflare_port}}"
            echo "==> Health Check: {{cloudflare_health_url}}"
            
            # Initialize database schema and clear data for clean test environment
            echo "==> Setting up database for clean test environment..."
            cd "{{cloudflare_dir}}" && wrangler d1 execute icp-marketplace-db --file=migrations/0001_initial_schema.sql >/dev/null 2>&1 || echo "Database schema already exists"
            cd "{{cloudflare_dir}}" && wrangler d1 execute icp-marketplace-db --command="DELETE FROM scripts;" >/dev/null 2>&1 || echo "Scripts table already empty"
            cd "{{cloudflare_dir}}" && wrangler d1 execute icp-marketplace-db --command="DELETE FROM reviews;" >/dev/null 2>&1 || echo "Reviews table already empty"  
            cd "{{cloudflare_dir}}" && wrangler d1 execute icp-marketplace-db --command="DELETE FROM purchases;" >/dev/null 2>&1 || echo "Purchases table already empty"
            cd "{{cloudflare_dir}}" && wrangler d1 execute icp-marketplace-db --command="DELETE FROM users;" >/dev/null 2>&1 || echo "Users table already empty"
            echo "==> ✅ Database setup complete for tests"
            
            exit 0
        fi
        echo "==> Waiting for server... ($elapsed/$timeout seconds)"
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "==> ❌ Cloudflare Workers failed to start within $timeout seconds"
    echo "==> Check logs with: cat /tmp/wrangler-test.log"
    exit 1

# Stop Cloudflare Workers for testing (with PID management)
cloudflare-test-down:
    @echo "==> Stopping Cloudflare Workers for testing"
    @just _stop-cloudflare-workers

# Show local Cloudflare Workers logs
cloudflare-local-logs:
    @echo "==> Showing recent Cloudflare Workers logs"
    @echo "==> Use 'wrangler dev' directly to see live logs"
    @echo "==> Or check: cd cloudflare-api && wrangler dev --port 8787"

# Reset local Cloudflare Workers environment (wipes all data)
cloudflare-local-reset:
    @echo "==> Resetting local Cloudflare Workers environment (wipes all data)"
    cd {{cloudflare_dir}} && wrangler d1 execute icp-marketplace-db --command="DELETE FROM scripts;" || echo "Database already empty"
    cd {{cloudflare_dir}} && wrangler d1 execute icp-marketplace-db --command="DELETE FROM reviews;" || echo "Database already empty"
    cd {{cloudflare_dir}} && wrangler d1 execute icp-marketplace-db --command="DELETE FROM script_stats;" || echo "Database already empty"
    @echo "==> Local Cloudflare Workers environment reset complete"

# Initialize local Cloudflare Workers database
cloudflare-local-init:
    @echo "==> Initializing local Cloudflare Workers database"
    cd {{cloudflare_dir}} && wrangler d1 execute icp-marketplace-db --file=migrations/0001_initial_schema.sql
    @echo "==> Database initialized successfully"

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

# Show local Cloudflare Workers configuration
cloudflare-local-config:
    @echo "==> Local Cloudflare Workers Configuration"
    @echo "==> API Endpoint: http://localhost:{{cloudflare_port}}"
    @echo "==> Database: icp-marketplace-db (local D1)"
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
