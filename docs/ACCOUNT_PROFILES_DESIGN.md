# Account Profiles Design Specification

**Version:** 1.3
**Status:** Production Ready
**Updated:** 2025-11-21

## Overview

Account profiles system provides secure, cryptographically-authenticated user accounts. Each account has:
- A unique username (e.g., `@alice`)
- Profile information (display name, bio, contact details)
- 1-10 cryptographic keypairs for authentication
- IC (Internet Computer) principals derived from public keys

## Architecture: Profile-Centric Model

Follows a **browser profile** mental model (like Chrome/Firefox profiles):

```
Profile (Local + Backend)
├── Profile Metadata (local name, settings)
├── Backend Account (@username, display name, bio, contacts)
└── Keypairs (1-10 keypairs owned by THIS profile only)
    ├── Keypair 1 (laptop)
    ├── Keypair 2 (phone)
    └── Keypair 3 (hardware wallet)
```

**Key Principles:**
1. **Tree Structure**: Profiles → Keypairs (each key belongs to exactly ONE profile)
2. **No Key Sharing**: A keypair cannot be shared across profiles
3. **Backend Enforcement**: Each public key is unique across ALL accounts
4. **1:1 Mapping**: Each profile has exactly one backend account
5. **Isolation**: Profiles are completely isolated from each other

## Core Design Principles

1. **Cryptographic Authentication**: All state-changing operations must be cryptographically signed
2. **Fail Fast**: No fallbacks, immediate failure on security violations
3. **Replay Prevention**: Timestamp + nonce ensures requests cannot be replayed
4. **Audit Trail**: All operations logged for forensics
5. **Soft Deletes**: Keys are disabled, never hard deleted

## Security Model

### Authentication
Every state-changing request includes:
- **Timestamp**: Unix timestamp (must be within 5 minutes of server time)
- **Nonce**: UUID v4 (prevents replay attacks within 10-minute window)
- **Signature**: Ed25519 or secp256k1 signature over canonical JSON
- **Public Key**: Must be an active key for the account

### Signature Process
1. Construct canonical JSON (alphabetically ordered fields, no whitespace)
2. UTF-8 encode to bytes
3. Sign with algorithm:
   - **Ed25519**: Sign message directly (RFC 8032)
   - **secp256k1**: SHA-256 hash then sign (ECDSA)
4. Base64 encode the signature

### IC Principal Generation
- Principals are **deterministically derived** from public keys
- Backend computes principals using IC SDK
- User-provided principals are **never trusted**

## Username Rules

- **Length**: 3-32 characters
- **Characters**: `[a-z0-9_-]` (lowercase alphanumeric, underscore, hyphen)
- **Format**: Cannot start/end with hyphen or underscore
- **Regex**: `^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$`
- **Reserved**: `admin`, `api`, `system`, `root`, `support`, `moderator`, `icp`, `administrator`, `test`, `null`, `undefined`

**Examples:**
- ✅ Valid: `alice`, `bob123`, `charlie-delta`, `user_99`
- ❌ Invalid: `ab` (too short), `-alice` (starts with hyphen), `ALICE` (uppercase)

## API Endpoints

### 1. Register Account
```
POST /api/v1/accounts
```
**Request:**
```json
{
  "username": "alice",
  "displayName": "Alice Smith",
  "contactEmail": "alice@example.com",
  "publicKey": "0x1234abcd...",
  "timestamp": 1700000000,
  "nonce": "550e8400-e29b-41d4-a716-446655440000",
  "signature": "abc..."
}
```

**Response (201):**
```json
{
  "id": "550e8400-...",
  "username": "alice",
  "publicKeys": [
    {
      "id": "650e8400-...",
      "publicKey": "0x1234abcd...",
      "icPrincipal": "aaaaa-aa...",
      "isActive": true
    }
  ]
}
```

### 2. Get Account
```
GET /api/v1/accounts/{username}
```
Returns account details including all public keys.

### 3. Add Public Key
```
POST /api/v1/accounts/{username}/keys
```
**Request:**
```json
{
  "newPublicKey": "0x5678efgh...",
  "signingPublicKey": "0x1234abcd...",
  "timestamp": 1700000100,
  "nonce": "550e8400-...",
  "signature": "abc..."
}
```
Must be signed by an existing active key. Max 10 keys per account.

### 4. Remove Public Key
```
DELETE /api/v1/accounts/{username}/keys/{keyId}
```
Soft delete (sets `is_active = false`). Cannot remove last active key.

### 5. Update Profile
```
PATCH /api/v1/accounts/{username}
```
Update display name, bio, contact information.

### 6. Admin Operations
```
POST /api/v1/admin/accounts/{username}/keys/{keyId}/disable
POST /api/v1/admin/accounts/{username}/recovery-key
```
Admin-only endpoints for account recovery. Requires admin bearer token.

## Key Management

### Key Operations
- **Add Key**: Any active key can add a new key (generates new keypair)
- **Remove Key**: Any active key can remove another key (soft delete)
- **Max Keys**: 10 keys per account
- **Min Keys**: 1 active key (cannot remove last key)

### Key Hierarchy
All keys are equal - no "master key" concept. Any active key can add/remove other keys within the same profile.

## Account Recovery

If user loses all keys:
1. Contact support with identity verification
2. Admin adds recovery key via API
3. User can now manage account with new key
4. Admin action logged with reason in audit trail

## Error Codes

- **400**: Invalid format, constraints violated
- **401**: Invalid signature, replay attack, inactive key
- **404**: Account or key not found
- **409**: Username taken, public key already registered

## Usage Example

### Client-Side Flow
```dart
// 1. Generate keypair
final keypair = await ProfileKeypair.generate(KeyAlgorithm.ed25519);

// 2. Create canonical payload
final payload = {
  "action": "register_account",
  "nonce": Uuid().v4(),
  "publicKey": publicKeyB64,
  "timestamp": DateTime.now().millisecondsSinceEpoch ~/ 1000,
  "username": "alice"
};

// 3. Sign with keypair
final signature = await signPayload(keypair, payload);

// 4. Send to backend
final response = await apiClient.registerAccount({
  ...payload,
  "signature": signature
});
```

## Security Considerations

**Attack Vectors Mitigated:**
1. ✅ Replay Attacks: Timestamp + nonce prevention
2. ✅ Signature Forgery: Ed25519/secp256k1 cryptographic signatures
3. ✅ Principal Spoofing: Backend computes principals
4. ✅ Key Reuse: Public keys unique across all accounts
5. ✅ Account Takeover: All operations require valid signature

**Audit Trail:**
Every operation logged with:
- Who (public_key, account_id)
- What (action, payload)
- When (timestamp, created_at)
- How (signature for verification)

## References

- [Ed25519 Signature Scheme](https://ed25519.cr.yp.to/)
- [Internet Computer Principal Derivation](https://internetcomputer.org/docs/current/references/ic-interface-spec#principals)
- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
