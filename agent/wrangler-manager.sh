#!/bin/bash

# Wrangler process management within the container
# Provides fail-fast startup, health checking, and clean shutdown

set -euo pipefail

# Find repository root by looking for .git directory, fallback to script dir/../
find_repo_root() {
    local current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Navigate up looking for .git directory
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done

    # Fallback to script directory parent
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}

# Get repository root
REPO_ROOT="$(find_repo_root)"

# Configuration (using relative paths from repo root)
WRANGLER_PID_FILE="$REPO_ROOT/.tmp/wrangler-test.pid"
WRANGLER_LOG_FILE="$REPO_ROOT/.tmp/wrangler-dev.log"
CLOUDFLARE_DIR="$REPO_ROOT/cloudflare-api"
WRANGLER_PORT="8787"
HEALTH_URL="http://localhost:${WRANGLER_PORT}/api/v1/health"
TIMEOUT=60

# Ensure .tmp directory exists
mkdir -p "$(dirname "$WRANGLER_PID_FILE")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Debug: Show paths being used (can be enabled by setting DEBUG=1)
if [[ "${DEBUG:-0}" == "1" ]]; then
    echo "==> Repository Root: $REPO_ROOT"
    echo "==> PID File: $WRANGLER_PID_FILE"
    echo "==> Log File: $WRANGLER_LOG_FILE"
    echo "==> Cloudflare Dir: $CLOUDFLARE_DIR"
