-- Create identity profiles table (PostgreSQL)
CREATE TABLE IF NOT EXISTS identity_profiles (
    id VARCHAR(64) PRIMARY KEY,
    principal VARCHAR(255) NOT NULL UNIQUE,
    display_name VARCHAR(255) NOT NULL,
    username VARCHAR(255),
    contact_email VARCHAR(255),
    contact_telegram VARCHAR(255),
    contact_twitter VARCHAR(255),
    contact_discord VARCHAR(255),
    website_url VARCHAR(500),
    bio TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_keypair_profiles_principal
    ON identity_profiles(principal);

CREATE TRIGGER update_keypair_profiles_updated_at
    BEFORE UPDATE ON identity_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
