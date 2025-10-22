# ICP Script Marketplace Deployment Guide

This directory contains deployment tools for the ICP Script Marketplace backend infrastructure on Appwrite.

## Files Overview

### Python Deployment Script
- **`deploy.py`** - Main deployment script that replaces `deploy.sh`
- **`test_deploy.py`** - Unit tests for the deployment script
- **`requirements.txt`** - Python dependencies (minimal, mostly standard library)
- **`README_DEPLOYMENT.md`** - This file

### Configuration Files
- **`appwrite.json`** - Complete Appwrite configuration (database schema, functions)
- **`functions/`** - Cloud function source code
- **`deploy.sh`** - Legacy bash script (deprecated, use `deploy.py` instead)

## Quick Start

### 1. Install Dependencies

```bash
# Install Appwrite CLI (global)
npm install -g appwrite-cli

# Install Python dependencies (if any)
pip install -r requirements.txt

# Build Rust CLI tool
cd ../appwrite-cli && cargo build --release
```

### 2. Deploy to Appwrite

```bash
# Using Python script (recommended)
python deploy.py

# Or using Makefile
make appwrite-deploy

# Dry run to see what would be executed
python deploy.py --dry-run --verbose
make appwrite-deploy-dry-run

# Verbose deployment with detailed logging
python deploy.py --verbose
make appwrite-deploy-verbose
```

### 3. Test the Deployment

```bash
# Run unit tests
python test_deploy.py

# Or using Makefile
make appwrite-test

# Run all tests including deployment tests
make test
```

## Deployment Targets

The following Makefile targets are available for Appwrite operations:

```bash
# Setup all Appwrite deployment tools
make appwrite-setup

# Deploy marketplace infrastructure
make appwrite-deploy

# Deploy with dry-run (preview changes)
make appwrite-deploy-dry-run

# Deploy with verbose logging
make appwrite-deploy-verbose

# Test deployment configuration
make appwrite-test

# Start API server in development
make appwrite-api-server-dev

# Start API server in production
make appwrite-api-server

# Test API server
make appwrite-api-server-test
```

## Python Script Features

### Advantages over Bash Script

1. **Testable**: Unit tests for all components (`test_deploy.py`)
2. **Error Handling**: Proper exception handling with custom error types
3. **Configuration Management**: Centralized configuration with dataclasses
4. **Logging**: Structured logging with configurable verbosity
5. **Dry Run Mode**: Preview what would be executed
6. **Parameter Validation**: Input validation and sanitization
7. **Command Construction**: Robust command building with proper escaping

### Usage Options

```bash
python deploy.py --help                    # Show help
python deploy.py                          # Normal deployment
python deploy.py --dry-run                # Preview mode
python deploy.py --verbose                # Detailed logging
python deploy.py --dry-run --verbose      # Verbose dry run
```

### Configuration

Configuration is centralized in the `AppConfig` dataclass:

```python
@dataclass
class AppConfig:
    appwrite_endpoint: str = "https://fra.cloud.appwrite.io/v1"
    project_id: str = "68f7fc8b00255b20ed42"
    database_id: str = "marketplace_db"
    # ... other configuration
```

## Testing

### Unit Tests

The Python deployment script includes comprehensive unit tests:

```bash
# Run tests with unittest
python test_deploy.py

# Run tests with pytest (if installed)
pytest test_deploy.py -v

# Run tests with coverage
pytest test_deploy.py --cov=deploy --cov-report=html
```

### Test Coverage

- CLI detection and validation
- Command execution and error handling
- Configuration validation
- Attribute and index creation
- Collection and database setup
- Complete deployment sequence

### Mock Testing

Tests use Python's unittest.mock to avoid actual CLI calls:

```python
@patch('subprocess.run')
def test_create_database_new(self, mock_run):
    # Test database creation logic without calling actual CLI
    ...
```

## Error Handling

The deployment script includes robust error handling:

1. **Custom Exceptions**: `AppwriteDeploymentError` for deployment-specific errors
2. **Timeout Protection**: 5-minute timeout per command
3. **Graceful Cancellation**: Ctrl+C handling with cleanup
4. **Detailed Error Messages**: Contextual error information
5. **Retry Logic**: Can be added using tenacity library

## Security Considerations

1. **Input Validation**: All inputs validated and sanitized
2. **Command Injection Prevention**: Proper subprocess usage with argument lists
3. **Secret Management**: API keys handled via Appwrite CLI, not environment
4. **Permission Model**: Follows principle of least privilege

## Migration from Bash

To migrate from the old `deploy.sh` script:

1. **Replace** `./deploy.sh` with `python deploy.py`
2. **Update** CI/CD pipelines to use Python script
3. **Add** unit tests to your test suite
4. **Configure** logging and error monitoring

### Before (Bash)
```bash
#!/bin/bash
set -e
appwrite databases create $DATABASE_ID --name "Database"
```

### After (Python)
```bash
#!/usr/bin/env python3
from deploy import AppwriteDeployer, AppConfig
deployer = AppwriteDeployer(AppConfig())
deployer.deploy()
```

## Troubleshooting

### Common Issues

1. **Appwrite CLI not found**
   ```bash
   npm install -g appwrite-cli
   ```

2. **Authentication issues**
   ```bash
   appwrite account login
   ```

3. **Python version issues**
   ```bash
   # Requires Python 3.7+
   python --version
   ```

4. **Permission issues**
   ```bash
   chmod +x deploy.py
   ```

### Debug Mode

Enable detailed logging:

```bash
python deploy.py --verbose
```

### Dry Run Mode

Preview what would be executed:

```bash
python deploy.py --dry-run --verbose
```

## Contributing

When adding new features:

1. Add unit tests in `test_deploy.py`
2. Update documentation in `README_DEPLOYMENT.md`
3. Test with dry-run mode first
4. Follow existing code patterns
5. Update Makefile targets if needed

## Performance

- **Command Execution**: Efficient subprocess usage
- **Memory Usage**: Minimal memory footprint
- **Network Calls**: Limited to Appwrite CLI operations
- **Parallel Execution**: Can be enhanced for concurrent operations