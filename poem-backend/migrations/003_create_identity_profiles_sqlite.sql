-- Create identity profiles table (SQLite)
CREATE TABLE IF NOT EXISTS identity_profiles (
    id TEXT PRIMARY KEY,
    principal TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    username TEXT,
    contact_email TEXT,
    contact_telegram TEXT,
    contact_twitter TEXT,
    contact_discord TEXT,
    website_url TEXT,
    bio TEXT,
    metadata TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_identity_profiles_principal
    ON identity_profiles(principal);

CREATE TRIGGER IF NOT EXISTS update_identity_profiles_updated_at
    AFTER UPDATE ON identity_profiles
    FOR EACH ROW
BEGIN
    UPDATE identity_profiles
    SET updated_at = datetime('now')
    WHERE id = NEW.id;
END;
