# ICP Marketplace API - Rust + Poem Backend (Phase 1)

A minimal, robust REST API backend built with Rust and Poem framework, replacing the CloudFlare Worker implementation.

## ✨ Features

- **Lightweight & Fast**: Minimal dependencies, clean architecture
- **SQLite**: Simple local development with file-based database
- **Auto-migrations**: Database schema created automatically on startup
- **JSON API**: RESTful endpoints with proper error handling
- **CORS enabled**: Ready for frontend integration

## 🚀 Quick Start

### Prerequisites
- Rust 1.75+ (`rustup install stable`)

### Run Locally

```bash
cd poem-backend

# Copy environment config
cp .env.example .env

# Run the server (compiles and starts)
cargo run

# Or build release version for better performance
cargo build --release
./target/release/icp-marketplace-api
```

The API will be available at `http://127.0.0.1:8080`

## 📋 API Endpoints

### Health & Status
- `GET /api/v1/health` - Server health check
- `GET /api/v1/ping` - Simple ping test

### Scripts
- `GET /api/v1/scripts` - List all public scripts
  - Query params: `limit`, `offset`, `category`
- `GET /api/v1/scripts/:id` - Get specific script by ID
- `GET /api/v1/scripts/count` - Get total scripts count

### Statistics
- `GET /api/v1/marketplace-stats` - Get marketplace statistics
  - Returns: `totalScripts`, `totalDownloads`, `averageRating`

### Development
- `POST /api/dev/reset-database` - Reset database (development only)

## 🧪 Testing

```bash
# Test health endpoint
curl http://127.0.0.1:8080/api/v1/health | jq .

# Get all scripts
curl http://127.0.0.1:8080/api/v1/scripts | jq .

# Get marketplace stats
curl http://127.0.0.1:8080/api/v1/marketplace-stats | jq .

# Reset database (dev only)
curl -X POST http://127.0.0.1:8080/api/dev/reset-database | jq .
```

## 📁 Project Structure

```
poem-backend/
├── src/
│   └── main.rs          # All application code (clean & minimal)
├── data/
│   └── dev.db           # SQLite database file (auto-created)
├── Cargo.toml           # Rust dependencies
├── .env                 # Environment configuration
└── README.md            # This file
```

## ⚙️ Configuration

Edit `.env` file:

```bash
DATABASE_URL=sqlite:./data/dev.db
PORT=8080
ENVIRONMENT=development
RUST_LOG=info,icp_marketplace_api=debug
```

## 🔄 Phase 2 - PostgreSQL Support

To add PostgreSQL support in the future:

1. Add `postgres` feature to sqlx in Cargo.toml
2. Update database connection logic to support both SQLite and Postgres
3. Change `?N` parameter syntax to `$N` for Postgres compatibility
4. Set `DATABASE_URL=postgresql://...` in production

## 📊 Database Schema

### Scripts Table
```sql
CREATE TABLE scripts (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    lua_source TEXT NOT NULL,
    author_name TEXT NOT NULL,
    is_public INTEGER DEFAULT 1,
    rating REAL DEFAULT 0.0,
    downloads INTEGER DEFAULT 0,
    review_count INTEGER DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

## 🎯 Benefits Over CloudFlare Worker

- ✅ **No port conflicts** - runs on any free port
- ✅ **Simple local testing** - just `cargo run`
- ✅ **Better debugging** - standard Rust tooling
- ✅ **Faster iteration** - no deployment needed for testing
- ✅ **Type safety** - compile-time guarantees
- ✅ **Clean separation** - easy to test and maintain

## 📝 Example Response

```json
{
  "success": true,
  "data": {
    "scripts": [],
    "total": 0,
    "hasMore": false
  }
}
```

## 🐛 Troubleshooting

**Port already in use:**
```bash
# Kill existing process
pkill -f icp-marketplace-api
# Or change PORT in .env
```

**Database permission errors:**
```bash
chmod 755 data/
chmod 644 data/dev.db
```

**Clean rebuild:**
```bash
cargo clean
cargo build
```

## 📦 Dependencies

- **poem** - Modern, fast web framework
- **tokio** - Async runtime
- **sqlx** - SQL toolkit with compile-time checked queries
- **serde** - Serialization/deserialization
- **chrono** - Date/time handling

## 🚢 Next Steps

1. Add POST endpoints for creating scripts
2. Implement signature verification for writes
3. Add reviews functionality
4. Implement search with filters
5. Add rate limiting
6. Deploy to CloudFlare as a container

---

Built with ❤️ using Rust 🦀
