#!/bin/bash
# One-click Just installation script for ICP-CC project
# Simply run: ./install-just.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Fancy ASCII art
echo -e "${PURPLE}"
cat << 'EOF'
 _   _      _ _     _     _        _
| | | | ___| | | __| | __ _| |_ ___ _ __ _ __ _   _
| |_| |/ _ \ | |/ _` |/ _` | __/ _ \ '__| '__| | | |
|  _  |  __/ | | (_| | (_| | ||  __/ |  | |  | |_| |
|_| |_|\___|_|_|\__,_|\__,_|\__\___|_|  |_|   \__, |
                                                |___/
EOF
echo -e "${NC}"

echo -e "${BLUE}🚀 Installing Just - Modern Command Runner for ICP-CC${NC}"
echo -e "${YELLOW}┌─────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│  Just replaces Make with a modern,           │${NC}"
echo -e "${YELLOW}│  cross-platform, and more powerful tool.     │${NC}"
echo -e "${YELLOW}└─────────────────────────────────────────────────────────┘${NC}"
echo

# Check if Just is already installed
if command -v just >/dev/null 2>&1; then
    INSTALLED_VERSION=$(just --version 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✅ Just is already installed: $INSTALLED_VERSION${NC}"
    echo -e "${GREEN}🎉 You're ready to go! Just run 'just --list' to see commands.${NC}"
    exit 0
fi

echo -e "${YELLOW}📦 Just not found. Installing now...${NC}"
echo

# Download and install Just
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Setup installation directory
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

# Use the official installer which handles OS/arch detection
echo -e "${BLUE}⬇️  Using official Just installer...${NC}"
echo

if command -v curl >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to "$INSTALL_DIR"
elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://just.systems/install.sh | bash -s -- --to "$INSTALL_DIR"
else
    echo -e "${RED}❌ Neither curl nor wget found. Please install one and retry.${NC}"
    exit 1
fi

# Check if ~/.local/bin is in PATH
if echo ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
    echo -e "${GREEN}✅ $HOME/.local/bin is in your PATH${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: $HOME/.local/bin is not in your PATH${NC}"
    echo -e "${YELLOW}   Add this to your shell profile (~/.bashrc, ~/.zshrc, etc):${NC}"
    echo -e "${YELLOW}   export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo -e "${YELLOW}   Then restart your terminal or run: source ~/.bashrc${NC}"
    echo
fi

# Verify installation
if "$INSTALL_DIR/just" --version >/dev/null 2>&1; then
    VERSION=$("$INSTALL_DIR/just" --version)
    echo -e "${GREEN}🎉 Installation successful!${NC}"
    echo -e "${GREEN}📍 Version: $VERSION${NC}"
    echo
    echo -e "${BLUE}📖 Quick start guide:${NC}"
    echo -e "${GREEN}  just                    # Show available commands${NC}"
    echo -e "${GREEN}  just build               # Build current platform${NC}"
    echo -e "${GREEN}  just test               # Run all tests${NC}"
    echo -e "${GREEN}  just appwrite-deploy     # Deploy to Appwrite${NC}"
    echo -e "${GREEN}  just appwrite-deploy -- --dry-run    # Deploy with dry-run${NC}"
    echo
    echo -e "${BLUE}🚀 You're ready to use Just with ICP-CC!${NC}"
else
    echo -e "${RED}❌ Installation verification failed${NC}"
    exit 1
fi