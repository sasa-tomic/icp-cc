# Justfile for ICP-CC project
# Modern replacement for Makefile with better features and cross-platform support
#
# Install Just: https://just.systems/
# Usage: just [target] [args...]

# Global settings
set shell := ["bash", "-euo", "pipefail", "-c"]
root := `pwd`
scripts_dir := root + "/scripts"

# Platform detection
platform := if `uname` == "Darwin" { "macos" } else if `uname` == "Linux" { "linux" } else { "unknown" }

# Default target - show dynamic help
default:
    @{{scripts_dir}}/dynamic-just-help.sh

# =============================================================================
# Build Targets
# =============================================================================

# Build all platforms
all: linux android

# Platform-specific builds
linux:
    @echo "==> Building Linux target..."
    {{scripts_dir}}/build_linux.sh
    cd {{root}}/apps/autorun_flutter && flutter build linux

android:
    @echo "==> Building Android target..."
    {{scripts_dir}}/build_android.sh
    cd {{root}}/apps/autorun_flutter && flutter build apk

android-emulator:
    @echo "==> Starting Android emulator..."
    {{scripts_dir}}/run_android_emulator.sh

macos:
    @echo "==> Building macOS target..."
    {{scripts_dir}}/build_macos.sh
    cd {{root}}/apps/autorun_flutter && flutter build macos

ios:
    @echo "==> Building iOS target..."
    {{scripts_dir}}/build_ios.sh
    cd {{root}}/apps/autorun_flutter && flutter build ios --no-codesign

windows:
    @echo "==> Building Windows target..."
    {{scripts_dir}}/build_windows.sh
    cd {{root}}/apps/autorun_flutter && flutter build windows

# =============================================================================
# Testing
# =============================================================================

# Run all tests with analysis and linting
test:
    @echo "==> Running Flutter analysis..."
    cd {{root}}/apps/autorun_flutter && flutter analyze --quiet
    @echo "==> Running Flutter tests..."
    cd {{root}}/apps/autorun_flutter && flutter test --quiet
    @echo "==> Running Rust linting and tests"
    cargo clippy --benches --tests --all-features --quiet
    cargo clippy --quiet
    cargo fmt --all --quiet
    cargo nextest run
    @echo "✅ All tests passed!"

# Run tests in machine-readable format (for CI/CD)
test-machine:
    @echo "==> Running Flutter analysis..."
    cd {{root}}/apps/autorun_flutter && flutter analyze --quiet
    @echo "==> Running Flutter tests..."
    cd {{root}}/apps/autorun_flutter && flutter test --machine --quiet
    @echo "==> Running Rust linting and tests"
    cargo clippy --benches --tests --all-features --quiet
    cargo clippy --quiet
    cargo fmt --all --quiet
    cargo nextest run
    @echo "✅ All tests passed!"

# =============================================================================
# Cleanup
# =============================================================================

# Clean build artifacts
clean:
    @echo "==> Cleaning build artifacts..."
    rm -rf {{root}}/apps/autorun_flutter/android/app/src/main/jniLibs/* || true
    rm -rf {{root}}/apps/autorun_flutter/build || true
    rm -f {{root}}/apps/autorun_flutter/build/linux/x64/*/bundle/lib/libicp_core.* || true
    rm -rf {{root}}/apps/autorun_flutter/linux/flutter/ephemeral || true

# Deep clean including dependencies
distclean: clean
    @echo "==> Deep cleaning all artifacts and dependencies..."
    rm -rf {{root}}/target || true
    rm -rf {{root}}/apps/autorun_flutter/.dart_tool || true
    rm -rf {{root}}/apps/autorun_flutter/.gradle || true

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
    cd {{root}}/cloudflare-api && wrangler dev --port 8787 --persist-to .wrangler/state &
    @echo "==> Waiting for Cloudflare Workers to be ready..."
    # Wait up to 30 seconds for server to be ready, checking every 1 second
    @timeout=30 && elapsed=0 && while [ $elapsed -lt $timeout ]; do \
        if curl -s http://localhost:8787/health >/dev/null 2>&1; then \
            echo "==> ✅ Cloudflare Workers is healthy and ready!"; \
            echo "==> API Endpoint: http://localhost:8787"; \
            echo "==> Health Check: http://localhost:8787/health"; \
            exit 0; \
        fi; \
        echo "==> Waiting for server... ($elapsed/$timeout seconds)"; \
        sleep 1; \
        elapsed=$((elapsed + 1)); \
    done; \
    echo "==> ❌ Cloudflare Workers failed to start within $timeout seconds"; \
    echo "==> Check logs with: just cloudflare-local-logs"; \
    exit 1

