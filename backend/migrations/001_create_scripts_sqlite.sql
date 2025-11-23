-- Create scripts table (SQLite)
CREATE TABLE IF NOT EXISTS scripts (
    id TEXT PRIMARY KEY,
    slug TEXT NOT NULL,
    owner_account_id TEXT,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    tags TEXT, -- JSON as TEXT for SQLite
    lua_source TEXT NOT NULL,
    author_principal TEXT,
    author_public_key TEXT,
    upload_signature TEXT,
    canister_ids TEXT, -- JSON as TEXT for SQLite
    icon_url TEXT,
    screenshots TEXT, -- JSON as TEXT for SQLite
    version TEXT NOT NULL DEFAULT '1.0.0',
    compatibility TEXT,
    price REAL NOT NULL DEFAULT 0.0,
    is_public INTEGER NOT NULL DEFAULT 1 CHECK (is_public IN (0, 1)),
    downloads INTEGER NOT NULL DEFAULT 0,
    rating REAL NOT NULL DEFAULT 0.0,
    review_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted_at TEXT,
    FOREIGN KEY (owner_account_id) REFERENCES accounts(id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_scripts_category ON scripts(category);
CREATE INDEX IF NOT EXISTS idx_scripts_author_principal ON scripts(author_principal);
CREATE INDEX IF NOT EXISTS idx_scripts_is_public ON scripts(is_public);
CREATE INDEX IF NOT EXISTS idx_scripts_rating ON scripts(rating DESC);
CREATE INDEX IF NOT EXISTS idx_scripts_downloads ON scripts(downloads DESC);
CREATE INDEX IF NOT EXISTS idx_scripts_created_at ON scripts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scripts_price ON scripts(price);

-- Full-text search for SQLite
CREATE VIRTUAL TABLE IF NOT EXISTS scripts_fts USING fts5(
    title,
    description,
    category,
    content=scripts,
    content_rowid=rowid
);

-- Triggers for full-text search
CREATE TRIGGER IF NOT EXISTS scripts_fts_insert AFTER INSERT ON scripts BEGIN
    INSERT INTO scripts_fts(rowid, title, description, category)
    VALUES (new.rowid, new.title, new.description, new.category);
END;

CREATE TRIGGER IF NOT EXISTS scripts_fts_delete AFTER DELETE ON scripts BEGIN
    INSERT INTO scripts_fts(scripts_fts, rowid, title, description, category)
    VALUES ('delete', old.rowid, old.title, old.description, old.category);
END;

CREATE TRIGGER IF NOT EXISTS scripts_fts_update AFTER UPDATE ON scripts BEGIN
    INSERT INTO scripts_fts(scripts_fts, rowid, title, description, category)
    VALUES ('delete', old.rowid, old.title, old.description, old.category);
    INSERT INTO scripts_fts(rowid, title, description, category)
    VALUES (new.rowid, new.title, new.description, new.category);
END;

-- Trigger to update updated_at timestamp
CREATE TRIGGER IF NOT EXISTS update_scripts_updated_at
    AFTER UPDATE ON scripts
    FOR EACH ROW
BEGIN
    UPDATE scripts SET updated_at = datetime('now') WHERE id = NEW.id;
END;