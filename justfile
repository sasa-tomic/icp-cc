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
# Appwrite Deployment
# =============================================================================

# Setup Appwrite CLI and build deployment tools
appwrite-setup:
    @echo "==> Setting up Appwrite CLI tools"
    npm install -g appwrite-cli || echo "Appwrite CLI already installed or install failed - please install manually"
    @echo "==> Building Rust deployment tool"
    cd {{root}}/appwrite-cli && cargo build --release

# Deploy to Appwrite with flexible arguments
appwrite +args="":
    cd {{root}}/appwrite-cli && cargo run --bin appwrite-cli -- {{args}}

# Deploy to Appwrite with flexible arguments
# Usage: just appwrite-deploy --target local|prod [additional args]
appwrite-deploy +args="":
    @echo "==> Deploying ICP Script Marketplace to Appwrite"
    cd {{root}}/appwrite-cli && cargo run --bin appwrite-cli -- deploy {{args}}

# Test Appwrite deployment configuration
# Usage: just appwrite-test --target local|prod [additional args]
appwrite-test +args="":
    @echo "==> Testing Appwrite deployment configuration"
    cd {{root}}/appwrite-cli && cargo run --bin appwrite-cli -- test {{args}}

# Show Appwrite configuration
# Usage: just appwrite-config --target local|prod
appwrite-config +args="":
    @echo "==> Showing Appwrite configuration"
    cd {{root}}/appwrite-cli && cargo run --bin appwrite-cli -- config {{args}}

# Initialize Appwrite configuration
# Usage: just appwrite-init --target local|prod [additional args]
appwrite-init +args="":
    @echo "==> Initializing Appwrite configuration"
    cd {{root}}/appwrite-cli && cargo run --bin appwrite-cli -- init {{args}}

# =============================================================================
# Appwrite API Server
# =============================================================================

# Start API server in development mode (default)
appwrite-api-server +args="":
    @echo "==> Starting Appwrite API server (development mode)"
    cd {{root}}/appwrite-api-server && (npm list >/dev/null 2>&1 || npm install) && npm run dev {{args}}

# Start API server in local development mode
appwrite-api-server-local +args="":
    @echo "==> Starting Appwrite API server (local development mode)"
    cd {{root}}/appwrite-api-server && (npm list >/dev/null 2>&1 || npm install) && APPWRITE_ENDPOINT=http://localhost:48080/v1 npm run dev {{args}}

# Start API server in production mode
appwrite-api-server-prod +args="":
    @echo "==> Starting Appwrite API server (production mode)"
    cd {{root}}/appwrite-api-server && (npm list --production >/dev/null 2>&1 || npm install) && npm start {{args}}

# Test API server
appwrite-api-server-test +args="":
    @echo "==> Testing Appwrite API server"
    cd {{root}}/appwrite-api-server && (npm list >/dev/null 2>&1 || npm install) && npm test {{args}}

# Legacy compatibility
appwrite-api-server-dev: appwrite-api-server

# =============================================================================
# Local Development Environment
# =============================================================================

# Start local Appwrite development environment
appwrite-local-up:
    @echo "==> Starting local Appwrite development environment"
    cd {{root}} && docker compose --env-file appwrite-local.env up -d
    @echo "==> Waiting for Appwrite services to be healthy..."
    # Wait up to 120 seconds for services to be healthy, checking every 1 second
    @timeout=120 && elapsed=0 && while [ $${elapsed} -lt $${timeout} ]; do \
        if curl -s http://localhost:48080/health >/dev/null 2>&1; then \
            echo "==> ✅ Appwrite is healthy and ready!"; \
            echo "==> Appwrite Console: http://localhost:48080"; \
            echo "==> Appwrite API: http://localhost:48080/v1"; \
            exit 0; \
        fi; \
        echo "==> Waiting for services... ($${elapsed}/$${timeout} seconds)"; \
        sleep 1; \
        elapsed=$$((elapsed + 1)); \
    done; \
    echo "==> ❌ Appwrite failed to become healthy within $${timeout} seconds"; \
    echo "==> Check logs with: just appwrite-local-logs"; \
    exit 1

# Stop local Appwrite development environment
appwrite-local-down:
    @echo "==> Stopping local Appwrite development environment"
    cd {{root}} && docker compose --env-file appwrite-local.env  down

# Show local Appwrite logs
appwrite-local-logs:
    @echo "==> Showing local Appwrite logs"
    cd {{root}} && docker compose --env-file appwrite-local.env logs -f

# Reset local Appwrite environment (wipes all data)
appwrite-local-reset:
    @echo "==> Resetting local Appwrite environment (wipes all data)"
    cd {{root}} && docker compose --env-file appwrite-local.env down -v --remove-orphans
    cd {{root}} && docker volume prune -f
    cd {{root}} && docker system prune -f
    @echo "==> Local Appwrite environment reset complete"

# Initialize local Appwrite configuration
appwrite-local-init +args="":
    @echo "==> Initializing local Appwrite configuration"
    cd {{root}}/appwrite-cli && cargo run --bin appwrite-cli -- --target local init {{args}}

# Deploy marketplace to local Appwrite instance
appwrite-local-deploy +args="--yes":
    @echo "==> Deploying marketplace to local Appwrite instance"
    cd {{root}}/appwrite-cli && cargo run --bin appwrite-cli -- --target local -v deploy {{args}}

# Start complete development stack (Appwrite + API Server)
appwrite-dev-stack:
    @echo "==> Starting complete development stack (Appwrite + API Server)"
    just appwrite-local-up
    sleep 45
    cd {{root}}/appwrite-api-server && APPWRITE_ENDPOINT=http://localhost:48080/v1 npm run dev &

# Stop complete development stack
appwrite-dev-stop:
    @echo "==> Stopping complete development stack"
    pkill -f "appwrite-api-server.*npm run dev" || true
    just appwrite-local-down

# =============================================================================
# Flutter App Development
# =============================================================================

# Run Flutter app with local development environment
flutter-local +args="":
    @echo "==> Starting Flutter app with local development environment"
    cd {{root}}/apps/autorun_flutter && flutter run -d chrome --dart-define=MARKETPLACE_API_URL=http://localhost:48080/v1 {{args}}

# Run Flutter app with production environment
flutter-production +args="":
    @echo "==> Starting Flutter app with production environment"
    cd {{root}}/apps/autorun_flutter && flutter run -d chrome --dart-define=MARKETPLACE_API_URL=https://fra.cloud.appwrite.io/v1 {{args}}

# =============================================================================
# Help and Information
# =============================================================================
