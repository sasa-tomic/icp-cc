-- Initial schema for ICP Script Marketplace
-- Compatible with Cloudflare D1 (SQLite)

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT,
    name TEXT NOT NULL,
    is_verified_developer BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Scripts table
CREATE TABLE IF NOT EXISTS scripts (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    tags TEXT, -- JSON array
    lua_source TEXT NOT NULL,
    author_name TEXT NOT NULL,
    author_id TEXT NOT NULL,
    author_principal TEXT,
    author_public_key TEXT,
    upload_signature TEXT,
    canister_ids TEXT, -- JSON array
    icon_url TEXT,
    screenshots TEXT, -- JSON array
    version TEXT NOT NULL DEFAULT '1.0.0',
    compatibility TEXT,
    price REAL NOT NULL DEFAULT 0.0,
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    downloads INTEGER NOT NULL DEFAULT 0,
    rating REAL NOT NULL DEFAULT 0.0,
    review_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Reviews table
CREATE TABLE IF NOT EXISTS reviews (
    id TEXT PRIMARY KEY,
    script_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,

    -- Foreign key constraints (D1 supports them)
    FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,

    -- Ensure one review per user per script
    UNIQUE(script_id, user_id)
);

-- Purchases table
CREATE TABLE IF NOT EXISTS purchases (
    id TEXT PRIMARY KEY,
    script_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    price REAL NOT NULL,
    purchase_date TEXT NOT NULL,

    -- Foreign key constraints
    FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,

    -- Ensure one purchase per user per script
    UNIQUE(script_id, user_id)
);

-- Script stats table (for analytics and trending)
CREATE TABLE IF NOT EXISTS script_stats (
    id TEXT PRIMARY KEY,
    script_id TEXT NOT NULL UNIQUE,
    views INTEGER NOT NULL DEFAULT 0,
    downloads INTEGER NOT NULL DEFAULT 0,
    daily_downloads INTEGER NOT NULL DEFAULT 0,
    weekly_downloads INTEGER NOT NULL DEFAULT 0,
    monthly_downloads INTEGER NOT NULL DEFAULT 0,
    last_downloaded_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,

    -- Foreign key constraint
    FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE
);

-- Create indexes separately for better performance
CREATE INDEX IF NOT EXISTS idx_scripts_author_id ON scripts(author_id);
CREATE INDEX IF NOT EXISTS idx_scripts_category ON scripts(category);
CREATE INDEX IF NOT EXISTS idx_scripts_is_public ON scripts(is_public);
CREATE INDEX IF NOT EXISTS idx_scripts_created_at ON scripts(created_at);
CREATE INDEX IF NOT EXISTS idx_scripts_downloads ON scripts(downloads);
CREATE INDEX IF NOT EXISTS idx_scripts_rating ON scripts(rating);
CREATE INDEX IF NOT EXISTS idx_scripts_price ON scripts(price);

CREATE INDEX IF NOT EXISTS idx_reviews_script_id ON reviews(script_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rating ON reviews(rating);
CREATE INDEX IF NOT EXISTS idx_reviews_created_at ON reviews(created_at);

CREATE INDEX IF NOT EXISTS idx_purchases_script_id ON purchases(script_id);
CREATE INDEX IF NOT EXISTS idx_purchases_user_id ON purchases(user_id);
CREATE INDEX IF NOT EXISTS idx_purchases_purchase_date ON purchases(purchase_date);

CREATE INDEX IF NOT EXISTS idx_script_stats_downloads ON script_stats(downloads);
CREATE INDEX IF NOT EXISTS idx_script_stats_daily_downloads ON script_stats(daily_downloads);
CREATE INDEX IF NOT EXISTS idx_script_stats_weekly_downloads ON script_stats(weekly_downloads);
CREATE INDEX IF NOT EXISTS idx_script_stats_monthly_downloads ON script_stats(monthly_downloads);
CREATE INDEX IF NOT EXISTS idx_script_stats_last_downloaded ON script_stats(last_downloaded_at);

-- Insert initial system user (for system operations)
INSERT OR IGNORE INTO users (
    id,
    name,
    is_verified_developer,
    created_at,
    updated_at
) VALUES (
    'system',
    'System User',
    TRUE,
    datetime('now'),
    datetime('now')
);