fi

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if wrangler process is running
is_running() {
    if [[ -f "$WRANGLER_PID_FILE" ]]; then
        local pid=$(cat "$WRANGLER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            rm -f "$WRANGLER_PID_FILE"
            return 1
        fi
    fi
    return 1
}

# Check if wrangler service is healthy
is_healthy() {
    # Primary: Check if process is still running and responding
    if [[ -f "$WRANGLER_PID_FILE" ]]; then
        local pid=$(cat "$WRANGLER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            # Check if process has written "Ready" to logs
            if [[ -f "$WRANGLER_LOG_FILE" ]] && grep -q "Ready on http://localhost:$WRANGLER_PORT" "$WRANGLER_LOG_FILE"; then
                return 0
            fi
        fi
    fi

    # Fallback: try curl if available
    if command -v curl >/dev/null 2>&1; then
        timeout 5 curl -s "http://localhost:$WRANGLER_PORT" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        timeout 5 wget -q --spider "http://localhost:$WRANGLER_PORT" >/dev/null 2>&1
    else
        # Last resort: check if port is accessible
        timeout 5 bash -c "</dev/tcp/localhost/$WRANGLER_PORT" >/dev/null 2>&1
    fi
}

# Stop wrangler process
stop_wrangler() {
    log_info "Stopping wrangler process..."

    if is_running; then
        local pid=$(cat "$WRANGLER_PID_FILE")
        log_info "Sending TERM signal to wrangler (PID: $pid)"
        kill -TERM "$pid" || true

        # Wait for graceful shutdown
        local count=0
        while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
            sleep 1
            count=$((count + 1))
        done

        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            log_warning "Wrangler did not shut down gracefully, force killing..."
            kill -KILL "$pid" || true
        fi

        log_success "Wrangler stopped"
    else
        log_warning "Wrangler process was not running"
    fi

    # Cleanup
    rm -f "$WRANGLER_PID_FILE"
    # Optionally clean up log file on stop (keep for debugging)
    # rm -f "$WRANGLER_LOG_FILE"
    log_info "Cleanup completed"
}

# Start wrangler process
start_wrangler() {
    log_info "Starting wrangler process in container..."

    # Enhanced cleanup: Handle any existing processes or stale state
    if is_running; then
        log_warning "⚠️ Existing wrangler process detected - cleaning up"
        stop_wrangler
        sleep 2
    fi

    # Aggressive cleanup with pkill and verification
    log_info "Performing aggressive cleanup of wrangler processes..."

    # First attempt: Graceful shutdown with pkill
    pkill -f "wrangler dev" || true
    pkill -f "workerd" || true

    # Check for 5 seconds with pgrep every second
    local count=0
    while [ $count -lt 5 ]; do
        if ! pgrep -f "wrangler dev" >/dev/null 2>&1 && ! pgrep -f "workerd" >/dev/null 2>&1; then
            log_info "All wrangler processes terminated gracefully"
            break
        fi
        log_info "Waiting for processes to terminate... ($((count + 1))/5)"
        sleep 1
        count=$((count + 1))
    done

    # Second attempt: Force kill with pkill -9 if still running
    if pgrep -f "wrangler dev" >/dev/null 2>&1 || pgrep -f "workerd" >/dev/null 2>&1; then
        log_warning "Some processes still running, using force kill..."
        pkill -9 -f "wrangler dev" || true
        pkill -9 -f "workerd" || true
        sleep 1
    fi

    # Additional cleanup: Check for any processes using the port
    if command -v lsof >/dev/null 2>&1; then
        local port_pids=$(lsof -ti ":$WRANGLER_PORT" 2>/dev/null || true)
        if [[ -n "$port_pids" ]]; then
            log_warning "⚠️ Processes using port $WRANGLER_PORT detected - cleaning up"
            echo "$port_pids" | xargs -r kill -TERM 2>/dev/null || true
            sleep 2
            # Force kill if still running
            echo "$port_pids" | xargs -r kill -KILL 2>/dev/null || true
        fi
    fi

    # Final verification
    if pgrep -f "wrangler dev" >/dev/null 2>&1 || pgrep -f "workerd" >/dev/null 2>&1; then
        log_error "❌ Failed to terminate all wrangler processes"
        return 1
    fi

    # Final cleanup: Remove any stale PID file
    rm -f "$WRANGLER_PID_FILE"
    log_info "Cleanup completed successfully"

    # Port check now redundant due to cleanup above, but keep as safety net
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i ":$WRANGLER_PORT" >/dev/null 2>&1; then
            log_error "❌ Port $WRANGLER_PORT is still in use after cleanup - FAILING FAST"
            log_error "Another process is blocking the wrangler port"
            return 1
        fi
    fi

    # Start wrangler in background
    log_info "Starting wrangler dev server..."
    cd "$CLOUDFLARE_DIR"

    # Start wrangler with background execution and logging
    WRANGLER_LOG=info nohup wrangler dev --local \
        --config wrangler.local.jsonc \
        --port "$WRANGLER_PORT" \
        --persist-to .wrangler/state \
        --var="TEST_DB_NAME:default" \
        > "$WRANGLER_LOG_FILE" 2>&1 &

    local wrangler_pid=$!
    echo "$wrangler_pid" > "$WRANGLER_PID_FILE"

    log_info "Wrangler started with PID: $wrangler_pid"

    # Wait for health check
    log_info "Waiting for wrangler to become healthy..."
    local elapsed=0

    while [ $elapsed -lt $TIMEOUT ]; do
        if ! kill -0 "$wrangler_pid" 2>/dev/null; then
            log_error "❌ WRANGLER PROCESS DIED"
            log_error "FAIL FAST - Critical infrastructure process failure"
            log_error "Process terminated unexpectedly"
            log_error "Last log lines:"
            tail -10 "$WRANGLER_LOG_FILE" 2>/dev/null || echo "No logs available"
            return 1
        fi

        if is_healthy; then
            log_success "✅ Wrangler is healthy and ready!"
            log_success "API Endpoint: http://localhost:$WRANGLER_PORT"
            log_success "Health Check: $HEALTH_URL"
            log_success "Test Database: icp-marketplace-test"
            return 0
        fi

        echo -n "."
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo
    log_error "❌ WRANGLER HEALTH FAILURE"
    log_error "FAIL FAST - Service failed to become healthy within $TIMEOUT seconds"
    log_error "Log output:"
    tail -20 "$WRANGLER_LOG_FILE" 2>/dev/null || echo "No logs available"
    return 1
}

# Show wrangler status
status_wrangler() {
    if is_running; then
        local pid=$(cat "$WRANGLER_PID_FILE")
        echo "==> Wrangler Process Status: RUNNING"
        echo "==> PID: $pid"
        echo "==> Port: $WRANGLER_PORT"

        if is_healthy; then
            echo "==> Health: HEALTHY ✅"
            echo "==> API: http://localhost:$WRANGLER_PORT"
        else
            echo "==> Health: UNHEALTHY ❌"
            echo "==> Recent logs:"
            tail -10 "$WRANGLER_LOG_FILE" 2>/dev/null || echo "No logs available"
        fi
    else
        echo "==> Wrangler Process Status: NOT RUNNING"
    fi
}

# Show wrangler logs
logs_wrangler() {
    if [[ -f "$WRANGLER_LOG_FILE" ]]; then
        echo "==> Wrangler Logs (last 50 lines):"
        tail -50 "$WRANGLER_LOG_FILE"
    else
        echo "==> No wrangler log file found"
    fi
}

# Main command handling
case "${1:-}" in
    start)
        start_wrangler
        ;;
    stop)
        stop_wrangler
        ;;
    restart)
        stop_wrangler
        sleep 2
        start_wrangler
        ;;
    status)
        status_wrangler
        ;;
    logs)
        logs_wrangler
        ;;
    health)
        if is_healthy; then
            echo "healthy"
            exit 0
        else
            echo "unhealthy"
            exit 1
        fi
        ;;
    *)
        cat << EOF
Wrangler Process Manager for ICP-CC

USAGE:
    $0 {start|stop|restart|status|logs|health}

COMMANDS:
    start       Start wrangler development server (fail-fast)
    stop        Stop wrangler process with cleanup
    restart     Stop and start wrangler process
    status      Show current wrangler process status
    logs        Show recent wrangler logs
    health      Check if wrangler is healthy (exit code)

This script provides fail-fast process management for wrangler within
the development container, ensuring clean state and immediate failure
detection.

EOF
        exit 1
        ;;
esac
