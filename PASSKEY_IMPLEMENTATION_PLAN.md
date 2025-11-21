# Passkey Authentication Implementation Plan

**Status**: Deferred to Phase 2 (after UX improvements)
**Research Date**: 2025-11-14
**Target Timeline**: 3-4 weeks for full implementation

---

## Executive Decision

**Chosen Architecture**: Hybrid Approach - Passkey Authentication + Password-Based Vault Encryption

### Why This Works
- ✅ Passkey for frequent logins (phishing-resistant, great UX)
- ✅ Separate vault password for credential encryption (zero-knowledge)
- ✅ Rock-solid recovery via password recovery codes
- ✅ Platform-independent (no Windows 11 PRF fragmentation issues)
- ✅ Separation of concerns: losing passkey ≠ losing data

### Rejected Alternative: Pure Passkey with PRF Encryption
- ❌ Platform fragmentation (Windows 11 users excluded)
- ❌ High complexity (RSA key management per passkey)
- ❌ Irreversible data loss risk if all passkeys deleted
- ❌ Library support unclear for PRF extension
- ❌ Not "rock-solid" recovery as user required

---

## Implementation Stack

### Backend (Rust)
- **WebAuthn**: `webauthn-rs` v0.5.2 (production-ready, security audited)
- **Password Hashing**: `argon2` v0.5 for vault encryption + recovery codes
- **Encryption**: `aes-gcm` v0.10 for credential storage
- **Random**: `rand` v0.8 for recovery code generation

### Frontend (Flutter)
- **Passkey Auth**: `passkeys` package v2.16.0 (30k weekly downloads, actively maintained)
- **Vault Encryption**: Argon2id via FFI bridge to Rust or `pointycastle` package
- **Minimum**: Flutter 3.19.0

### Parameters (Bitwarden-Level Security)
```rust
// Argon2id configuration
time_cost: 3 iterations
memory_cost: 64 MB
parallelism: 4
output_length: 32 bytes (256-bit key)

// AES-GCM encryption
key_size: 256 bits
nonce_size: 96 bits
```

---

## Database Schema (Already Created)

### `passkeys` Table
```sql
CREATE TABLE passkeys (
    id TEXT PRIMARY KEY,
    user_principal TEXT NOT NULL,
    credential_id BLOB NOT NULL UNIQUE,       -- WebAuthn credential ID
    public_key BLOB NOT NULL,                 -- COSE public key
    counter INTEGER NOT NULL DEFAULT 0,        -- Signature counter (anti-cloning)
    device_name TEXT,                         -- User-friendly name ("iPhone 15")
    device_type TEXT,                         -- "platform" or "cross-platform"
    created_at TEXT NOT NULL,
    last_used_at TEXT,
    FOREIGN KEY (user_principal) REFERENCES keypair_profiles(principal)
);
```

**Indexes**: `user_principal`, `credential_id`

### `recovery_codes` Table
```sql
CREATE TABLE recovery_codes (
    id TEXT PRIMARY KEY,
    user_principal TEXT NOT NULL,
    code_hash TEXT NOT NULL,                  -- Argon2id hash of code
    used INTEGER NOT NULL DEFAULT 0,          -- Boolean: 0=unused, 1=used
    used_at TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_principal) REFERENCES keypair_profiles(principal)
);
```

**Indexes**: `user_principal`

### `user_vaults` Table
```sql
CREATE TABLE user_vaults (
    id TEXT PRIMARY KEY,
    user_principal TEXT NOT NULL UNIQUE,
    encrypted_data BLOB NOT NULL,             -- AES-GCM encrypted credentials
    salt BLOB NOT NULL,                       -- Argon2id salt (16 bytes)
    nonce BLOB NOT NULL,                      -- AES-GCM nonce (12 bytes)
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (user_principal) REFERENCES keypair_profiles(principal)
);
```

**Indexes**: `user_principal` (unique)

---

## Implementation Phases

### Phase 1: Backend (1.5 weeks)

#### 1.1 WebAuthn Integration
- [ ] Create `WebauthnBuilder` configuration with relying party details
- [ ] Implement `/api/passkey/register/start` endpoint
  - Generate challenge
  - Store challenge in temporary session/cache
  - Return `PublicKeyCredentialCreationOptions`
