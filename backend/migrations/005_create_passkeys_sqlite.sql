-- Passkey Authentication Migration (SQLite)
-- Implements PASSKEY_IMPLEMENTATION_PLAN.md

-- Passkeys table (WebAuthn credentials)
CREATE TABLE IF NOT EXISTS passkeys (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    credential_id BLOB NOT NULL UNIQUE,
    public_key BLOB NOT NULL,
    counter INTEGER NOT NULL DEFAULT 0,
    device_name TEXT,
    device_type TEXT CHECK (device_type IN ('platform', 'cross-platform')),
    created_at TEXT NOT NULL,
    last_used_at TEXT,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_passkeys_account ON passkeys(account_id);
CREATE INDEX IF NOT EXISTS idx_passkeys_credential ON passkeys(credential_id);

-- Recovery codes table (one-time use, Argon2id hashed)
CREATE TABLE IF NOT EXISTS recovery_codes (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    used INTEGER NOT NULL DEFAULT 0,
    used_at TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_recovery_account ON recovery_codes(account_id);

-- Encrypted vault table (zero-knowledge storage)
CREATE TABLE IF NOT EXISTS user_vaults (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL UNIQUE,
    encrypted_data BLOB NOT NULL,
    salt BLOB NOT NULL,
    nonce BLOB NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_vault_account ON user_vaults(account_id);

-- WebAuthn challenges (temporary, for registration/authentication)
CREATE TABLE IF NOT EXISTS webauthn_challenges (
    id TEXT PRIMARY KEY,
    account_id TEXT,
    challenge BLOB NOT NULL,
    challenge_type TEXT NOT NULL CHECK (challenge_type IN ('registration', 'authentication')),
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_challenge_expires ON webauthn_challenges(expires_at);
