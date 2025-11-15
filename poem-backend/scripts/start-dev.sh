#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}ICP Marketplace API - Development Deployment${NC}"
echo "============================================="
echo

# Change to the script's directory parent (poem-backend)
cd "$(dirname "$0")/.."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker Compose is available
if ! docker compose version &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not available${NC}"
    echo "Please install Docker Compose v2: https://docs.docker.com/compose/install/"
    exit 1
fi

echo -e "${GREEN}✓${NC} Docker and Docker Compose are installed"
echo

# Ensure data directory exists and is writable
echo -e "${YELLOW}Preparing data directory...${NC}"
mkdir -p data
chmod 777 data
echo -e "${GREEN}✓${NC} Data directory ready"
echo

# Build and start services
echo -e "${YELLOW}Building and starting development services...${NC}"
echo

if docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build; then
    echo
    echo -e "${GREEN}=========================================="
    echo "Development Container Started!"
    echo "==========================================${NC}"
    echo
    echo "Services started:"
    echo "  • ICP Marketplace API (dev mode)"
    echo
    echo -e "${YELLOW}Checking API health...${NC}"
    sleep 3

    # Check if API is healthy
    if curl -f -s http://localhost:58000/api/v1/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} API is healthy!"
        echo
        echo "Your API is now accessible locally at:"
        echo -e "  ${BLUE}http://localhost:58000/api/v1/health${NC}"
        echo
        echo "API endpoints:"
        echo -e "  ${BLUE}http://localhost:58000/api/v1/health${NC}          - Health check"
        echo -e "  ${BLUE}http://localhost:58000/api/v1/marketplace-stats${NC} - Stats"
        echo -e "  ${BLUE}http://localhost:58000/api/v1/scripts${NC}          - Scripts listing"
    else
        echo -e "${YELLOW}⚠${NC}  API not responding yet - check logs:"
        echo -e "  ${BLUE}just docker-logs-dev${NC}"
    fi
    echo
    echo "Useful commands:"
    echo -e "  ${BLUE}just docker-logs-dev${NC}      # View logs"
    echo -e "  ${BLUE}just docker-status-dev${NC}    # Check status"
    echo -e "  ${BLUE}just docker-rebuild-dev${NC}   # Rebuild"
    echo -e "  ${BLUE}just docker-down-dev${NC}      # Stop"
    echo
else
    echo
    echo -e "${RED}=========================================="
    echo "Deployment Failed"
    echo "==========================================${NC}"
    echo
    echo "Check the logs for errors:"
    echo -e "  ${BLUE}just docker-logs-dev${NC}"
    echo
    exit 1
fi
