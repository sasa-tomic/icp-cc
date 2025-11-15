#!/bin/bash

# Development setup script for ICP Marketplace API
# Sets up SQLite database and starts development server

set -e

echo "🚀 Setting up ICP Marketplace API development environment..."

# Create data directory
mkdir -p data

# Set environment variables
export DATABASE_URL="sqlite:./data/dev.db"
export PORT=58000
export ENVIRONMENT="development"
export RUST_LOG="info,icp_marketplace_api_poem=debug"

echo "📦 Installing dependencies..."
cargo install sqlx-cli --no-default-features --features native-tls,sqlite

echo "🗄️ Setting up SQLite database..."
# Run migrations for SQLite
sqlx database create --database-url "$DATABASE_URL" || echo "Database already exists"
sqlx migrate run --database-url "$DATABASE_URL" --source migrations

# Create some sample data if needed
echo "📝 Creating sample data..."
sqlite3 ./data/dev.db << 'EOF'
INSERT OR IGNORE INTO scripts (
    id, title, description, category, tags, lua_source, author_name, author_id,
    author_principal, author_public_key, upload_signature, canister_ids, icon_url,
    screenshots, version, compatibility, price, is_public, downloads, rating,
    review_count, created_at, updated_at
) VALUES (
    'sample-script-1',
    'Hello World Script',
    'A simple hello world script for testing',
    'utility',
    '["hello", "world", "test"]',
    'print("Hello, World!")',
    'Test Developer',
    'dev-123',
    '2vxsx-fae',
    'test-public-key',
    'test-signature',
    '["rrkah-fqaaa-aaaaa-aaaaq-cai"]',
    'https://example.com/icon.png',
    '["https://example.com/screenshot1.png"]',
    '1.0.0',
    'ICP Compatible',
    0.0,
    1,
    0,
    0.0,
    0,
    datetime('now'),
    datetime('now')
);
EOF

echo "✅ Development environment ready!"
echo ""
echo "🔧 Commands:"
echo "  Start server:     cargo run"
echo "  Reset database:  ./scripts/reset-db.sh"
echo "  Add sample data:  ./scripts/add-sample-data.sh"
echo ""
echo "🌐 Server will be available at: http://localhost:58000"
echo "📚 API endpoints:"
echo "  Health:          http://localhost:58000/api/v1/health"
echo "  Ping:            http://localhost:58000/api/v1/ping"
echo "  Scripts:         http://localhost:58000/api/v1/scripts"
echo ""
