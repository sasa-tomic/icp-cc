#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLOUDFLARE_DIR="$PROJECT_ROOT/cloudflare-api"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log with color
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to generate random database name
generate_db_name() {
    local prefix="icp-marketplace-test"
    local suffix=$(openssl rand -hex 4)
    echo "${prefix}-${suffix}"
}

# Function to create test database
create_test_db() {
    local db_name="$1"
    log_info "Creating test database: $db_name"
    
    cd "$CLOUDFLARE_DIR"
    
    # Create the local database using miniflare
    wrangler d1 execute "$db_name" --command="SELECT 1" --local --config wrangler.local.jsonc 2>/dev/null || {
        log_info "Initializing local test database: $db_name"
        wrangler d1 execute "$db_name" --file=migrations/0001_initial_schema.sql --local --config wrangler.local.jsonc
    }
    
    # Use a fixed ID for local testing
    local db_id="local-test-db"
    
    log_info "Created local database: $db_name (ID: $db_id)"
    echo "$db_id"
}

# Function to delete test database
delete_test_db() {
    local db_name="$1"
    log_info "Deleting test database: $db_name"
    
    cd "$CLOUDFLARE_DIR"
    # For local databases, we just clean the data
    wrangler d1 execute "$db_name" --command="DELETE FROM scripts;" --local --config wrangler.local.jsonc 2>/dev/null || log_warn "Database $db_name not found or already empty"
    wrangler d1 execute "$db_name" --command="DELETE FROM reviews;" --local --config wrangler.local.jsonc 2>/dev/null || log_warn "Reviews table already empty"
    wrangler d1 execute "$db_name" --command="DELETE FROM purchases;" --local --config wrangler.local.jsonc 2>/dev/null || log_warn "Purchases table already empty"
    wrangler d1 execute "$db_name" --command="DELETE FROM users;" --local --config wrangler.local.jsonc 2>/dev/null || log_warn "Users table already empty"
}

# Function to initialize database schema
init_db_schema() {
    local db_name="$1"
    log_info "Initializing schema for database: $db_name"
    
    cd "$CLOUDFLARE_DIR"
    wrangler d1 execute "$db_name" --file=migrations/0001_initial_schema.sql --local --config wrangler.local.jsonc
}

# Function to clean up all test databases
cleanup_all_test_dbs() {
    log_info "Cleaning up all test databases..."
    
    cd "$CLOUDFLARE_DIR"
    
    # For local testing, just clean the standard test database
    delete_test_db "icp-marketplace-test"
    
    log_info "Cleanup completed"
}

# Function to setup test environment
setup_test_env() {
    local test_name="$1"
    local db_name="icp-marketplace-test"
    
    log_info "Setting up test environment for: $test_name"
    
    # Always create/initialize local test database
    local db_id=""
    log_info "Creating test database: $db_name"
    db_id=$(create_test_db "$db_name")
    init_db_schema "$db_name"
    
    # Export environment variables for the test
    export TEST_DB_NAME="$test_name"
    export TEST_DB_ID="$db_id"
    export TEST_DB_FULL_NAME="$db_name"
    
    log_info "Test environment ready:"
    log_info "  - Database: $db_name"
    log_info "  - Test Name: $test_name"
    
    echo "$db_name"
}

# Function to teardown test environment
teardown_test_env() {
    local test_name="$1"
    local db_name="${2:-}"
    
    log_info "Tearing down test environment for: $test_name"
    
    # Clean up temp config file
    if [ -n "${WRANGLER_CONFIG_FILE:-}" ]; then
        rm -f "$WRANGLER_CONFIG_FILE"
    fi
    
    # Delete database if name provided
    if [ -n "$db_name" ]; then
        delete_test_db "$db_name"
    fi
    
    # Unset environment variables
    unset TEST_DB_NAME TEST_DB_ID TEST_DB_FULL_NAME WRANGLER_CONFIG_FILE
    
    log_info "Teardown completed"
}

# Main command handling
case "${1:-}" in
    "create")
        if [ -z "${2:-}" ]; then
            log_error "Usage: $0 create <test-name>"
            exit 1
        fi
        setup_test_env "$2"
        ;;
    "cleanup")
        cleanup_all_test_dbs
        ;;
    "delete")
        if [ -z "${2:-}" ]; then
            log_error "Usage: $0 delete <database-name>"
            exit 1
        fi
        delete_test_db "$2"
        ;;
    "init")
        if [ -z "${2:-}" ]; then
            log_error "Usage: $0 init <database-name>"
            exit 1
        fi
        init_db_schema "$2"
        ;;
    *)
        echo "Usage: $0 {create|cleanup|delete|init} [args]"
        echo ""
        echo "Commands:"
        echo "  create <test-name>    Create and setup test database"
        echo "  cleanup              Delete all test databases"
        echo "  delete <db-name>     Delete specific database"
        echo "  init <db-name>       Initialize database schema"
        echo ""
        echo "Examples:"
        echo "  $0 create comprehensive"
        echo "  $0 cleanup"
        echo "  $0 delete icp-marketplace-test-1234abcd"
        exit 1
        ;;
esac