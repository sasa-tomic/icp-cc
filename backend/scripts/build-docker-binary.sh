#!/usr/bin/env bash
set -euo pipefail

# Build the binary for Docker deployment (linux/amd64)
# This script builds the binary natively, which is then injected into the Docker image

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "==> Building icp-marketplace-api for Docker (linux/amd64)"

# Build the release binary for native target
echo "==> Building release binary..."
cargo build --release

# Create output directory for Docker build context
mkdir -p target/docker
cp target/release/icp-marketplace-api target/docker/

# Strip debug symbols to reduce size
if command -v strip &> /dev/null; then
    echo "==> Stripping debug symbols..."
    strip target/docker/icp-marketplace-api
fi

echo "==> ✅ Binary built successfully: target/docker/icp-marketplace-api"
echo "==> Binary size: $(du -h target/docker/icp-marketplace-api | cut -f1)"
echo "==> Ready for Docker image build"
