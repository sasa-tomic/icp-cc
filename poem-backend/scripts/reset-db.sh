#!/bin/bash

# Reset SQLite database for development
# Deletes all data while preserving schema

set -e

echo "🗑️ Resetting SQLite database..."

export DATABASE_URL="sqlite:./data/dev.db"

# Check if database exists
if [ ! -f "./data/dev.db" ]; then
    echo "❌ Database file not found. Run ./scripts/dev-setup.sh first."
    exit 1
fi

# Delete all data from tables
sqlite3 ./data/dev.db << 'EOF'
DELETE FROM reviews;
DELETE FROM scripts;
EOF

echo "✅ Database reset successfully!"
echo "📊 Database is now empty but schema is preserved."
echo ""
echo "💡 You can add sample data with: ./scripts/add-sample-data.sh"