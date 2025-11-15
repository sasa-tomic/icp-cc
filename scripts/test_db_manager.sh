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
    
    # Create the database
    wrangler d1 create "$db_name"
    
    # Get database ID
    local db_id=$(wrangler d1 info "$db_name" --json | jq -r '.uuid')
    
    log_info "Created database: $db_name (ID: $db_id)"
    echo "$db_id"
}

# Function to delete test database
delete_test_db() {
    local db_name="$1"
    log_info "Deleting test database: $db_name"
    
    cd "$CLOUDFLARE_DIR"
    wrangler d1 delete "$db_name" || log_warn "Database $db_name not found or already deleted"
}

# Function to initialize database schema
init_db_schema() {
    local db_name="$1"
    log_info "Initializing schema for database: $db_name"
    
    cd "$CLOUDFLARE_DIR"
    wrangler d1 execute "$db_name" --file=migrations/0001_initial_schema.sql
}

# Function to clean up all test databases
cleanup_all_test_dbs() {
    log_info "Cleaning up all test databases..."
    
    cd "$CLOUDFLARE_DIR"
    
    # List all databases and filter test databases
    local test_dbs=$(wrangler d1 list --json | jq -r '.[] | select(.name | startswith("icp-marketplace-test")) | .name')
    
    for db in $test_dbs; do
        if [ -n "$db" ]; then
            delete_test_db "$db"
        fi
    done
    
    log_info "Cleanup completed"
}

# Function to setup test environment
setup_test_env() {
    local test_name="$1"
    local db_name="icp-marketplace-test"
    
    log_info "Setting up test environment for: $test_name"
    
    # Check if test database exists, create if not
    local db_id=""
    if ! wrangler d1 info "$db_name" >/dev/null 2>&1; then
        log_info "Creating test database: $db_name"
        db_id=$(create_test_db "$db_name")
        init_db_schema "$db_name"
    else
        log_info "Using existing test database: $db_name"
        db_id=$(wrangler d1 info "$db_name" --json | jq -r '.uuid')
    fi
    
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