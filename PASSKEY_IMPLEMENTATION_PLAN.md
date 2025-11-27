# Passkey Authentication Implementation Plan

**Status**: HIGH priority
**Architecture**: Hybrid - Passkey Auth + Password-Based Vault Encryption

## Why This Architecture

- ✅ Passkey for frequent logins (phishing-resistant, great UX)
- ✅ Separate vault password for credential encryption (zero-knowledge)
- ✅ Rock-solid recovery via password recovery codes
- ✅ Platform-independent (no Windows 11 PRF fragmentation issues)
- ✅ Losing passkey ≠ losing data

**Rejected**: Pure Passkey with PRF encryption (platform fragmentation, irreversible data loss risk)

## Implementation Stack

### Backend (Rust)
- `webauthn-rs` v0.5.2 - WebAuthn (security audited)
- `argon2` v0.5 - vault encryption + recovery codes
- `aes-gcm` v0.10 - credential storage

### Frontend (Flutter)
- `passkeys` v2.16.0 - Passkey auth (30k weekly downloads)
- Argon2id via FFI bridge to Rust

### Encryption Parameters (Bitwarden-level)
```
Argon2id: time=3, memory=64MB, parallelism=4, output=32 bytes
AES-GCM: key=256 bits, nonce=96 bits
```

## Database Schema (TODO)

```sql
-- Passkeys table
CREATE TABLE passkeys (
    id TEXT PRIMARY KEY,
    user_principal TEXT NOT NULL,
    credential_id BLOB NOT NULL UNIQUE,
    public_key BLOB NOT NULL,
    counter INTEGER NOT NULL DEFAULT 0,
    device_name TEXT,
    device_type TEXT,  -- "platform" or "cross-platform"
    created_at TEXT NOT NULL,
    last_used_at TEXT,
    FOREIGN KEY (user_principal) REFERENCES keypair_profiles(principal)
);

-- Recovery codes table
CREATE TABLE recovery_codes (
    id TEXT PRIMARY KEY,
    user_principal TEXT NOT NULL,
    code_hash TEXT NOT NULL,  -- Argon2id hash
    used INTEGER NOT NULL DEFAULT 0,
    used_at TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_principal) REFERENCES keypair_profiles(principal)
);

-- Encrypted vault table
CREATE TABLE user_vaults (
    id TEXT PRIMARY KEY,
    user_principal TEXT NOT NULL UNIQUE,
    encrypted_data BLOB NOT NULL,
    salt BLOB NOT NULL,       -- Argon2id salt (16 bytes)
    nonce BLOB NOT NULL,      -- AES-GCM nonce (12 bytes)
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (user_principal) REFERENCES keypair_profiles(principal)
);
```

## API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/passkey/register/start` | POST | Begin passkey registration |
| `/api/passkey/register/finish` | POST | Complete registration |
| `/api/passkey/authenticate/start` | POST | Begin login |
| `/api/passkey/authenticate/finish` | POST | Complete login |
| `/api/passkey/list` | GET | List user's passkeys |
| `/api/passkey/delete` | DELETE | Remove a passkey |
| `/api/vault/create` | POST | Create encrypted vault |
| `/api/vault/update` | PUT | Update vault |
| `/api/vault/get` | GET | Retrieve encrypted vault |
| `/api/recovery/generate` | POST | Generate recovery codes |
| `/api/recovery/verify` | POST | Verify code for password reset |

## User Flows

### Registration
```
1. Create keypair profile → 2. Register passkey (WebAuthn)
→ 3. Set vault password → 4. Display 12 recovery codes
→ 5. User confirms saved → 6. Prompt second passkey
```

### Login
```
1. Passkey auth → 2. Session token issued
→ 3. Prompt vault password → 4. Derive key (Argon2id)
→ 5. Fetch encrypted vault → 6. Decrypt client-side (AES-GCM)
```

### Recovery
```
1. Forgot password → 2. Enter recovery code
→ 3. Backend verifies + marks used → 4. Set new vault password
→ 5. Re-encrypt vault with new key
```

## Security Model

| Threat | Mitigation |
|--------|------------|
| Phishing | Passkey domain-bound |
| Server Breach | Zero-knowledge vault (no decryption key on server) |
| Password Guessing | Argon2id memory-hard KDF |
| Passkey Cloning | Signature counter verification |
| Recovery Code Leak | Hashed with Argon2id, one-time use |

## Platform Support

| Platform | Passkey | Vault | Notes |
|----------|---------|-------|-------|
| iOS 16+ | ✅ iCloud Keychain | ✅ | Full support |
| Android 9+ | ✅ Google Password Manager | ✅ | Full support |
| macOS 15+ | ✅ iCloud Keychain | ✅ | Full support |
| Windows 11 | ✅ Windows Hello | ✅ | Full support |
| Web (Chrome/Safari) | ✅ | ✅ | Full support |
| Linux | ⚠️ Hardware keys only | ✅ | Limited passkey |

## References

- [webauthn-rs docs](https://docs.rs/webauthn-rs/)
- [passkeys Flutter package](https://pub.dev/packages/passkeys)
- [WebAuthn W3C Spec](https://www.w3.org/TR/webauthn-2/)
- [Argon2 RFC 9106](https://datatracker.ietf.org/doc/html/rfc9106)
