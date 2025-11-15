# Local Development Guide

This guide helps you set up a complete local development environment for the ICP Marketplace API using SQLite.

## 🚀 Quick Start

### 1. Set up the development environment

```bash
# Run the setup script (this handles everything)
./scripts/dev-setup.sh
```

This will:
- ✅ Create SQLite database (`./data/dev.db`)
- ✅ Run database migrations
- ✅ Create sample data
- ✅ Install necessary dependencies

### 2. Start the development server

```bash
# Start the server on port 8080
cargo run
```

The API will be available at `http://localhost:8080`

## 📋 Available Endpoints

### Health & Status
- `GET /api/v1/health` - Server health check
- `GET /api/v1/ping` - Simple ping test

### Scripts
- `GET /api/v1/scripts` - List all scripts
- `GET /api/v1/scripts/:id` - Get specific script
- `POST /api/v1/scripts` - Create new script
- `GET /api/v1/scripts/count` - Get total script count
- `GET /api/v1/scripts/category/:category` - Scripts by category

### Search & Discovery
- `GET /api/v1/scripts/search` - Search scripts
- `GET /api/v1/scripts/trending` - Trending scripts
- `GET /api/v1/scripts/featured` - Featured scripts
- `GET /api/v1/scripts/compatible` - Compatible scripts

### Reviews
- `GET /api/v1/scripts/:id/reviews` - Get script reviews
- `POST /api/v1/scripts/:id/reviews` - Create review

### Stats
- `GET /api/v1/marketplace-stats` - Marketplace statistics

### Development Tools
- `POST /api/dev/reset-database` - Reset all data (development only)

## 🛠️ Development Commands

### Database Management

```bash
# Reset database (clears all data, preserves schema)
./scripts/reset-db.sh

# Add sample data
./scripts/add-sample-data.sh

# Full setup (database + migrations + sample data)
./scripts/dev-setup.sh
```

### Running Tests

```bash
# Run all tests
cargo test

# Run integration tests specifically
cargo test integration_test

# Run tests with logging
RUST_LOG=debug cargo test
```

### Common Development Tasks

```bash
# Check code without running
cargo check

# Format code
cargo fmt

# Run linter
cargo clippy

# Build for release
cargo build --release
```

## 🧪 Testing with curl

### Basic Health Check
```bash
curl http://localhost:8080/api/v1/health
```

### Get All Scripts
```bash
curl http://localhost:8080/api/v1/scripts
```

### Get Marketplace Stats
```bash
curl http://localhost:8080/api/v1/marketplace-stats
```

### Reset Database
```bash
curl -X POST http://localhost:8080/api/dev/reset-database
```

## 📊 Database Schema

The local development uses SQLite with the following tables:

### Scripts
- `id` - Primary key (SHA256 hash)
- `title`, `description`, `category`
- `lua_source` - The actual script code
- `author_*` - Author information
- `rating`, `downloads`, `review_count`
- `created_at`, `updated_at`

### Reviews
- `script_id` - Foreign key to scripts
- `user_id` - Review author
- `rating` - 1-5 stars
- `comment` - Review text
- `created_at`, `updated_at`

## 🔧 Environment Variables

Copy `.env.example` to `.env` and modify:

```bash
# Database (SQLite for local development)
DATABASE_URL=sqlite:./data/dev.db

# Server
PORT=8080
ENVIRONMENT=development

# Logging
RUST_LOG=info,icp_marketplace_api_poem=debug
```

## 🐛 Troubleshooting

### Port Already in Use
```bash
# Find what's using port 8080
lsof -ti:8080

# Kill the process
kill -9 $(lsof -ti:8080)
```

### Database Issues
```bash
# Delete database file and recreate
rm ./data/dev.db
./scripts/dev-setup.sh
```

### Dependencies
```bash
# Clean and rebuild
cargo clean
cargo build
```

### Test Failures
```bash
# Ensure database is properly set up
./scripts/reset-db.sh
./scripts/add-sample-data.sh

# Run tests with verbose output
RUST_LOG=debug cargo test
```

## 📚 Sample API Responses

### Health Check Response
```json
{
  "success": true,
  "message": "ICP Marketplace API (Rust + Poem) is running",
  "environment": "development",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

### Scripts List Response
```json
{
  "success": true,
  "data": {
    "scripts": [
      {
        "id": "hello-world-001",
        "title": "Hello World Script",
        "description": "A simple hello world script",
        "category": "utility",
        "author_name": "Alice Developer",
        "rating": 4.5,
        "downloads": 42,
        "is_public": true
      }
    ],
    "total": 3,
    "hasMore": false
  }
}
```

## 🚀 Next Steps

Once you're comfortable with local development:

1. **Add new API endpoints** - Update `src/main.rs`
2. **Modify database schema** - Create new migration files
3. **Write tests** - Add tests to `tests/` directory
4. **Update Flutter app** - Point to `http://localhost:8080`
5. **Deploy to production** - Use the Dockerfile and Cloudflare Containers

## 🔄 Production Deployment

When ready for production:

1. Switch database URL to PostgreSQL
2. Remove development-only endpoints
3. Use the Dockerfile for container deployment
4. Deploy to Cloudflare Containers

```bash
# Build for production
docker build -t icp-marketplace-api .

# Deploy to Cloudflare
wrangler deploy
```