- [ ] Implement `/api/passkey/register/finish` endpoint
  - Verify attestation
  - Store credential in `passkeys` table
  - Link to user keypair
- [ ] Implement `/api/passkey/authenticate/start` endpoint
  - Generate challenge for existing credentials
  - Return `PublicKeyCredentialRequestOptions`
- [ ] Implement `/api/passkey/authenticate/finish` endpoint
  - Verify assertion
  - Update signature counter
  - Issue session token (JWT or similar)

#### 1.2 Vault Encryption Utilities
- [ ] Implement `derive_key_from_password(password, salt) -> [u8; 32]`
  - Use Argon2id with configured parameters
  - Generate random 16-byte salt on first setup
- [ ] Implement `encrypt_vault(data, key, nonce) -> Vec<u8>`
  - Use AES-256-GCM
  - Generate random 12-byte nonce
- [ ] Implement `decrypt_vault(encrypted, key, nonce) -> Result<Vec<u8>>`
  - Verify authentication tag
  - Return decrypted data or error

#### 1.3 Recovery Code System
- [ ] Implement `generate_recovery_codes(count: usize) -> Vec<String>`
  - Generate 12 random base32-encoded codes (format: `XXXX-XXXX-XXXX-XXXX`)
  - Cryptographically secure random (use `rand::thread_rng()`)
- [ ] Implement `hash_recovery_code(code) -> String`
  - Use Argon2id to hash before storage
- [ ] Implement `/api/recovery/verify` endpoint
  - Verify provided code against hash
  - Mark code as used (one-time use only)
  - Allow vault password reset on success

#### 1.4 API Endpoints Summary
| Endpoint                           | Method | Purpose                                 |
|------------------------------------|--------|-----------------------------------------|
| `/api/passkey/register/start`      | POST   | Begin passkey registration              |
| `/api/passkey/register/finish`     | POST   | Complete passkey registration           |
| `/api/passkey/authenticate/start`  | POST   | Begin passkey login                     |
| `/api/passkey/authenticate/finish` | POST   | Complete passkey login                  |
| `/api/passkey/list`                | GET    | List user's registered passkeys         |
| `/api/passkey/delete`              | DELETE | Remove a passkey                        |
| `/api/vault/create`                | POST   | Create encrypted vault                  |
| `/api/vault/update`                | PUT    | Update vault data                       |
| `/api/vault/get`                   | GET    | Retrieve encrypted vault blob           |
| `/api/recovery/generate`           | POST   | Generate recovery codes (one-time)      |
| `/api/recovery/verify`             | POST   | Verify recovery code for password reset |

---

### Phase 2: Frontend (1.5 weeks)

#### 2.1 Passkey Registration Flow
- [ ] Platform-specific setup:
  - iOS: Create `.well-known/apple-app-site-association` (AASA file)
  - Android: Create `.well-known/assetlinks.json` (Digital Asset Links)
  - Web: Configure domain in WebAuthn builder
- [ ] Create `PasskeyService` in Flutter
  - Use `passkeys` package
  - Handle registration challenge flow
  - Handle authentication challenge flow
- [ ] Create registration UI:
  - "Set Up Passkey" button
  - Device name input (optional, default to device model)
  - Success confirmation with prompt to add second passkey
- [ ] Create authentication UI:
  - "Sign In with Passkey" button
  - Conditional UI (show only if passkey available)
  - Fallback to traditional auth if needed

#### 2.2 Vault Password UI
- [ ] Create vault setup screen (first-time):
  - Password input with strength meter
  - Enforce minimum requirements (16 chars, complexity)
  - Confirmation input
  - Warning about irrecoverability
- [ ] Create vault unlock screen:
  - Password input
  - "Forgot Password" → recovery code flow
  - Decrypt vault on success, show credentials
- [ ] Implement Argon2id key derivation:
  - **Option A**: FFI bridge to Rust (faster, recommended)
  - **Option B**: Use `pointycastle` package (pure Dart, slower)
- [ ] Implement AES-GCM decryption:
  - Use `cryptography` or `encrypt` package
  - Decrypt in memory only, never persist

