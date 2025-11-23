-- Create scripts table
CREATE TABLE IF NOT EXISTS scripts (
    id VARCHAR(64) PRIMARY KEY,
    slug VARCHAR(255) NOT NULL,
    owner_account_id VARCHAR(255),
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    category VARCHAR(100) NOT NULL,
    tags JSONB,
    lua_source TEXT NOT NULL,
    author_principal VARCHAR(255),
    author_public_key TEXT,
    upload_signature TEXT,
    canister_ids JSONB,
    icon_url VARCHAR(500),
    screenshots JSONB,
    version VARCHAR(50) NOT NULL DEFAULT '1.0.0',
    compatibility VARCHAR(100),
    price DECIMAL(10,2) NOT NULL DEFAULT 0.0,
    is_public BOOLEAN NOT NULL DEFAULT true,
    downloads INTEGER NOT NULL DEFAULT 0,
    rating DECIMAL(3,2) NOT NULL DEFAULT 0.0,
    review_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
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

-- Full-text search index
CREATE INDEX IF NOT EXISTS idx_scripts_search ON scripts USING GIN (
    to_tsvector('english', title || ' ' || description)
);

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_scripts_updated_at
    BEFORE UPDATE ON scripts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();