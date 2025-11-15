#!/usr/bin/env bash
set -euo pipefail

# Build the binary for Docker deployment (linux/amd64, statically linked)
# This script builds the binary natively, which is then injected into the Docker image

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "==> Building icp-marketplace-api for Docker (linux/amd64, musl)"

# Check and install musl target
if ! rustup target list --installed | grep -q "x86_64-unknown-linux-musl"; then
    echo "==> Installing x86_64-unknown-linux-musl target..."
    rustup target add x86_64-unknown-linux-musl
fi

# Check if musl-tools is installed and offer to install
if ! command -v musl-gcc &> /dev/null; then
    echo "⚠️  musl-tools not found. Installing..."

    # Detect package manager and install
    if command -v apt-get &> /dev/null; then
        echo "==> Detected apt package manager"
        if [ "$EUID" -eq 0 ]; then
            apt-get update && apt-get install -y musl-tools musl-dev
        else
            echo "==> Installing musl-tools (requires sudo)..."
            sudo apt-get update && sudo apt-get install -y musl-tools musl-dev
        fi
    elif command -v dnf &> /dev/null; then
        echo "==> Detected dnf package manager"
        if [ "$EUID" -eq 0 ]; then
            dnf install -y musl-gcc musl-libc-static
        else
            sudo dnf install -y musl-gcc musl-libc-static
        fi
    elif command -v pacman &> /dev/null; then
        echo "==> Detected pacman package manager"
        if [ "$EUID" -eq 0 ]; then
            pacman -S --noconfirm musl
        else
            sudo pacman -S --noconfirm musl
        fi
    else
        echo "❌ Cannot auto-install musl-tools. Please install manually:"
        echo "   Ubuntu/Debian: sudo apt-get install -y musl-tools musl-dev"
        echo "   Fedora/RHEL:   sudo dnf install -y musl-gcc musl-libc-static"
        echo "   Arch:          sudo pacman -S musl"
        exit 1
    fi
fi

# Verify musl-gcc is now available
if ! command -v musl-gcc &> /dev/null; then
    echo "❌ musl-gcc still not available after installation attempt"
    exit 1
fi

# Build the release binary with musl for static linking
echo "==> Building release binary..."
cargo build --release --target x86_64-unknown-linux-musl

# Create output directory for Docker build context
mkdir -p target/docker
cp target/x86_64-unknown-linux-musl/release/icp-marketplace-api target/docker/

echo "==> ✅ Binary built successfully: target/docker/icp-marketplace-api"
echo "==> Binary size: $(du -h target/docker/icp-marketplace-api | cut -f1)"
echo "==> Ready for Docker image build"
