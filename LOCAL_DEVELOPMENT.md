# Local Development with Cloudflare Workers

This guide covers setting up and running the ICP Script Marketplace with local Cloudflare Workers and D1 database for development and testing.

## Quick Start

Install dependencies with `scripts/bootstrap.sh`
Install just-build with `./install-just.sh`

1. **Start local Cloudflare Workers**: `just cloudflare-local-up`
2. **Initialize database**: `just cloudflare-local-init`
3. **Run Flutter app locally**: `just flutter-local`

## Detailed Setup

### 1. Local Cloudflare Workers Environment

The project uses Wrangler CLI for local Cloudflare Workers development:

```bash
# Start local Cloudflare Workers
just cloudflare-local-up

# API endpoint: http://localhost:8787
# Health check: http://localhost:8787/api/v1/health

# Stop when done
just cloudflare-local-down

# View logs
just cloudflare-local-logs

# Reset database (wipes all data)
just cloudflare-local-reset
```

### 2. Database Setup

Cloudflare Workers uses D1 database (SQLite-based):

```bash
# Initialize database with migrations
just cloudflare-local-init

# Run database migrations manually
cd cloudflare-api && wrangler d1 execute icp-marketplace-db --file=migrations/0001_initial_schema.sql

# View database contents
cd cloudflare-api && wrangler d1 execute icp-marketplace-db --command="SELECT * FROM scripts LIMIT 10"
```

### 3. Server-Deploy CLI Tool

The `server-deploy` CLI tool manages Cloudflare Workers deployment:

```bash
# Local development
server-deploy --target local <command>

# Production deployment
server-deploy --target prod <command>
```

Available commands:
- `bootstrap` - Set up fresh Cloudflare environment
- `deploy` - Deploy Workers and database migrations
- `config` - Show current configuration
- `test` - Test API connectivity
- `clean` - Clean up resources

### 4. Flutter App Configuration

The Flutter app automatically uses Cloudflare Workers:

```bash
# Local development (default)
just flutter-local  # Uses http://localhost:8787

# Production
just flutter-production  # Uses production Cloudflare Workers endpoint
```

Environment variables:
- `USE_CLOUDFLARE=true` (default) - Use Cloudflare Workers
- `CLOUDFLARE_ENDPOINT=http://localhost:8787` - Local endpoint
- `CLOUDFLARE_ENDPOINT=<production-url>` - Production endpoint

### 5. Complete Testing Workflow

```bash
# 1. Start local Cloudflare Workers
just cloudflare-local-up

# 2. Initialize database
just cloudflare-local-init

# 3. Test API endpoints
just cloudflare-local-test

# 4. Run Flutter app
just flutter-local

# 5. Clean up when done
just cloudflare-local-down
```

## Available Commands

### Cloudflare Workers Management
- `just cloudflare-local-up` - Start local Cloudflare Workers server
- `just cloudflare-local-down` - Stop local Cloudflare Workers server
- `just cloudflare-local-logs` - Show server logs
- `just cloudflare-local-reset` - Reset D1 database (deletes all data)

### CLI Commands (Local)
- `just cloudflare-local-init` - Initialize D1 database with migrations
- `just cloudflare-local-test` - Test local API endpoints
- `just cloudflare-local-config` - Show local configuration
- `server-deploy bootstrap` - Bootstrap fresh Cloudflare environment

### Flutter App
- `just flutter-local` - Run Flutter app with local Cloudflare Workers endpoint
- `just flutter-production` - Run Flutter app with production endpoint

## Architecture

### Local Environment
- **Cloudflare Workers API**: http://localhost:8787
- **D1 Database**: Local SQLite database managed by Wrangler
- **Health Check**: http://localhost:8787/api/v1/health
- **API Endpoints**: http://localhost:8787/api/*

### Configuration Management
- **Target Switching**: `--target` flag automatically switches endpoints
- **Config File**: Stored in `~/.config/icp-marketplace/config.json`
- **Environment Detection**: Flutter app detects local vs production automatically
- **Database Migrations**: Managed through `cloudflare-api/migrations/` directory

## Troubleshooting

### Common Issues

**Workers server not starting**
```
Error: Port 8787 already in use
```
- Solution: Kill existing process or use different port
- Run `lsof -ti:8787 | xargs kill -9` to kill process

**Database connection errors**
```
Error: D1 database binding not found
```
- Solution: Ensure database is initialized
- Run `just cloudflare-local-init` to create database

**Connection refused**
```
Error: Connection refused
```
- Solution: Verify Cloudflare Workers server is running
- Run `ps aux | grep wrangler` to check server status

**Flutter app can't connect**
- Solution: Verify local Cloudflare Workers is running
- Check API endpoint configuration in `AppConfig`
- Ensure firewall allows port 8787

### Debugging Commands

```bash
# Check server status
ps aux | grep wrangler

# Check server logs
just cloudflare-local-logs

# Test API connectivity
curl http://localhost:8787/api/v1/health
curl http://localhost:8787/api/v1/marketplace-stats

# Check configuration
just cloudflare-local-config

# Test all endpoints
just cloudflare-local-test
```

## Development Tips

### Environment Switching
- Use `--target local` for local development
- Use `--target prod` (default) for production deployment
- CLI automatically updates configuration file

### Testing Strategy
1. Test features locally first
2. Deploy to production when stable
3. Use separate databases for isolation

### Performance Considerations
- Local development is faster than production
- No network latency for API calls
- D1 database is optimized for fast local operations

## Security Notes

- Local Cloudflare Workers instance is not secured
- Use only for development/testing
- Don't commit production secrets
- Reset database regularly to clean test data

## Data Management

### Backup Local Data
```bash
# Export D1 database
cd cloudflare-api && wrangler d1 export icp-marketplace-db --output=backup.sql

# Restore D1 database
cd cloudflare-api && wrangler d1 import icp-marketplace-db --input=backup.sql
```

### Reset Environment
```bash
# Complete reset (wipes all data)
just cloudflare-local-reset

# Or manually
cd cloudflare-api && wrangler d1 execute icp-marketplace-db --command="DELETE FROM scripts;"
```

## API Endpoints Reference

### Available Endpoints
- `GET /api/v1/health` - Health check
- `GET /api/v1/marketplace-stats` - Marketplace statistics
- `GET /api/v1/scripts/featured` - Featured scripts
- `GET /api/v1/scripts/trending` - Trending scripts
- `POST /api/v1/scripts/search` - Search scripts
- `GET /api/v1/scripts/{id}` - Get script details
- `GET /api/v1/scripts/category/{category}` - Scripts by category

### Testing Endpoints
```bash
# Health check
curl http://localhost:8787/api/v1/health

# Get marketplace stats
curl http://localhost:8787/api/v1/marketplace-stats

# Search scripts
curl -X POST -H "Content-Type: application/json" \
  -d '{"query":"test","limit":5}' \
  http://localhost:8787/api/v1/scripts/search
```

## Integration with CI/CD

The target system makes it easy to integrate local testing into CI/CD pipelines:

```bash
# In CI pipeline
just cloudflare-local-up
just cloudflare-local-init
# Run tests
just cloudflare-local-down
```
