-- Scripts table
CREATE TABLE IF NOT EXISTS scripts (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL,
  tags TEXT, -- JSON array
  lua_source TEXT NOT NULL,
  author_name TEXT NOT NULL,
  author_id TEXT NOT NULL DEFAULT 'anonymous',
  author_principal TEXT, -- ICP principal of the script author
  author_public_key TEXT, -- Public key for signature verification
  upload_signature TEXT, -- Signature of the initial upload payload
  canister_ids TEXT, -- JSON array
  icon_url TEXT,
  screenshots TEXT, -- JSON array
  version TEXT NOT NULL DEFAULT '1.0.0',
  compatibility TEXT,
  price REAL NOT NULL DEFAULT 0.0,
  is_public BOOLEAN NOT NULL DEFAULT TRUE,
  downloads INTEGER NOT NULL DEFAULT 0,
  rating REAL NOT NULL DEFAULT 0,
  review_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Users table
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE,
  name TEXT NOT NULL,
  is_verified_developer BOOLEAN NOT NULL DEFAULT FALSE,
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
  FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(script_id, user_id)
);

-- Purchases table
CREATE TABLE IF NOT EXISTS purchases (
  id TEXT PRIMARY KEY,
  script_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  price REAL NOT NULL,
  purchase_date TEXT NOT NULL,
  FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Indexes for better performance
CREATE INDEX IF NOT EXISTS idx_scripts_category ON scripts(category);
CREATE INDEX IF NOT EXISTS idx_scripts_author ON scripts(author_id);
CREATE INDEX IF NOT EXISTS idx_scripts_public ON scripts(is_public);
CREATE INDEX IF NOT EXISTS idx_scripts_downloads ON scripts(downloads DESC);
CREATE INDEX IF NOT EXISTS idx_scripts_rating ON scripts(rating DESC);
CREATE INDEX IF NOT EXISTS idx_scripts_author_principal ON scripts(author_principal);
CREATE INDEX IF NOT EXISTS idx_reviews_script_id ON reviews(script_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_purchases_script_id ON purchases(script_id);
CREATE INDEX IF NOT EXISTS idx_purchases_user_id ON purchases(user_id);