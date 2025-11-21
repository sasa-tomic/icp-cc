# Account Profiles Design Specification

**Version:** 1.1
**Status:** Implementation In Progress - Architecture Clarification
**Created:** 2025-11-17
**Updated:** 2025-11-20

## Overview

This document specifies the design for account profiles in the backend. Each account is identified by a username and can have multiple public keys. Each public key has a corresponding IC (Internet Computer) principal derived from it.

## Architecture: Profile-Centric Model (Browser Profiles)

**IMPORTANT:** This system follows a **browser profile** mental model (Chrome profiles, Firefox profiles):

```
Profile (Local + Backend)
├── Profile Metadata (local name, settings)
├── Backend Account (@username, display name, bio, contacts)
└── Keypairs (1-10 keypairs owned by THIS profile only)
    ├── Keypair 1 (primary)
    ├── Keypair 2 (backup device)
    └── Keypair 3 (hardware wallet)
```

**Key Principles:**
1. **Tree Structure, Not Graph**: Profiles → Keypairs (each key belongs to exactly ONE profile)
2. **No Key Sharing**: A keypair CANNOT be shared across multiple profiles
3. **Backend Enforcement**: Database constraint ensures each public key is unique across ALL accounts
4. **1:1 Profile-Account Mapping**: Each profile has exactly one backend account
5. **Isolation**: Profiles are completely isolated from each other (like browser profiles)

**Example:**
```
Profile "Alice" (@alice)
  └─ Keypair 1 (laptop)
  └─ Keypair 2 (phone)

Profile "Bob" (@bob)
  └─ Keypair 1 (desktop)
```
- Alice's keypairs can ONLY access @alice's account
- Bob's keypairs can ONLY access @bob's account
- No cross-profile key usage

## Core Principles

1. **Cryptographic Authentication**: All operations must be cryptographically signed
2. **Fail Fast**: No fallbacks, immediate failure on security violations
3. **Replay Prevention**: Timestamp + nonce ensures requests cannot be replayed
4. **Audit Trail**: All operations logged for forensics and compliance
5. **Soft Deletes**: Preserve historical data, no hard deletes

## Security Model

### Authentication Flow

Every state-changing request must include:
- **Timestamp**: Client-generated Unix timestamp (seconds)
- **Nonce**: Client-generated UUID v4
- **Signature**: Ed25519 signature over canonical JSON payload
- **Public Key**: The key used to sign (must be active key for the account)

### Replay Attack Prevention

**Strategy: Timestamp + User-Generated Nonce**

1. **Timestamp Validation**:
   - Client generates timestamp locally
   - Backend validates: `|backend_time - user_timestamp| <= 5 minutes`
   - Tolerates clock drift (5 minutes is industry standard)
   - Rejects requests outside time window

2. **Nonce Validation**:
   - Client generates UUID v4 locally
   - Backend checks if nonce seen in last 10 minutes (queries `signature_audit`)
   - If found: reject (replay attack)
   - If not found: accept and insert into `signature_audit`

3. **Performance Optimization**:
   - No separate `request_nonces` table needed
   - Query `signature_audit` with time-bound index
   - Only check recent data (last 10 minutes)
   - After 10 minutes, timestamp validation rejects request

**Why both timestamp and nonce?**
- **Timestamp alone**: Attacker can replay within 5-minute window
- **Nonce alone**: Must check against ALL historical nonces (millions of rows)
- **Both together**: Check only last 10 minutes, automatic cleanup

### Signature Payload Format

**Canonical JSON**: Fields in alphabetical order, no whitespace, UTF-8 encoded

#### Registration Example
```json
{"action":"register_account","nonce":"550e8400-e29b-41d4-a716-446655440000","publicKey":"0x1234abcd...","timestamp":1700000000,"username":"alice"}
```

#### Add Key Example
```json
{"action":"add_key","newPublicKey":"0x5678efgh...","nonce":"550e8400-e29b-41d4-a716-446655440001","signingPublicKey":"0x1234abcd...","timestamp":1700000100,"username":"alice"}
```