# Stop local Cloudflare Workers development environment
cloudflare-local-down:
    @echo "==> Stopping local Cloudflare Workers development environment"
    @pkill -f "wrangler dev" || echo "No wrangler processes found"
    @echo "==> Cloudflare Workers stopped"

# Show local Cloudflare Workers logs
cloudflare-local-logs:
    @echo "==> Showing recent Cloudflare Workers logs"
    @echo "==> Use 'wrangler dev' directly to see live logs"
    @echo "==> Or check: cd cloudflare-api && wrangler dev --port 8787"

# Reset local Cloudflare Workers environment (wipes all data)
cloudflare-local-reset:
    @echo "==> Resetting local Cloudflare Workers environment (wipes all data)"
    cd {{root}}/cloudflare-api && wrangler d1 execute icp-marketplace-db --command="DELETE FROM scripts;" || echo "Database already empty"
    cd {{root}}/cloudflare-api && wrangler d1 execute icp-marketplace-db --command="DELETE FROM reviews;" || echo "Database already empty"
    cd {{root}}/cloudflare-api && wrangler d1 execute icp-marketplace-db --command="DELETE FROM script_stats;" || echo "Database already empty"
    @echo "==> Local Cloudflare Workers environment reset complete"

# Initialize local Cloudflare Workers database
cloudflare-local-init:
    @echo "==> Initializing local Cloudflare Workers database"
    cd {{root}}/cloudflare-api && wrangler d1 execute icp-marketplace-db --file=migrations/0001_initial_schema.sql
    @echo "==> Database initialized successfully"

# Test local Cloudflare Workers endpoints
cloudflare-local-test:
    @echo "==> Testing Cloudflare Workers endpoints"
    @echo "==> Testing health endpoint..."
    @curl -s http://localhost:8787/health | jq . || echo "Health check failed"
    @echo "==> Testing marketplace stats..."
    @curl -s http://localhost:8787/api/marketplace-stats | jq . || echo "Stats endpoint failed"
    @echo "==> Testing featured scripts..."
    @curl -s http://localhost:8787/api/scripts/featured | jq . || echo "Featured scripts failed"
    @echo "==> Testing search endpoint..."
    @curl -s -X POST -H "Content-Type: application/json" -d '{"query":"test","limit":5}' http://localhost:8787/api/scripts/search | jq . || echo "Search endpoint failed"
    @echo "==> ✅ All endpoint tests completed"

# Show local Cloudflare Workers configuration
cloudflare-local-config:
    @echo "==> Local Cloudflare Workers Configuration"
    @echo "==> API Endpoint: http://localhost:8787"
    @echo "==> Database: icp-marketplace-db (local D1)"
    @echo "==> Environment: development"
    @cd {{root}}/cloudflare-api && wrangler whoami

# Start complete development stack (Cloudflare Workers only)
cloudflare-dev-stack:
    @echo "==> Starting Cloudflare Workers development environment"
    just cloudflare-local-up

# Stop complete development stack
cloudflare-dev-stop:
    @echo "==> Stopping Cloudflare Workers development environment"
    just cloudflare-local-down

# =============================================================================
# Flutter App Development
# =============================================================================

# Run Flutter app with local development environment
flutter-local +args="":
    @echo "==> Starting Flutter app with local Cloudflare Workers environment"
    cd {{root}}/apps/autorun_flutter && flutter run -d chrome --dart-define=USE_CLOUDFLARE=true --dart-define=CLOUDFLARE_ENDPOINT=http://localhost:8787 {{args}}

# Run Flutter app with production environment
flutter-production +args="":
    @echo "==> Starting Flutter app with production environment"
    cd {{root}}/apps/autorun_flutter && flutter run -d chrome --dart-define=CLOUDFLARE_ENDPOINT=https://icp-autorun.appwrite.network {{args}}

# =============================================================================
# Help and Information
# =============================================================================
