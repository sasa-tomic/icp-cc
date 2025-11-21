-- Account Profiles Migration (PostgreSQL)
-- Implements the Account Profiles Design Specification

-- Accounts table
CREATE TABLE IF NOT EXISTS accounts (
    id VARCHAR(64) PRIMARY KEY,
    username VARCHAR(32) UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    contact_email TEXT,
    contact_telegram TEXT,
    contact_twitter TEXT,
    contact_discord TEXT,
    website_url TEXT,
    bio TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT username_format CHECK (username ~ '^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$')
);

CREATE INDEX IF NOT EXISTS idx_accounts_username ON accounts(username);

-- Account public keys table
CREATE TABLE IF NOT EXISTS account_public_keys (
    id VARCHAR(64) PRIMARY KEY,
    account_id VARCHAR(64) NOT NULL,
    public_key TEXT UNIQUE NOT NULL,
    ic_principal TEXT UNIQUE NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    added_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    disabled_at TIMESTAMP WITH TIME ZONE,
    disabled_by_key_id VARCHAR(64),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
    FOREIGN KEY (disabled_by_key_id) REFERENCES account_public_keys(id),
    UNIQUE(account_id, public_key)
);

CREATE INDEX IF NOT EXISTS idx_keys_account ON account_public_keys(account_id);
CREATE INDEX IF NOT EXISTS idx_keys_principal ON account_public_keys(ic_principal);
CREATE INDEX IF NOT EXISTS idx_keys_active ON account_public_keys(account_id, is_active);

-- Signature audit trail
CREATE TABLE IF NOT EXISTS signature_audit (
    id VARCHAR(64) PRIMARY KEY,
    account_id VARCHAR(64),
    action VARCHAR(50) NOT NULL,
    payload TEXT NOT NULL,
    signature TEXT NOT NULL,
    public_key TEXT NOT NULL,
    timestamp BIGINT NOT NULL,
    nonce VARCHAR(64) NOT NULL,
    is_admin_action BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE INDEX IF NOT EXISTS idx_audit_nonce_time ON signature_audit(nonce, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_account ON signature_audit(account_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON signature_audit(created_at);

-- Trigger to update updated_at timestamp for accounts
CREATE TRIGGER update_accounts_updated_at
    BEFORE UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