#### Remove Key Example
```json
{"action":"remove_key","keyId":"550e8400-e29b-41d4-a716-446655440002","nonce":"550e8400-e29b-41d4-a716-446655440003","signingPublicKey":"0x1234abcd...","timestamp":1700000200,"username":"alice"}
```

**Signing Process**:
1. Construct canonical JSON (alphabetically ordered fields, no whitespace)
2. UTF-8 encode to bytes
3. Sign with private key (algorithm-specific):
   - **Ed25519**: Sign message directly (standard RFC 8032 - algorithm does SHA-512 internally)
   - **secp256k1**: Compute SHA-256 hash then sign (ECDSA requirement)
4. Encode signature as hex

**Verification Process**:
1. Receive payload + signature + public key
2. Reconstruct canonical JSON
3. UTF-8 encode to bytes
4. Verify signature using provided public key (algorithm-specific):
   - **Ed25519**: Verify against message directly
   - **secp256k1**: Compute SHA-256 hash then verify
5. Ensure public key belongs to account (for non-registration)

## Username Validation

### Rules
- **Length**: 3-32 characters
- **Characters**: `[a-z0-9_-]` (lowercase alphanumeric, underscore, hyphen)
- **Format**: Cannot start/end with hyphen or underscore
- **Normalization**: Convert to lowercase, trim whitespace
- **Regex**: `^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$`

### Reserved Usernames
```
["admin", "api", "system", "root", "support", "moderator", "icp", "administrator", "test", "null", "undefined"]
```

### Examples
- ✅ Valid: `alice`, `bob123`, `charlie-delta`, `user_99`
- ❌ Invalid: `ab` (too short), `-alice` (starts with hyphen), `alice_` (ends with underscore), `ALICE` (uppercase, but normalized to `alice`), `admin` (reserved)

## Database Schema

### Tables

```sql
-- Accounts table
CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(32) UNIQUE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT username_format CHECK (username ~ '^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$')
);

CREATE INDEX idx_accounts_username ON accounts(username);

-- Account public keys table
CREATE TABLE account_public_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    public_key TEXT UNIQUE NOT NULL,
    ic_principal TEXT UNIQUE NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    added_at TIMESTAMP NOT NULL DEFAULT NOW(),
    disabled_at TIMESTAMP,
    disabled_by_key_id UUID REFERENCES account_public_keys(id),
    CONSTRAINT one_public_key_per_account_unique UNIQUE (account_id, public_key)
);

CREATE INDEX idx_keys_account ON account_public_keys(account_id);
CREATE INDEX idx_keys_principal ON account_public_keys(ic_principal);
CREATE INDEX idx_keys_active ON account_public_keys(account_id, is_active);

-- Signature audit trail
CREATE TABLE signature_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID REFERENCES accounts(id),
    action VARCHAR(50) NOT NULL,
    payload TEXT NOT NULL,
    signature TEXT NOT NULL,
    public_key TEXT NOT NULL,
    timestamp BIGINT NOT NULL,
    nonce UUID NOT NULL,
    is_admin_action BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_nonce_time ON signature_audit(nonce, created_at);
CREATE INDEX idx_audit_account ON signature_audit(account_id);
CREATE INDEX idx_audit_created ON signature_audit(created_at);
```

### Constraints

1. **Uniqueness**:
   - Username unique across all accounts
   - Public key unique across all accounts
   - IC principal unique across all accounts

2. **Business Rules** (enforced in application layer):
   - Max 10 keys per account
   - Min 1 active key per account (cannot remove last key)

3. **Referential Integrity**:
   - Public keys cascade delete with account
   - `disabled_by_key_id` references the key that performed the disable action

## IC Principal Generation

**IC principals are deterministically derived from public keys.**

### Rules
1. Backend **MUST** compute IC principal from public key
2. **NEVER** trust user-provided IC principal
3. Use Internet Computer's standard derivation algorithm
4. Store computed principal in `account_public_keys.ic_principal`

