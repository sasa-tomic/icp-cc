-- Passkey Authentication Migration
-- Implements PASSKEY_IMPLEMENTATION_PLAN.md

-- Passkeys table (WebAuthn credentials)
CREATE TABLE passkeys (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    credential_id BYTEA NOT NULL UNIQUE,
    public_key BYTEA NOT NULL,
    counter INTEGER NOT NULL DEFAULT 0,
    device_name VARCHAR(255),
    device_type VARCHAR(20) CHECK (device_type IN ('platform', 'cross-platform')),
    created_at TIMESTAMP NOT NULL,
    last_used_at TIMESTAMP
);

CREATE INDEX idx_passkeys_account ON passkeys(account_id);
CREATE INDEX idx_passkeys_credential ON passkeys(credential_id);

-- Recovery codes table (one-time use, Argon2id hashed)
CREATE TABLE recovery_codes (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    code_hash VARCHAR(255) NOT NULL,
    used BOOLEAN NOT NULL DEFAULT FALSE,
    used_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_recovery_account ON recovery_codes(account_id);

-- Encrypted vault table (zero-knowledge storage)
CREATE TABLE user_vaults (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE CASCADE,
    encrypted_data BYTEA NOT NULL,
    salt BYTEA NOT NULL,
    nonce BYTEA NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_vault_account ON user_vaults(account_id);

-- WebAuthn challenges (temporary, for registration/authentication)
CREATE TABLE webauthn_challenges (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) REFERENCES accounts(id) ON DELETE CASCADE,
    challenge BYTEA NOT NULL,
    challenge_type VARCHAR(20) NOT NULL CHECK (challenge_type IN ('registration', 'authentication')),
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_challenge_expires ON webauthn_challenges(expires_at);
