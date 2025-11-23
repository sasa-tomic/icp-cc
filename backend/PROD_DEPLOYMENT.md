# Docker Deployment with Cloudflare Tunnel

This guide explains how to deploy the ICP Marketplace API using Docker Compose with Cloudflare Tunnel for secure external access.

## Overview

The deployment consists of two services:
- **api**: The ICP Marketplace API (Poem-based Rust application)
- **cloudflared**: Cloudflare Tunnel connector for secure external access

## Architecture

```
Internet
    ↓
Cloudflare Network
    ↓
Cloudflare Tunnel (cloudflared container)
    ↓
icp-mp.kalaj.org → api:58000
```

**Benefits:**
- No firewall ports need to be opened
- Built-in DDoS protection via Cloudflare
- Automatic TLS/SSL encryption
- No public IP exposure
- **No local cloudflared installation needed** - everything runs in containers

## Prerequisites

1. A Cloudflare account with access to the domain `kalaj.org`
2. Docker and Docker Compose installed

That's it! No need to install cloudflared locally.

## Setup (5-minute setup)

### Step 1: Create a Remotely-Managed Tunnel in Cloudflare Dashboard

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** > **Connectors** > **Cloudflare Tunnels**
3. Click **Create a tunnel**
4. Choose **Cloudflared** and click **Next**
5. Enter tunnel name: `icp-marketplace`
6. Click **Save tunnel**

### Step 2: Configure Public Hostname

1. In the tunnel configuration page, go to the **Public Hostname** tab
2. Click **Add a public hostname**
3. Configure:
   - **Subdomain**: `icp-mp`
   - **Domain**: `kalaj.org`
   - **Service Type**: `HTTP`
   - **URL**: `api:58000`
4. Click **Save hostname**

### Step 3: Get the Tunnel Token

1. In the tunnel page, select **Configure** (or **Edit**)
2. Choose **Docker** as the environment
3. Copy the installation command shown in the dashboard
4. Extract just the token value (the long string starting with `eyJhIjoiNWFi...`)

The command looks like:
```bash
docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJhIjoiNWFi...
```

### Step 4: Save Token Locally

Create `.env.tunnel` file in the `backend` directory:

```bash
# Copy the example file
cp .env.tunnel.example .env.tunnel

# Edit and add your token
nano .env.tunnel
```

Add your token:
```bash
TUNNEL_TOKEN=eyJhIjoiNWFi...your-actual-token-here
```

**Important:** This file is gitignored and contains secrets - never commit it!

### Step 5: Prepare Data Directory

```bash
# Create and set permissions for the database directory
mkdir -p data
chmod 777 data
```

### Step 6: Start Services

```bash
# Load the tunnel token and start services
export $(cat .env.tunnel | xargs) && docker compose up -d

# Or use --env-file (Docker Compose v2.1+)
docker compose --env-file .env.tunnel up -d
```

### Step 7: Verify Deployment

```bash
# Check service health
docker compose ps

# View logs
docker compose logs -f

# Test the API endpoint
curl https://icp-mp.kalaj.org/api/v1/health

# Expected response: {"status":"ok"}
```

## Management

### View Logs

```bash
# All services
docker compose logs -f

# API only
docker compose logs -f api

# Cloudflared only
docker compose logs -f cloudflared
```

### Restart Services

```bash
# Restart all
export $(cat .env.tunnel | xargs) && docker compose restart

# Restart specific service
export $(cat .env.tunnel | xargs) && docker compose restart api
export $(cat .env.tunnel | xargs) && docker compose restart cloudflared
```

### Stop Services

```bash
docker compose down
```

### Update and Rebuild

```bash
# Pull latest code changes
git pull

# Rebuild and restart
export $(cat .env.tunnel | xargs) && docker compose up -d --build
```

## Monitoring

### Health Checks

The API service includes a built-in health check that runs every 30 seconds:

```bash
docker compose ps  # Shows health status
```

### Tunnel Status

Check tunnel status in the Cloudflare dashboard:
1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** > **Connectors** > **Cloudflare Tunnels**
3. Your tunnel should show as "Healthy" with active connections

## Troubleshooting

### API Service Won't Start

```bash
# Check logs for errors
docker compose logs api

# Verify the database directory exists
ls -la data/

# Check environment variables
docker compose config
```

### Tunnel Connection Issues