### Implementation
```rust
// Pseudo-code
fn derive_ic_principal(public_key: &[u8]) -> String {
    // Use IC SDK to derive principal from Ed25519 public key
    // ic_agent::Principal::self_authenticating(public_key)
}
```

## Key Management

### Key Hierarchy

**All keys are equal within a profile** - no hierarchy, no "master key" concept.

**Benefits**:
- Simpler mental model
- Any active key can add/remove other keys within the SAME profile
- No single point of failure
- Prevents "lost master key = lost account" scenario

**IMPORTANT - Profile Isolation:**
- Keys belong to exactly ONE profile
- Keys from Profile A CANNOT be added to Profile B
- When adding a key, a NEW keypair is generated for the current profile
- No importing/sharing of keys across profiles

### Key Operations

#### Add Key
- Any active key within a profile can add a NEW key to that profile
- **Generates a NEW keypair** (does NOT import from another profile)
- Max 10 keys per profile/account
- New key becomes immediately active
- Signed by an existing active key from the same profile

#### Remove Key (Soft Delete)
- Any active key can remove another key within the same profile (or itself)
- Cannot remove the last active key (enforced in application)
- Sets `is_active = false`, `disabled_at = NOW()`, `disabled_by_key_id`
- Key remains in database for audit trail
- IC principal remains in database (prevents principal reuse)

#### Key Compromise
- User can remove compromised key using any non-compromised active key from the same profile
- Admin can also remove key (see Admin Operations)

## API Endpoints

### 1. Register Account

**Endpoint**: `POST /api/v1/accounts`

**Request**:
```json
{
  "username": "alice",
  "publicKey": "0x1234abcd...",
  "timestamp": 1700000000,
  "nonce": "550e8400-e29b-41d4-a716-446655440000",
  "signature": "0xabcd1234..."
}
```

**Signed Payload**:
```json
{"action":"register_account","nonce":"550e8400-e29b-41d4-a716-446655440000","publicKey":"0x1234abcd...","timestamp":1700000000,"username":"alice"}
```

**Validation**:
1. Username format validation
2. Username not reserved
3. Username not already taken
4. Public key not already registered
5. Timestamp within 5 minutes
6. Nonce not seen in last 10 minutes
7. Signature valid

**Response** (201 Created):
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "alice",
  "createdAt": "2024-11-15T10:00:00Z",
  "publicKeys": [
    {
      "id": "650e8400-e29b-41d4-a716-446655440001",
      "publicKey": "0x1234abcd...",
      "icPrincipal": "aaaaa-aa...",
      "addedAt": "2024-11-15T10:00:00Z",
      "isActive": true
    }
  ]
}
```

**Errors**:
- 400: Invalid username format, reserved username, invalid timestamp
- 409: Username already exists, public key already registered
- 401: Invalid signature, replay attack (nonce reused)

### 2. Get Account

**Endpoint**: `GET /api/v1/accounts/{username}`

**Response** (200 OK):
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "alice",
  "createdAt": "2024-11-15T10:00:00Z",
  "updatedAt": "2024-11-15T10:05:00Z",
  "publicKeys": [
    {
      "id": "650e8400-e29b-41d4-a716-446655440001",
      "publicKey": "0x1234abcd...",
      "icPrincipal": "aaaaa-aa...",
      "addedAt": "2024-11-15T10:00:00Z",
      "isActive": true
    },
    {
      "id": "750e8400-e29b-41d4-a716-446655440002",
      "publicKey": "0x5678efgh...",
      "icPrincipal": "bbbbb-bb...",
      "addedAt": "2024-11-15T10:05:00Z",
      "isActive": true
    }
  ]
}
```

**Errors**:
- 404: Account not found

### 3. Add Public Key

**Endpoint**: `POST /api/v1/accounts/{username}/keys`

**Request**:
```json
{
  "newPublicKey": "0x5678efgh...",
  "signingPublicKey": "0x1234abcd...",
  "timestamp": 1700000100,
  "nonce": "550e8400-e29b-41d4-a716-446655440001",
  "signature": "0xefgh5678..."
}
```

