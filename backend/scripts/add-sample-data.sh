#!/bin/bash

# Add sample data to SQLite database for testing

set -e

echo "📝 Adding sample data to SQLite database..."

export DATABASE_URL="sqlite:./data/dev.db"

# Check if database exists
if [ ! -f "./data/dev.db" ]; then
    echo "❌ Database file not found. Run ./scripts/dev-setup.sh first."
    exit 1
fi

# Add sample scripts
sqlite3 ./data/dev.db << 'EOF'
-- Clear existing data
DELETE FROM reviews;
DELETE FROM scripts;

-- Sample scripts
INSERT INTO scripts (
    id, title, description, category, tags, lua_source, author_name, author_id,
    author_principal, author_public_key, upload_signature, canister_ids, icon_url,
    screenshots, version, compatibility, price, is_public, downloads, rating,
    review_count, created_at, updated_at
) VALUES
(
    'hello-world-001',
    'Hello World Script',
    'A simple hello world script that prints a greeting message',
    'utility',
    '["hello", "world", "greeting", "beginner"]',
    'print("Hello, World!")\nprint("Welcome to ICP Marketplace!")',
    'Alice Developer',
    'alice-123',
    '2vxsx-fae',
    'test-public-key-alice',
    'test-signature-hello-world',
    '["rrkah-fqaaa-aaaaa-aaaaq-cai"]',
    'https://picsum.photos/seed/hello/100/100.jpg',
    '["https://picsum.photos/seed/hello1/300/200.jpg", "https://picsum.photos/seed/hello2/300/200.jpg"]',
    '1.0.0',
    'All ICP Canisters',
    0.0,
    1,
    42,
    4.5,
    3,
    datetime('now', '-7 days'),
    datetime('now', '-7 days')
),
(
    'data-parser-002',
    'JSON Data Parser',
    'Parse and manipulate JSON data structures with ease',
    'data-processing',
    '["json", "parser", "data", "utilities"]',
    'local data = {"name": "John", "age": 30}\nprint("Parsed data:", data.name)',
    'Bob Coder',
    'bob-456',
    '3v5f3-hae',
    'test-public-key-bob',
    'test-signature-data-parser',
    '["be2us-64aaaa-aaaaa-aaaaq-cai"]',
    'https://picsum.photos/seed/parser/100/100.jpg',
    '["https://picsum.photos/seed/parser1/300/200.jpg"]',
    '2.1.0',
    'All ICP Canisters',
    1.99,
    1,
    128,
    4.8,
    12,
    datetime('now', '-3 days'),
    datetime('now', '-1 day')
),
(
    'game-score-003',
    'Game Score Tracker',
    'Track high scores and game statistics across sessions',
    'gaming',
    '["game", "score", "tracker", "statistics"]',
    '-- Score tracking implementation\nlocal scores = {}\nfunction addScore(player, score)\n  scores[player] = (scores[player] or 0) + score\nend',
    'GameDev Pro',
    'gamedev-789',
    '4w5t6-yae',
    'test-public-key-gamedev',
    'test-signature-game-score',
    '["ryjl3-tyaaa-aaaaa-aaaaq-cai"]',
    'https://picsum.photos/seed/game/100/100.jpg',
    '["https://picsum.photos/seed/game1/300/200.jpg", "https://picsum.photos/seed/game2/300/200.jpg"]',
    '1.5.2',
    'Games with state storage',
    4.99,
    1,
    256,
    4.2,
    8,
    datetime('now', '-1 day'),
    datetime('now', '-12 hours')
);

-- Sample reviews
INSERT INTO reviews (
    id, script_id, user_id, rating, comment, created_at, updated_at
) VALUES
(
    'review-001',
    'hello-world-001',
    'user-alpha',
    5,
    'Perfect for beginners! Very clear and well-documented.',
    datetime('now', '-6 days'),
    datetime('now', '-6 days')
),
(
    'review-002',
    'hello-world-001',
    'user-beta',
    4,
    'Great starting point. Would love to see more examples.',
    datetime('now', '-5 days'),
    datetime('now', '-5 days')
),
(
    'review-003',
    'data-parser-002',
    'user-gamma',
    5,
    'Excellent JSON parser. Saved me hours of coding time!',
    datetime('now', '-2 days'),
    datetime('now', '-2 days')
),
(
    'review-004',
    'data-parser-002',
    'user-delta',
    4,
    'Works well but documentation could be better.',
    datetime('now', '-1 day'),
    datetime('now', '-1 day')
),
(
    'review-005',
    'game-score-003',
    'user-epsilon',
    5,
    'Exactly what I needed for my game project!',
    datetime('now', '-10 hours'),
    datetime('now', '-10 hours')
);

EOF

echo "✅ Sample data added successfully!"
echo ""
echo "📊 Added:"
echo "  • 3 sample scripts"
echo "  • 5 sample reviews"
echo "  • Ratings between 4-5 stars"
echo ""
echo "🌐 Test the API:"
echo "  curl http://localhost:58000/api/v1/scripts"
echo "  curl http://localhost:58000/api/v1/scripts/hello-world-001"
