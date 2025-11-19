-- Account Profiles Migration (SQLite)
-- Implements the Account Profiles Design Specification

-- Accounts table
CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    contact_email TEXT,
    contact_telegram TEXT,
    contact_twitter TEXT,
    contact_discord TEXT,
    website_url TEXT,
    bio TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_accounts_username ON accounts(username);

-- Account public keys table
CREATE TABLE IF NOT EXISTS account_public_keys (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    public_key TEXT UNIQUE NOT NULL,
    ic_principal TEXT UNIQUE NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    added_at TEXT NOT NULL,
    disabled_at TEXT,
    disabled_by_key_id TEXT,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
    FOREIGN KEY (disabled_by_key_id) REFERENCES account_public_keys(id),
    UNIQUE(account_id, public_key)
);

CREATE INDEX IF NOT EXISTS idx_keys_account ON account_public_keys(account_id);
CREATE INDEX IF NOT EXISTS idx_keys_principal ON account_public_keys(ic_principal);
CREATE INDEX IF NOT EXISTS idx_keys_active ON account_public_keys(account_id, is_active);

-- Signature audit trail
CREATE TABLE IF NOT EXISTS signature_audit (
    id TEXT PRIMARY KEY,
    account_id TEXT,
    action TEXT NOT NULL,
    payload TEXT NOT NULL,
    signature TEXT NOT NULL,
    public_key TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    nonce TEXT NOT NULL,
    is_admin_action INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE INDEX IF NOT EXISTS idx_audit_nonce_time ON signature_audit(nonce, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_account ON signature_audit(account_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON signature_audit(created_at);