**Signed Payload**:
```json
{"action":"add_key","newPublicKey":"0x5678efgh...","nonce":"550e8400-e29b-41d4-a716-446655440001","signingPublicKey":"0x1234abcd...","timestamp":1700000100,"username":"alice"}
```

**Validation**:
1. Account exists
2. Signing public key belongs to account and is active
3. New public key not already registered (anywhere)
4. Account has < 10 keys
5. Timestamp within 5 minutes
6. Nonce not seen in last 10 minutes
7. Signature valid

**Response** (201 Created):
```json
{
  "id": "750e8400-e29b-41d4-a716-446655440002",
  "publicKey": "0x5678efgh...",
  "icPrincipal": "bbbbb-bb...",
  "addedAt": "2024-11-15T10:05:00Z",
  "isActive": true
}
```

**Errors**:
- 400: Invalid timestamp, max keys exceeded
- 404: Account not found
- 401: Invalid signature, signing key not active, replay attack
- 409: Public key already registered

### 4. Remove Public Key

**Endpoint**: `DELETE /api/v1/accounts/{username}/keys/{keyId}`

**Request**:
```json
{
  "signingPublicKey": "0x1234abcd...",
  "timestamp": 1700000200,
  "nonce": "550e8400-e29b-41d4-a716-446655440003",
  "signature": "0x9012ijkl..."
}
```

**Signed Payload**:
```json
{"action":"remove_key","keyId":"750e8400-e29b-41d4-a716-446655440002","nonce":"550e8400-e29b-41d4-a716-446655440003","signingPublicKey":"0x1234abcd...","timestamp":1700000200,"username":"alice"}
```

**Validation**:
1. Account exists
2. Key exists and belongs to account
3. Signing public key belongs to account and is active
4. Key to remove is not the last active key
5. Timestamp within 5 minutes
6. Nonce not seen in last 10 minutes
7. Signature valid

**Action**: Soft delete (set `is_active = false`, `disabled_at = NOW()`, `disabled_by_key_id`)

**Response** (200 OK):
```json
{
  "id": "750e8400-e29b-41d4-a716-446655440002",
  "publicKey": "0x5678efgh...",
  "icPrincipal": "bbbbb-bb...",
  "addedAt": "2024-11-15T10:05:00Z",
  "isActive": false,
  "disabledAt": "2024-11-15T10:10:00Z",
  "disabledByKeyId": "650e8400-e29b-41d4-a716-446655440001"
}
```

**Errors**:
- 400: Cannot remove last active key, invalid timestamp
- 404: Account or key not found
- 401: Invalid signature, signing key not active, replay attack

### 5. Admin: Disable Key

**Endpoint**: `POST /api/v1/admin/accounts/{username}/keys/{keyId}/disable`

**Authentication**: Requires admin credentials (separate from user key-based auth)

**Request**:
```json
{
  "reason": "Compromised key reported by user"
}
```

**Action**:
- Soft delete key (same as user removal)
- Set `is_admin_action = true` in `signature_audit`
- Log admin action with reason

**Response** (200 OK):
```json
{
  "id": "750e8400-e29b-41d4-a716-446655440002",
  "publicKey": "0x5678efgh...",
  "isActive": false,
  "disabledAt": "2024-11-15T10:15:00Z",
  "disabledByAdmin": true
}
```

**Use Cases**:
- User reports key compromise but has no other active keys
- User loses all keys and needs account recovery
- Security incident response

### 6. Admin: Add Recovery Key

**Endpoint**: `POST /api/v1/admin/accounts/{username}/recovery-key`

**Authentication**: Requires admin credentials

**Request**:
```json
{
  "publicKey": "0x9012mnop...",
  "reason": "User lost all keys, verified via support ticket #12345"
}
```

**Action**:
- Add new public key to account
- Set `is_admin_action = true` in `signature_audit`
- Log admin action with reason