#### 2.3 Recovery Code Display
- [ ] Create recovery code display screen (shown once after vault setup):
  - Display all 12 codes in grid format
  - "Download" button (saves `.txt` file)
  - "Print" button (opens print dialog)
  - "Copy All" button
  - Multiple checkboxes confirming user saved codes
  - Don't allow dismissal until confirmed
- [ ] Create recovery code input screen:
  - Text input for code (format `XXXX-XXXX-XXXX-XXXX`)
  - Verify with backend
  - On success: allow new vault password setup

#### 2.4 Passkey Management UI
- [ ] Create "Security Settings" screen:
  - List all registered passkeys with device name, last used
  - "Add Passkey" button
  - Delete passkey (with confirmation, require at least 1 remaining)
  - Alert when new passkey registered (email/push notification)

---

### Phase 3: Testing & Polish (1 week)

#### 3.1 Cross-Platform Testing
- [ ] Test on iOS physical device (simulator passkey support limited)
- [ ] Test on Android physical device
- [ ] Test on web (Chrome, Safari, Firefox)
- [ ] Test passkey sync across devices (iCloud Keychain, Google Password Manager)
- [ ] Test recovery code flow (generate → use → reset password)

#### 3.2 Error Handling
- [ ] Handle passkey not supported (old browsers/OS)
- [ ] Handle user cancellation during passkey prompt
- [ ] Handle invalid recovery code (show remaining attempts)
- [ ] Handle vault decryption failure (wrong password)
- [ ] Handle all passkeys deleted scenario

#### 3.3 Security Audit
- [ ] Verify salt uniqueness per user
- [ ] Verify nonce uniqueness per encryption
- [ ] Verify recovery codes are hashed (never plaintext)
- [ ] Verify vault password never transmitted to server
- [ ] Verify encrypted data at rest (check database directly)
- [ ] Test signature counter anti-cloning protection
- [ ] Test session token expiration

#### 3.4 User Education
- [ ] Add tooltips explaining passkeys ("What's a passkey?")
- [ ] Add warnings about vault password irrecoverability
- [ ] Add inline help for recovery code storage
- [ ] Create onboarding flow for first-time users
- [ ] Add "Passkeys Doctor" diagnostic tool (from `passkeys` package)

---

## Architecture Diagrams

### User Flows

#### Registration Flow
```
1. User signs up
   ↓
2. Create keypair profile in DB
   ↓
3. [Passkey Setup] Register first passkey (WebAuthn flow)
   ↓
4. [Vault Setup] Set vault password
   ↓
5. Generate & display 12 recovery codes
   ↓
6. User confirms codes saved
   ↓
7. Prompt to add second passkey (recommended)
   ↓
8. Complete
```

#### Login Flow
```
1. User clicks "Sign In"
   ↓
2. Passkey authentication (WebAuthn challenge/response)
   ↓
3. Backend verifies signature, issues session token
   ↓
4. [If accessing vault] Prompt for vault password
   ↓
5. Derive key from password + user's salt
   ↓
6. Fetch encrypted vault from server
   ↓
7. Decrypt vault client-side (AES-GCM)
   ↓
8. Display credentials in memory (never persist decrypted)
```

#### Recovery Flow
```
1. User forgets vault password
   ↓
2. Click "Forgot Password" on vault unlock screen
   ↓
3. Enter one of 12 recovery codes
   ↓
4. Backend verifies code hash, marks as used
   ↓
5. Allow user to set new vault password
   ↓
6. Re-derive key with new password + new salt
   ↓
7. Re-encrypt vault data with new key
   ↓
8. Save updated vault to server
```

### Data Flow: Vault Encryption

