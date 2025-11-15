#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}ICP Marketplace API - Production Deployment${NC}"
echo "==============================================="
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

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠${NC}  .env not found"
    echo
    echo "You need to create a Cloudflare Tunnel and save the token."
    echo
    echo "Steps:"
    echo "  1. Go to: ${BLUE}https://one.dash.cloudflare.com/${NC}"
    echo "  2. Navigate to: Networks > Connectors > Cloudflare Tunnels"
    echo "  3. Click 'Create a tunnel' > Choose 'Cloudflared' > Name it 'icp-marketplace'"
    echo "  4. Add a public hostname:"
    echo "     - Subdomain: icp-mp"
    echo "     - Domain: kalaj.org"
    echo "     - Service Type: HTTP"
    echo "     - URL: api:58000"
    echo "  5. Select 'Docker' and copy the token from the command"
    echo "  6. Create .env file:"
    echo
    echo -e "     ${BLUE}cp .env.tunnel.example .env${NC}"
    echo -e "     ${BLUE}$EDITOR .env${NC}  # Add your token"
    echo
    exit 1
fi

echo -e "${GREEN}✓${NC} Found .env file"
echo

# Ensure data directory exists and is writable
echo -e "${YELLOW}Preparing data directory...${NC}"
mkdir -p data
chmod 777 data
echo -e "${GREEN}✓${NC} Data directory ready"
echo

# Build and start services
echo -e "${YELLOW}Building and starting services...${NC}"
echo

if docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build; then
    echo
    echo -e "${GREEN}=========================================="
    echo "Containers Started!"
    echo "==========================================${NC}"
    echo
    echo "Services starting:"
    echo "  • ICP Marketplace API"
    echo "  • Cloudflare Tunnel"
    echo
    echo -e "${YELLOW}Checking tunnel connection...${NC}"
    sleep 5

    # Check if tunnel connected successfully
    if docker compose -f docker-compose.yml -f docker-compose.prod.yml logs cloudflared 2>&1 | grep -q "Registered tunnel connection connIndex="; then
        echo -e "${GREEN}✓${NC} Tunnel connected successfully!"
        echo
        echo "Your API is now accessible at:"
        echo -e "  ${BLUE}https://icp-mp.kalaj.org/api/v1/health${NC}"
    elif docker compose -f docker-compose.yml -f docker-compose.prod.yml logs cloudflared 2>&1 | grep -q "Unauthorized"; then
        echo -e "${RED}✗${NC} Tunnel authentication failed!"
        echo
        echo "This means:"
        echo "  1. The tunnel doesn't exist in Cloudflare dashboard, OR"
        echo "  2. The tunnel token is incorrect"
        echo
        echo "Please:"
        echo "  1. Go to: ${BLUE}https://one.dash.cloudflare.com/${NC}"
        echo "  2. Check Networks > Tunnels"
        echo "  3. Verify the tunnel exists and get a fresh token"
        echo "  4. Update .env with the correct TUNNEL_TOKEN"
        echo
    else
        echo -e "${YELLOW}⚠${NC}  Tunnel status unclear - check logs:"
        echo -e "  ${BLUE}docker compose logs cloudflared${NC}"
    fi
    echo
    echo "Useful commands:"
    echo -e "  ${BLUE}just docker-logs-prod${NC}     # View logs"
    echo -e "  ${BLUE}just docker-status-prod${NC}   # Check status"
    echo -e "  ${BLUE}just docker-rebuild-prod${NC}  # Rebuild"
    echo -e "  ${BLUE}just docker-down-prod${NC}     # Stop services"
    echo
else
    echo
    echo -e "${RED}=========================================="
    echo "Deployment Failed"
    echo "==========================================${NC}"
    echo
    echo "Check the logs for errors:"
    echo -e "  ${BLUE}just docker-logs-prod${NC}"
    echo
    exit 1
fi