**Response** (201 Created):
```json
{
  "id": "850e8400-e29b-41d4-a716-446655440003",
  "publicKey": "0x9012mnop...",
  "icPrincipal": "ccccc-cc...",
  "addedAt": "2024-11-15T10:20:00Z",
  "isActive": true,
  "addedByAdmin": true
}
```

## Account Recovery

### Scenario: User Loses All Keys

**Process**:
1. User contacts support (out-of-band verification required)
2. Support verifies keypair (email, phone, KYC, etc.)
3. Admin uses `POST /api/v1/admin/accounts/{username}/recovery-key`
4. Admin provides new public key (user generates new key pair)
5. User can now use new key to manage account
6. Admin action logged in `signature_audit` with `is_admin_action = true`

**Security Considerations**:
- Admin actions require strong authentication
- All admin actions logged with reason
- Consider multi-signature requirement for admin actions
- Rate limit admin recovery operations

## Validation Logic

### Every Signed Request

```rust
// Pseudo-code validation flow
fn validate_signed_request(request: SignedRequest) -> Result<()> {
    // 1. Validate timestamp
    let now = current_timestamp();
    if (now - request.timestamp).abs() > 300 { // 5 minutes
        return Err("Timestamp out of range");
    }

    // 2. Check nonce (replay prevention)
    let nonce_exists = db.query(
        "SELECT 1 FROM signature_audit
         WHERE nonce = $1
         AND created_at > NOW() - INTERVAL '10 minutes'"
    )?;
    if nonce_exists {
        return Err("Nonce already used (replay attack)");
    }

    // 3. Reconstruct canonical JSON payload
    let canonical_payload = create_canonical_json(request);

    // 4. Verify signature
    if !verify_signature(
        canonical_payload,
        request.signature,
        request.public_key
    ) {
        return Err("Invalid signature");
    }

    // 5. For non-registration: verify key belongs to account and is active
    if request.action != "register_account" {
        let key = db.get_public_key(request.public_key)?;
        if !key.is_active {
            return Err("Public key is not active");
        }
        if key.account.username != request.username {
            return Err("Public key does not belong to this account");
        }
    }

    // 6. Perform action-specific validation
    validate_action_specific(request)?;

    // 7. Insert into signature_audit (nonce is now "used")
    db.insert_signature_audit(request)?;

    Ok(())
}
```

## Background Jobs

### Nonce Cleanup (Optional)

Since we use time-bound queries on `signature_audit`, old nonces don't impact performance. However, for data hygiene:

```sql
-- Run daily
DELETE FROM signature_audit
WHERE created_at < NOW() - INTERVAL '90 days';
```

**Retention Policy**:
- Keep signature audit for 90 days for compliance/forensics
- Archive older data if needed for long-term auditing

## Testing Requirements

### Unit Tests (Following AGENTS.md)

**CRITICAL**: All tests involving cryptography must use real cryptographic operations.

#### Test Helpers Required

1. **TestKeypairFactory**:
   ```dart
   final keypair = await TestKeypairFactory.getEd25519Keypair();
   final principal = PrincipalUtils.textFromRecord(keypair);
   ```

2. **TestSignatureUtils**:
   ```dart
   final signature = TestSignatureUtils.generateTestSignatureSync(payload);
   final request = TestSignatureUtils.createTestScriptRequest();
   ```

3. **FakeSecureKeypairRepository**:
   ```dart
   final repository = FakeSecureKeypairRepository([keypair]);
   ```

**NO hardcoded test principals, NO fake signatures, NO mock cryptography.**

### Test Coverage

Every endpoint and validation rule must be tested:

#### Registration Tests
- ✅ Valid registration with correct signature
- ✅ Duplicate username rejection
- ✅ Duplicate public key rejection
- ✅ Reserved username rejection
- ✅ Invalid username format rejection
- ✅ Invalid signature rejection
- ✅ Expired timestamp rejection
- ✅ Replay attack (nonce reuse) rejection

