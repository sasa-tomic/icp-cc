# Quick Start

5-minute deployment guide for the ICP Marketplace API.

## Prerequisites
- Rust 1.91+ for local development
- Docker + Docker Compose for production
- Cloudflare account for production deployment

## Local Development (2 minutes)

```bash
cd poem-backend
cp .env.example .env
cargo run
# API available at http://127.0.0.1:8080
```

See [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md) for details.

## Production Deployment (5 minutes)

```bash
# 1. Create tunnel at https://one.dash.cloudflare.com/
# 2. Copy tunnel token
cp .env.tunnel.example .env.tunnel
# 3. Paste token in .env.tunnel
./scripts/start-tunnel.sh
# API live at https://icp-mp.kalaj.org
```

See [DOCKER_DEPLOYMENT.md](./DOCKER_DEPLOYMENT.md) for complete setup guide.
