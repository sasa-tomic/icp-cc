#!/usr/bin/env bash
set -euo pipefail

# Fully dynamic help generation for justfile
# This script parses the justfile and generates completely dynamic help

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
JUSTFILE="${REPO_ROOT}/justfile"

# Colors for better formatting
BOLD='\033[1m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BOLD}Justfile for ICP-CC project${NC}"
echo ""

# Function to extract and categorize targets
extract_and_categorize() {
    local all_targets
    # Extract only recipe targets (lines with target:), excluding variable assignments (lines with :=)
    all_targets=$(grep -E "^[a-zA-Z][a-zA-Z0-9_-]*[^:]*:" "${JUSTFILE}" | \
                  grep -v ":=" | \
                  sed 's/^\([a-zA-Z][a-zA-Z0-9_-]*\).*/\1/' | \
                  grep -v "^default$" | \
                  sort -u)

    # Define categories and their patterns (order matters - use arrays!)
    local category_names=(
        "Quick Start"
        "API Server (Local)"
        "Flutter Builds"
        "Flutter Development"
        "Docker Deployment"
        "Docker Logs & Status"
        "Docker Rebuild"
        "Testing (Internal)"
    )

    declare -A category_patterns=(
        ["Quick Start"]="^(all|test|clean|distclean)$"
        ["API Server (Local)"]="^api-dev"
        ["Flutter Builds"]="^(linux|android|macos|ios|windows|android-emulator)$"
        ["Flutter Development"]="^flutter-(local|production)$"
        ["Docker Deployment"]="^docker-(deploy|prod-up|dev-up|prod-down|dev-down|all-down)$"
        ["Docker Logs & Status"]="^docker-(prod-logs|dev-logs|prod-status|dev-status|all-status)$"
        ["Docker Rebuild"]="^docker-(prod-rebuild|dev-rebuild)$"
        ["Testing (Internal)"]="^(rust-tests|flutter-tests)$"
    )

    # Track which targets have been categorized
    local categorized_targets=()
    local uncategorized_targets=()

    for category in "${category_names[@]}"; do
        local pattern="${category_patterns[$category]}"
        local category_targets=()

        for target in $all_targets; do
            # Skip internal variables and already categorized targets
            if [[ "$target" =~ ^(platform|root|scripts_dir|logs_dir|flutter_dir|api_dir|api_pid_file|api_port_file|set)$ ]]; then
                continue
            fi

            # Check if target matches current category pattern and hasn't been categorized yet
            if [[ $target =~ $pattern ]]; then
                local already_categorized=false
                for categorized in "${categorized_targets[@]}"; do
                    if [[ "$target" == "$categorized" ]]; then
                        already_categorized=true
                        break
                    fi
                done

                if [[ "$already_categorized" == false ]]; then
                    category_targets+=("$target")
                    categorized_targets+=("$target")
                fi
            fi
        done

        if [[ ${#category_targets[@]} -gt 0 ]]; then
            echo -e "${BLUE}${category}:${NC}"
            for target in "${category_targets[@]}"; do
                # Create a simple description based on target name
                local description=""
                case $target in
                    test*) description="Run tests" ;;
                    clean*) description="Clean build artifacts" ;;
                    linux|android|macos|ios|windows) description="Build for $target" ;;
                    *deploy*) description="Deploy to target environment" ;;
                    *setup*) description="Setup tools or environment" ;;
                    *up*) description="Start services" ;;
                    *down*) description="Stop services" ;;
                    *test*) description="Test configuration or deployment" ;;
                    *logs*) description="Show logs" ;;
                    *config*) description="Show configuration" ;;
                    *init*) description="Initialize environment" ;;
                    *validate*) description="Validate configuration" ;;
                    *generate*) description="Generate files or targets" ;;
                    *) description="Run $target" ;;
                esac
                printf "  %-25s # %s\n" "$target" "$description"
            done
            echo ""
        fi
    done

    # Find uncategorized targets
    for target in $all_targets; do
        if [[ "$target" =~ ^(platform|root|scripts_dir|logs_dir|flutter_dir|api_dir|api_pid_file|api_port_file|set)$ ]]; then
            continue
        fi

        local categorized=false
        for categorized_target in "${categorized_targets[@]}"; do
            if [[ "$target" == "$categorized_target" ]]; then
                categorized=true
                break
            fi
        done

        if [[ "$categorized" == false ]]; then
            uncategorized_targets+=("$target")
        fi
    done

    # Show uncategorized targets if any exist
    if [[ ${#uncategorized_targets[@]} -gt 0 ]]; then
        echo -e "${BLUE}Other commands:${NC}"
        for target in "${uncategorized_targets[@]}"; do
            local description="Run $target"
            case $target in
                test*) description="Run tests" ;;
                clean*) description="Clean build artifacts" ;;
                *deploy*) description="Deploy to target environment" ;;
                *setup*) description="Setup tools or environment" ;;
                *up*) description="Start services" ;;
                *down*) description="Stop services" ;;
                *test*) description="Test configuration or deployment" ;;
                *logs*) description="Show logs" ;;
                *config*) description="Show configuration" ;;
                *init*) description="Initialize environment" ;;
                *validate*) description="Validate configuration" ;;
                *generate*) description="Generate files or targets" ;;
            esac
            printf "  %-25s # %s\n" "$target" "$description"
        done
        echo ""
    fi
}

# Generate dynamic help
extract_and_categorize

echo -e "${YELLOW}Quick Examples:${NC}"
echo "  just test                      # Run all tests"
echo "  just api-dev-up                # Start local dev API server"
echo "  just docker-dev-up             # Start Docker dev containers"
echo "  just docker-deploy-prod        # Deploy to production with CF Tunnel"
echo "  just flutter-local             # Run Flutter app with local API"
echo ""
echo ""
echo -e "${GREEN}Tip: Run 'just --list' to see all targets with descriptions${NC}"