```bash
# View cloudflared logs
docker compose logs cloudflared

# Common issues:
# 1. Invalid token - verify TUNNEL_TOKEN in .env.tunnel
# 2. Token not loaded - ensure you run: export $(cat .env.tunnel | xargs)
# 3. Network issues - check your firewall allows outbound connections to Cloudflare
```

### "TUNNEL_TOKEN not found" Error

```bash
# Make sure to export the environment variable before running docker compose
export $(cat .env.tunnel | xargs)
docker compose up -d

# Or use --env-file flag
docker compose --env-file .env.tunnel up -d
```

### DNS Not Resolving

```bash
# Check DNS propagation (may take a few minutes)
nslookup icp-mp.kalaj.org

# Verify public hostname configuration in Cloudflare dashboard
# Networks > Tunnels > icp-marketplace > Public Hostname tab
```

## Security Considerations

1. **Token Protection**: The `.env.tunnel` file contains a secret token and is automatically excluded from git via `.gitignore`

2. **Cloudflare Protection**: All traffic goes through Cloudflare's network, providing:
   - DDoS protection
   - Web Application Firewall (WAF)
   - Rate limiting
   - TLS encryption

3. **Container Security**: The API runs as a non-root user inside the container

4. **Token Rotation**: You can regenerate the tunnel token at any time from the Cloudflare dashboard

## Data Persistence

The SQLite database is stored in `./data/marketplace-prod.db` on your host machine:

- **Location**: `backend/data/marketplace-prod.db`
- **Automatic Creation**: Database file and schema are created automatically on first startup
- **Backups**: Simply copy the `data/` directory
- **Direct Access**: You can query the database directly with any SQLite client

```bash
# View database file
ls -lh data/marketplace-prod.db

# Backup database
cp -r data/ data-backup-$(date +%Y%m%d)/

# Query with sqlite3
sqlite3 data/marketplace-prod.db "SELECT COUNT(*) FROM scripts;"
```

## Production Recommendations

1. **Monitoring**: Set up Cloudflare Access logs and API monitoring
2. **Backups**: Regularly backup the `data/` directory (SQLite database)
3. **Updates**: Keep Docker images updated with `docker compose pull`
4. **Secrets Management**: Consider using Docker secrets or a secrets manager for production
5. **Rate Limiting**: Configure Cloudflare rate limiting rules for API protection
6. **Health Alerts**: Enable Cloudflare tunnel health notifications

## Alternative: Using Docker Secrets (Production)

For production environments, use Docker secrets instead of environment variables:

```yaml
# docker-compose.yml
services:
  cloudflared:
    secrets:
      - tunnel_token
    command: tunnel --no-autoupdate run --token $(cat /run/secrets/tunnel_token)

secrets:
  tunnel_token:
    file: ./secrets/tunnel_token.txt
```

## Cleanup

To completely remove the deployment:

```bash
# Stop and remove containers
docker compose down

# Remove volumes (including database)
docker compose down -v

# Delete tunnel from Cloudflare dashboard
# Networks > Tunnels > icp-marketplace > Delete
```

## Comparison: Token-Based vs. Credentials-Based Setup

| Feature | Token-Based (This Setup) | Credentials-Based |
|---------|-------------------------|-------------------|
| Local installation needed | ❌ No | ✅ Yes |
| Setup complexity | ⭐ Simple | ⭐⭐⭐ Complex |
| Configuration files | 1 file (`.env.tunnel`) | 3+ files |
| Tunnel management | Dashboard | CLI + Config files |
| Token rotation | Easy (dashboard) | Requires re-auth |
| Best for | Docker/Container deployments | Traditional server deployments |

## Related Documentation

- [Local Development](./LOCAL_DEVELOPMENT.md) - Run locally without Docker
- [API Documentation](./README.md) - API endpoints and usage
- [Quick Start](./QUICKSTART.md) - 5-minute setup guide

## Quick Reference Commands

```bash
# Start with token from file
export $(cat .env.tunnel | xargs) && docker compose up -d

# Start with explicit env file
docker compose --env-file .env.tunnel up -d

# View all logs
docker compose logs -f

# Test endpoint
curl https://icp-mp.kalaj.org/api/v1/health

# Stop everything
docker compose down

# Rebuild after code changes
export $(cat .env.tunnel | xargs) && docker compose up -d --build
```
