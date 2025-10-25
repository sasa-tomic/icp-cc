# Local Development with Appwrite

This guide covers setting up and running the ICP Script Marketplace with a local Appwrite instance for development and testing.

## Quick Start

1. **Start local Appwrite instance**: `just appwrite-local-up`
2. **Initialize local configuration**: `just appwrite-local-init --project-id <ID> --api-key <KEY>`
3. **Deploy marketplace locally**: `just appwrite-local-deploy`
4. **Run Flutter app locally**: `just flutter-local`

## Detailed Setup

### 1. Local Appwrite Instance

The project includes a Docker Compose setup for running Appwrite locally:

```bash
# Start local Appwrite
just appwrite-local-up

# Access console at: http://localhost:48080/console
# API endpoint: http://localhost:48080/v1

# Stop when done
just appwrite-local-down

# View logs
just appwrite-local-logs

# Reset environment (wipes all data)
just appwrite-local-reset
```

### 2. Initial Project Setup

The local Appwrite instance requires manual project creation:

1. Open http://localhost:48080/console in browser
2. Create account or sign in
3. Create new project named "ICP Marketplace Local"
4. Note the Project ID and generate an API key
5. Initialize local configuration:
   ```bash
   just appwrite-local-init --project-id <YOUR_PROJECT_ID> --api-key <YOUR_API_KEY>
   ```

### 3. CLI Target System

The custom Appwrite CLI supports `--target` flag for seamless switching between environments:

```bash
# Local development
marketplace-deploy --target local <command>

# Production (default)
marketplace-deploy --target prod <command>
```

Available commands:
- `init` - Initialize configuration
- `deploy` - Deploy marketplace infrastructure
- `config` - Show current configuration
- `test` - Test connectivity
- `clean` - Clean up resources

### 4. Flutter App Configuration

The Flutter app uses environment variable for API endpoint:

```bash
# Local development
just flutter-local  # Uses http://localhost:48080/v1

# Production
just flutter-production  # Uses https://icp-autorun.appwrite.network/v1
```

### 5. Complete Testing Workflow

```bash
# 1. Start local Appwrite
just appwrite-local-up

# 2. Initialize and deploy
just appwrite-local-init --project-id <ID> --api-key <KEY>
just appwrite-local-deploy

# 3. Test configuration
just appwrite-local-test

# 4. Run Flutter app
just flutter-local

# 5. Clean up when done
just appwrite-local-down
```

## Available Commands

### Appwrite Instance Management
- `just appwrite-local-up` - Start local Appwrite containers
- `just appwrite-local-down` - Stop local Appwrite containers
- `just appwrite-local-logs` - Show container logs
- `just appwrite-local-reset` - Reset environment (deletes all data)

### CLI Commands (Local)
- `just appwrite-local-init` - Initialize local configuration
- `just appwrite-local-deploy` - Deploy to local Appwrite
- `just appwrite-local-test` - Test local configuration
- `just appwrite-local-config` - Show local configuration

### Flutter App
- `just flutter-local` - Run Flutter app with local endpoint
- `just flutter-production` - Run Flutter app with production endpoint

## Architecture

### Local Environment
- **Appwrite Console**: http://localhost:48080/console
- **Appwrite API**: http://localhost:48080/v1
- **Docker Network**: Internal containers communicate via Docker network
- **Data Persistence**: Volumes maintain data between restarts

### Configuration Management
- **Target Switching**: `--target` flag automatically switches endpoints
- **Config File**: Stored in `~/.config/icp-marketplace/config.json`
- **Environment Detection**: Flutter app detects local vs production automatically

## Troubleshooting

### Common Issues

**Project not found error**
```
HTTP 404 - Not Found: Project with the requested ID could not be found
```
- Solution: Create project in local Appwrite console first
- Ensure correct project ID in configuration

**Permission denied errors**
```
HTTP 401 - Unauthorized: User missing scope
```
- Solution: Check API key permissions
- Ensure API key has required scopes for operations

**Connection refused**
```
Error: Connection refused
```
- Solution: Verify Appwrite containers are running
- Run `docker ps | grep appwrite` to check container status


**Flutter app can't connect**
- Solution: Verify local Appwrite is running
- Check API endpoint configuration
- Ensure firewall allows port 48080

### Debugging Commands

```bash
# Check container status
docker ps | grep appwrite

# Check container logs
docker logs appwrite

# Test API connectivity
curl http://localhost:48080/v1/health

# Check configuration
just appwrite-local-config

# Test configuration
just appwrite-local-test
```

## Development Tips

### Environment Switching
- Use `--target local` for local development
- Use `--target prod` (default) for production deployment
- CLI automatically updates configuration file

### Testing Strategy
1. Test features locally first
2. Deploy to production when stable
3. Use different project IDs for isolation

### Performance Considerations
- Local development is faster than production
- No network latency for API calls
- Can test with realistic data volumes

## Security Notes

- Local Appwrite instance is not secured
- Use only for development/testing
- Don't commit production API keys
- Reset environment regularly to clean test data

## Data Management

### Backup Local Data
```bash
# Export database
docker exec appwrite-mariadb mysqldump -u root -p marketplace_db > backup.sql

# Restore database
docker exec -i appwrite-mariadb mysql -u root -p marketplace_db < backup.sql
```

### Reset Environment
```bash
# Complete reset (wipes all data)
just appwrite-local-reset

# Or manually
docker compose down -v
docker system prune -f
just appwrite-local-up
```

## Integration with CI/CD

The target system makes it easy to integrate local testing into CI/CD pipelines:

```bash
# In CI pipeline
just appwrite-local-up
just appwrite-local-deploy
# Run tests
just appwrite-local-down
```