#### Add Key Tests
- ✅ Valid key addition with active signing key
- ✅ Max keys (10) enforcement
- ✅ Duplicate public key rejection
- ✅ Inactive signing key rejection
- ✅ Wrong account signing key rejection
- ✅ Invalid signature rejection

#### Remove Key Tests
- ✅ Valid key removal
- ✅ Last active key protection
- ✅ Soft delete verification (is_active = false)
- ✅ Disabled timestamp and disabled_by_key_id set correctly

#### Admin Tests
- ✅ Admin can disable key
- ✅ Admin can add recovery key
- ✅ Admin actions logged with is_admin_action = true

## Implementation Order

### Phase 1: Database & Core Utils
1. Database migrations (schema creation)
2. IC principal derivation utility
3. Canonical JSON serialization utility
4. Signature validation middleware

### Phase 2: Registration
5. POST /api/v1/accounts (register)
6. Tests for registration

### Phase 3: Read Operations
7. GET /api/v1/accounts/{username}
8. Tests for get account

### Phase 4: Key Management
9. POST /api/v1/accounts/{username}/keys (add key)
10. DELETE /api/v1/accounts/{username}/keys/{keyId} (remove key)
11. Tests for key operations

### Phase 5: Admin Operations
12. POST /api/v1/admin/accounts/{username}/keys/{keyId}/disable
13. POST /api/v1/admin/accounts/{username}/recovery-key
14. Tests for admin operations

### Phase 6: Production Readiness
15. Background cleanup jobs
16. Performance testing
17. Security audit
18. Documentation

## Security Considerations

### Attack Vectors & Mitigations

1. **Replay Attacks**: ✅ Timestamp + nonce prevention
2. **Signature Forgery**: ✅ Ed25519 cryptographic signatures
3. **Principal Spoofing**: ✅ Backend computes principals, never trusts user input
4. **Key Reuse**: ✅ Public keys unique across all accounts
5. **Username Squatting**: ✅ Reserved list, can add rate limiting later
6. **Timing Attacks**: ✅ Constant-time signature verification
7. **Account Takeover**: ✅ All operations require signature from existing active key

### Audit Trail

Every operation logged in `signature_audit`:
- Who (public_key, account_id)
- What (action, payload)
- When (timestamp, created_at)
- How (signature for verification)
- Why (is_admin_action for admin ops)

## Performance Considerations

### Database Indexes

Critical indexes for performance:
- `idx_accounts_username`: Fast username lookups
- `idx_keys_principal`: Fast principal lookups
- `idx_audit_nonce_time`: Fast replay detection (time-bound nonce check)
- `idx_keys_account`: Fast key listing per account

### Query Optimization

Replay detection query is bounded by time:
```sql
SELECT 1 FROM signature_audit
WHERE nonce = ?
  AND created_at > NOW() - INTERVAL '10 minutes'
LIMIT 1;
```
Only scans last 10 minutes of data, not entire table.

### Expected Load

Assumptions for capacity planning:
- 10,000 users
- Average 3 keys per user
- 100 requests/minute
- 90-day audit retention

Storage estimates:
- `accounts`: ~1 MB
- `account_public_keys`: ~3 MB
- `signature_audit` (90 days): ~500 MB

## Open Questions / Future Enhancements

1. **Rate Limiting**: Not implemented in v1, can add later
2. **Multi-signature Admin Actions**: Consider for high-security environments
3. **Key Rotation Reminders**: Notify users to rotate keys periodically
4. **Account Deletion**: Currently not supported, intentional for audit trail
5. **Key Metadata**: Could add labels/descriptions to keys for user organization
6. **WebAuthn Integration**: Future enhancement for hardware key support

## References

- [Ed25519 Signature Scheme](https://ed25519.cr.yp.to/)
- [Internet Computer Principal Derivation](https://internetcomputer.org/docs/current/references/ic-interface-spec#principals)
- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)

---

**Document Status**: Ready for implementation
**Next Steps**: Begin Phase 1 (Database & Core Utils)
