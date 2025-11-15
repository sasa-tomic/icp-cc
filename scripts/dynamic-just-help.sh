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

    # Define categories and their patterns (order matters!)
    declare -A categories=(
        ["Common commands"]="^(test|clean|distclean)$"
        ["Build commands"]="^(linux|android|macos|ios|windows|all|android-emulator)$"
        ["API Server commands"]="^api-"
        ["Flutter commands"]="^flutter"
        ["Testing commands"]="^(rust-tests|flutter-tests|test-with-api)$"
    )

    # Track which targets have been categorized
    local categorized_targets=()
    local uncategorized_targets=()

    for category in "${!categories[@]}"; do
        local pattern="${categories[$category]}"
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

echo -e "${YELLOW}Examples:${NC}"
echo "  just api-up              # Start API server on random port"
echo "  just api-up 8080         # Start API server on port 8080"
echo "  just flutter-local       # Run Flutter app (auto-detects API port)"
echo "  just test                # Run all tests"
echo ""
echo -e "${GREEN}Tip: Run 'just --list' to see all available commands with full details${NC}"
