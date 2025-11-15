# Local Development with Poem API Server

This guide covers setting up and running the ICP Script Marketplace with the local Poem-based API server for development and testing.

## Quick Start

Install dependencies with `scripts/bootstrap.sh`
Install just-build with `./install-just.sh`

1. **Start local API server**: `just api-up`
2. **Run Flutter tests**: `just test`
3. **Run Flutter app locally**: `just flutter-local`

## Detailed Setup

### 1. Local API Server Environment

The project uses a Rust-based Poem API server for local development:

```bash
# Start local API server (auto-assigns random port)
just api-up

# The server will start on a random port and save it to /tmp/icp-api.port
# Example output:
#   ==> ✅ API server is healthy and ready!
#   ==> API Endpoint: http://127.0.0.1:45123
#   ==> Health Check: http://127.0.0.1:45123/api/v1/health

# Stop when done
just api-down

# Restart the server
just api-restart

# View logs
just api-logs

# Test API endpoints
just api-test

# Reset database (wipes all data, development only)
just api-reset
```

### 2. Database Setup

The API server uses SQLite database:

```bash
# Database is automatically initialized on first startup
# No manual setup required!

# To reset the database:
just api-reset
```

### 3. Building the API Server

```bash
# Build in release mode for better performance
just api-build

# Run in development mode (foreground, with auto-reload)
just api-dev
```

### 4. Flutter App Configuration

The Flutter app automatically uses the API server via the port file:

```bash
# Local development (uses dynamic port from /tmp/icp-api.port)
just flutter-local

# For production
just flutter-production
```

The test helpers automatically read the port from `/tmp/icp-api.port`, so no manual configuration is needed.

### 5. Complete Testing Workflow

```bash
# 1. Start local API server
just api-up

# 2. Run all tests (Rust + Flutter)
just test

# 3. Run Flutter app for manual testing
just flutter-local

# 4. Clean up when done
just api-down
```

## Available Commands

### API Server Management
- `just api-up [port]` - Start API server (port=0 for random, default)
- `just api-down` - Stop API server
- `just api-restart` - Restart API server
- `just api-logs` - Show server logs
- `just api-test` - Test all API endpoints
- `just api-reset` - Reset database (development only)
- `just api-build` - Build server in release mode
- `just api-dev` - Run server in development mode (foreground)

### Testing
- `just test` - Run all tests (starts API server automatically)
- `just rust-tests` - Run only Rust tests
- `just flutter-tests` - Run only Flutter tests (with API server)

### Flutter App
- `just flutter-local` - Run Flutter app with local API server
- `just flutter-production` - Run Flutter app with production endpoint

## Architecture

### Local Environment
- **Poem API Server**: http://127.0.0.1:[random-port] (port stored in `/tmp/icp-api.port`)
- **SQLite Database**: `poem-backend/data/dev.db`
- **Health Check**: `http://127.0.0.1:[port]/api/v1/health`
- **API Endpoints**: `http://127.0.0.1:[port]/api/*`

### Dynamic Port Allocation
- Server binds to port 0 by default, which assigns a random available port
- Actual port is logged and saved to `/tmp/icp-api.port`
- Flutter tests automatically read the port file
- No port conflicts with other services!

## Troubleshooting

### Common Issues

**API server not starting**
```
Error: Failed to bind to address
```
- Solution: Check logs at `logs/api-server.log`
- Run `just api-down` to clean up any stale processes

**Port file not found**
```
Error: API server port file not found at /tmp/icp-api.port
```
- Solution: Start the API server with `just api-up`
- Verify it's running with `just api-test`

**Connection refused**
```
Error: Connection refused
```
- Solution: Verify API server is running
- Check `just api-logs` for errors
- Restart with `just api-restart`

**Tests failing**
- Solution: Ensure API server is running (`just api-up`)
- Check server logs: `just api-logs`
- Try resetting database: `just api-reset`

### Debugging Commands

```bash
# Check if server is running
cat /tmp/icp-api.port

# Test API connectivity
just api-test

# Or manually test endpoints
API_PORT=$(cat /tmp/icp-api.port)
curl http://127.0.0.1:$API_PORT/api/v1/health
curl http://127.0.0.1:$API_PORT/api/v1/marketplace-stats

# Check server logs
just api-logs

# Check full test output
cat logs/test-output.log
```

## Development Tips

### Fast Iteration
- Use `just api-dev` for development with live updates
- API server starts quickly (2-3 seconds in release mode)
- No build step needed between code changes in dev mode

### Testing Strategy
1. Write failing tests first (TDD)
2. Run `just test` frequently
3. Check `logs/test-output.log` for detailed errors
4. Use `just api-reset` to clean test data between runs

### Performance Considerations
- Release builds are much faster: `just api-build`
- SQLite is optimized for fast local operations
- No network latency for API calls
- Dynamic ports prevent conflicts

## Security Notes

- Local API server is not secured
- Use only for development/testing
- Don't commit production secrets
- Database resets are only available in development mode

## Data Management

### Backup Local Data
```bash
# SQLite database is at poem-backend/data/dev.db
cp poem-backend/data/dev.db poem-backend/data/backup.db

# Restore from backup
cp poem-backend/data/backup.db poem-backend/data/dev.db
just api-restart
```

### Reset Environment
```bash
# Reset database via API
just api-reset

# Or manually delete the database
just api-down
rm poem-backend/data/dev.db
just api-up
```

## API Endpoints Reference

### Available Endpoints
- `GET /api/v1/health` - Health check
- `GET /api/v1/ping` - Simple ping test
- `GET /api/v1/marketplace-stats` - Marketplace statistics
- `GET /api/v1/scripts` - List all public scripts (query: limit, offset, category)
- `GET /api/v1/scripts/:id` - Get script by ID
- `GET /api/v1/scripts/count` - Get total scripts count
- `POST /api/dev/reset-database` - Reset database (development only)

### Testing Endpoints
```bash
# Get the current port
API_PORT=$(cat /tmp/icp-api.port)

# Health check
curl http://127.0.0.1:$API_PORT/api/v1/health | jq .

# Get marketplace stats
curl http://127.0.0.1:$API_PORT/api/v1/marketplace-stats | jq .

# List scripts
curl http://127.0.0.1:$API_PORT/api/v1/scripts | jq .

# Get scripts count
curl http://127.0.0.1:$API_PORT/api/v1/scripts/count | jq .
```

## Integration with CI/CD

The justfile makes it easy to integrate local testing into CI/CD pipelines:

```bash
# In CI pipeline
just api-up
just test
just api-down
```

The tests automatically start/stop the API server, so you can also just run:

```bash
just test
```