```
┌─────────────────────────────────────────────────────────────────┐
│ CLIENT SIDE                                                     │
│                                                                 │
│ User Password → Argon2id(password, salt) → 256-bit key         │
│                                              ↓                  │
│ Credentials (JSON) → AES-GCM-Encrypt(key) → Encrypted Blob     │
│                                              ↓                  │
│                                     Send to Server              │
└─────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────┐
│ SERVER SIDE (Zero-Knowledge)                                    │
│                                                                 │
│ Store: encrypted_data (BLOB)                                   │
│        salt (BLOB) - used for Argon2id                         │
│        nonce (BLOB) - used for AES-GCM                         │
│                                                                 │
│ Server NEVER sees: plaintext password or plaintext credentials │
└─────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────┐
│ CLIENT SIDE (Retrieval)                                         │
│                                                                 │
│ Fetch encrypted_data + salt + nonce                            │
│                    ↓                                            │
│ User Password → Argon2id(password, salt) → 256-bit key         │
│                    ↓                                            │
│ AES-GCM-Decrypt(encrypted_data, key, nonce) → Credentials      │
│                    ↓                                            │
│ Display in memory (never persist decrypted)                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Security Considerations

### Threat Model
| Threat                 | Mitigation                                                     |
|------------------------|----------------------------------------------------------------|
| **Phishing**           | Passkey authentication (domain-bound, can't be phished)        |
| **Server Breach**      | Zero-knowledge vault encryption (server has no decryption key) |
| **MITM Attack**        | HTTPS + WebAuthn origin verification                           |
| **Password Guessing**  | Argon2id memory-hard KDF (slow brute-force)                    |
| **Credential Theft**   | Encrypted at rest, decrypted only in memory                    |
| **Passkey Cloning**    | Signature counter verification (detects duplicates)            |
| **Recovery Code Leak** | Hashed with Argon2id, one-time use                             |

### Key Management
- **Passkey Private Key**: Never leaves device (stored in platform authenticator)
- **Vault Encryption Key**: Derived from password, never stored (ephemeral)
- **Recovery Codes**: Hashed before storage, user responsible for offline backup

### Audit Trail
- Log passkey registrations (device type, timestamp)
- Log authentication attempts (success/failure, IP, device)
- Alert users on new passkey registration (email/push)
- Alert users on recovery code usage (potential account takeover)
- Log vault access attempts (timestamp, success/failure)

---

## Platform Support Matrix

| Platform          | Passkey Support           | Vault Encryption   | Recovery Codes |
|-------------------|---------------------------|--------------------|----------------|
| **iOS 16+**       | ✅ iCloud Keychain         | ✅ Argon2id via FFI | ✅ Full support |
| **Android 9+**    | ✅ Google Password Manager | ✅ Argon2id via FFI | ✅ Full support |
| **Web (Chrome)**  | ✅ Platform authenticator  | ✅ WebCrypto API    | ✅ Full support |
| **Web (Safari)**  | ✅ Platform authenticator  | ✅ WebCrypto API    | ✅ Full support |
| **Web (Firefox)** | ⚠️ Partial support        | ✅ WebCrypto API    | ✅ Full support |
| **macOS 15+**     | ✅ iCloud Keychain         | ✅ Argon2id via FFI | ✅ Full support |
| **Windows 11**    | ✅ Windows Hello           | ✅ Argon2id via FFI | ✅ Full support |
| **Linux**         | ⚠️ Hardware keys only     | ✅ Argon2id via FFI | ✅ Full support |

**Note**: PRF extension for pure passkey-based encryption NOT used due to fragmentation.

---

## Library Documentation

### `webauthn-rs` (Backend)
- **Repository**: https://github.com/kanidm/webauthn-rs
- **Docs**: https://docs.rs/webauthn-rs/
- **Version**: 0.5.2
- **Security**: Audited by SUSE Product Security
- **Examples**: See `examples/` directory in repo

### `passkeys` (Frontend)
- **Package**: https://pub.dev/packages/passkeys
- **Docs**: https://pub.dev/documentation/passkeys/
- **Version**: 2.16.0
- **Setup Guides**:
  - iOS: https://pub.dev/packages/passkeys#ios-setup
  - Android: https://pub.dev/packages/passkeys#android-setup
  - Web: https://pub.dev/packages/passkeys#web-setup
- **Diagnostics**: Built-in "Passkeys Doctor" tool for troubleshooting

### Argon2id Parameters Reference
- **OWASP Recommendation**: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#argon2id
- **Bitwarden Security**: Similar to our chosen parameters (time=3, mem=64MB)
- **Rust Crate**: https://docs.rs/argon2/

---

## Testing Checklist

### Functional Testing
- [ ] User can register first passkey
- [ ] User can register second passkey (different device)
- [ ] User can log in with passkey
- [ ] User can delete passkey (if ≥2 exist)
- [ ] User can set vault password
- [ ] User can unlock vault with correct password
- [ ] User cannot unlock vault with wrong password
- [ ] User receives 12 recovery codes after vault setup
- [ ] User can use recovery code to reset vault password
- [ ] Recovery code becomes invalid after one use
- [ ] User cannot use same recovery code twice

### Security Testing
- [ ] Server never receives plaintext vault password
- [ ] Server never receives plaintext credentials
- [ ] Encrypted vault blob is unreadable without password
- [ ] Different users have different salts
- [ ] Different encryption operations have different nonces
- [ ] Recovery codes are hashed in database (no plaintext)
- [ ] Signature counter increments on each passkey use
- [ ] Cloned passkey is detected (counter mismatch)
- [ ] Session tokens expire after configured time
- [ ] HTTPS enforced (no HTTP fallback)

### Usability Testing
- [ ] Passkey prompt is clear and not scary
- [ ] Vault password strength meter works correctly
- [ ] Recovery code display is readable and printable
- [ ] Error messages are helpful (not cryptic)
- [ ] First-time user can complete setup without confusion
- [ ] Returning user can log in quickly
- [ ] User can find passkey management settings
- [ ] Tooltips explain technical terms

### Performance Testing
- [ ] Argon2id derivation completes in <2 seconds on low-end devices
- [ ] Vault decryption completes in <500ms
- [ ] Passkey authentication completes in <3 seconds
- [ ] Large vault (10KB+ credentials) encrypts/decrypts without UI freeze

---

## Migration Path (Future)

When implementing this system on existing users:

1. **Existing Users**: Prompt to set up passkey + vault password on next login
2. **Credentials Migration**: Offer one-time migration of existing credentials into encrypted vault
3. **Backward Compatibility**: Allow existing Ed25519 auth to coexist during transition period
4. **Grace Period**: Give users 30 days to migrate before enforcing new auth
5. **Support**: Provide migration guide and support channel

---

## Cost Estimates

### Development Time
- Backend: 1.5 weeks (60 hours)
- Frontend: 1.5 weeks (60 hours)
- Testing/Polish: 1 week (40 hours)
- **Total**: 4 weeks (160 hours)

### Dependencies Cost
- All libraries are open-source and free
- No license fees

### Infrastructure
- Minimal impact (vault storage is small, <10KB per user)
- No external services required (self-hosted)

---

## Open Questions (To Resolve During Implementation)

1. **Session Management**: How long should session tokens be valid? (Recommendation: 7 days with refresh)
2. **Passkey Limit**: Maximum passkeys per user? (Recommendation: 10)
3. **Recovery Code Expiry**: Should recovery codes expire? (Recommendation: No expiry, but warn if unused after 1 year)
4. **Vault Size Limit**: Maximum vault storage per user? (Recommendation: 100KB)
5. **Argon2id Tuning**: Are chosen parameters suitable for low-end mobile devices? (Test on old Android)
6. **Biometric Prompt**: Customize biometric prompt text on mobile? (Yes, use friendly copy)

---

## References

- [WebAuthn Specification (W3C)](https://www.w3.org/TR/webauthn-2/)
- [FIDO2 Overview (FIDO Alliance)](https://fidoalliance.org/fido2/)
- [Argon2 RFC 9106](https://datatracker.ietf.org/doc/html/rfc9106)
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [Bitwarden Security Whitepaper](https://bitwarden.com/images/resources/security-white-paper-download.pdf)
- [1Password Secret Key Model](https://support.1password.com/secret-key-security/)

---

## Next Steps (After UX Phase)

When ready to implement:
1. Read this document thoroughly
2. Review updated dependencies in `Cargo.toml` (already added)
3. Review database schema (already created)
4. Start with Phase 1: Backend implementation
5. Create tests for each component before implementation (TDD)
6. Deploy to staging environment for testing
7. Conduct security audit before production

**Estimated Start Date**: After UX improvements complete (~2-3 weeks from 2025-11-14)
