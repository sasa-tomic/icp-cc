# Admin Operations Guide

**Version:** 1.0
**Last Updated:** 2025-11-17

## Overview

This guide covers administrative operations for the Account Profiles system, including account recovery, key management, and security incident response.

## Table of Contents

- [Authentication](#authentication)
- [API Endpoints](#api-endpoints)
- [Common Scenarios](#common-scenarios)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)
- [Audit Trail](#audit-trail)

---

## Authentication

### Setup Admin Token

Admin operations require a bearer token configured via environment variable.

#### Development
```bash
# In .env file
ADMIN_TOKEN=change-me-in-production
```

#### Production
```bash
# Generate secure random token (32 bytes = 64 hex characters)
export ADMIN_TOKEN="$(openssl rand -hex 32)"

# Or use uuidgen
export ADMIN_TOKEN="$(uuidgen)-$(uuidgen)"
```

### Using Admin Token

All admin endpoints require the `Authorization` header:

```bash
Authorization: Bearer <ADMIN_TOKEN>
```

**Example**:
```bash
curl -X POST http://localhost:8080/api/v1/admin/accounts/alice/keys/key-123/disable \
  -H "Authorization: Bearer your-admin-token-here" \
  -H "Content-Type: application/json" \
  -d '{"reason": "User reported compromise"}'
```

### Security Considerations

- **Never commit** the admin token to version control
- **Rotate regularly** (recommended: every 90 days)
- **Use secrets management** in production (e.g., AWS Secrets Manager, HashiCorp Vault)
- **Restrict access** to admin token (only authorized personnel)
- **Monitor usage** via audit logs

---

## API Endpoints

### 1. Disable Key (Admin Override)

**Endpoint**: `POST /api/v1/admin/accounts/:username/keys/:key_id/disable`

**Purpose**: Disable a public key on any account, bypassing normal restrictions.

**Use Cases**:
- User reports key compromise
- Security incident response
- Suspicious activity detected
- Account lockout for investigation

**Request**:
```bash
curl -X POST http://localhost:8080/api/v1/admin/accounts/alice/keys/550e8400-e29b-41d4-a716-446655440001/disable \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reason": "User reported key compromise via support ticket #5678"
  }'
```

**Request Body**:
```json
{
  "reason": "Detailed explanation for audit trail"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "publicKey": "base64-encoded-public-key",
    "icPrincipal": "aaaaa-aa-principal-text",
    "isActive": false,
    "disabledAt": "2025-11-17T10:30:00Z",
    "disabledByAdmin": true
  }
}
```

**Error Responses**:
- **401 Unauthorized**: Missing or invalid admin token
- **404 Not Found**: Account or key doesn't exist
- **400 Bad Request**: Invalid username format

**Important Notes**:
- ⚠️ Admin can disable the **last active key** (normal users cannot)
- ✅ Action is logged in `signature_audit` with `is_admin_action = true`
- ✅ Reason is recorded in audit trail for compliance

---

### 2. Add Recovery Key (Admin Override)

**Endpoint**: `POST /api/v1/admin/accounts/:username/recovery-key`

**Purpose**: Add a new public key to an account without user signature (account recovery).

**Use Cases**:
- User lost all keys
- Account recovery after verification
- Emergency access restoration
- Migration from compromised keys

**Request**:
```bash
curl -X POST http://localhost:8080/api/v1/admin/accounts/alice/recovery-key \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "publicKey": "base64-encoded-new-public-key",
    "reason": "User verified via email+phone. Lost all keys. Support ticket #9012"
  }'
```

**Request Body**:
```json
{
  "publicKey": "base64-encoded-public-key",
  "reason": "Detailed explanation including verification method"
}
```

**Response (201 Created)**:
```json
{
  "success": true,
  "data": {
    "id": "650e8400-e29b-41d4-a716-446655440002",
    "publicKey": "base64-encoded-new-public-key",
    "icPrincipal": "bbbbb-bb-principal-text",
    "isActive": true,
    "addedByAdmin": true,
    "addedAt": "2025-11-17T10:35:00Z"
  }
}
```

**Error Responses**:
- **401 Unauthorized**: Missing or invalid admin token
- **404 Not Found**: Account doesn't exist
- **400 Bad Request**:
  - Invalid username format
  - Public key already registered
  - Maximum keys (10) reached
  - Invalid public key format

**Important Notes**:
- ✅ Bypasses signature verification (no user signature required)
- ✅ Still enforces max 10 keys limit
- ✅ Still validates public key uniqueness
- ✅ Action logged in `signature_audit` with `is_admin_action = true`

---

## Common Scenarios

### Scenario 1: User Reports Compromised Key

**Situation**: User contacts support reporting their key was potentially compromised.

**Steps**:

1. **Verify User Identity** (out-of-band):
   - Email verification
   - Phone call
   - Security questions
   - Previous transaction history

2. **Disable Compromised Key**:
```bash
curl -X POST http://localhost:8080/api/v1/admin/accounts/bob/keys/compromised-key-id/disable \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reason": "User reported compromise via phone 2025-11-17. Verified identity via email+2FA. Ticket #5678"
  }'
```

3. **Verify Other Keys**:
```bash
# Get account to see remaining active keys
curl http://localhost:8080/api/v1/accounts/bob
```

4. **Advise User**:
   - If user has other active keys: Use those to manage account
   - If no other keys: Proceed to Scenario 2 (Account Recovery)

---

### Scenario 2: Account Recovery (User Lost All Keys)

**Situation**: User lost access to all their keys and cannot authenticate.

**Steps**:

1. **Verify User Identity** (strict verification required):
   - Email verification (send code to registered email)
   - Phone verification (SMS or call to registered number)
   - KYC documents if available
   - Previous transaction patterns
   - Security questions
   - **Document everything** in support ticket

2. **Review Account**:
```bash
curl http://localhost:8080/api/v1/accounts/charlie
```

3. **User Generates New Key Pair**:
   - User generates new Ed25519 key pair on their device
   - User provides public key to support (via secure channel)

4. **Admin Adds Recovery Key**:
```bash
curl -X POST http://localhost:8080/api/v1/admin/accounts/charlie/recovery-key \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "publicKey": "user-new-public-key-base64",
    "reason": "Account recovery: User verified via email (code sent to charlie@example.com) and phone (+1-555-0123) on 2025-11-17. User lost device with all keys. Ticket #9012. Verified by: Admin John Doe"
  }'
```

5. **User Confirms Access**:
   - User tests new key by making authenticated request
   - User should add additional keys for backup
   - User should disable old keys if desired

6. **Follow-up**:
   - Recommend user enable 2FA/backup methods
   - Document recovery in user's account notes

---

### Scenario 3: Security Incident Response

**Situation**: Security team detects suspicious activity on an account.

**Steps**:

1. **Assess Threat**:
   - Review audit logs
   - Identify compromised keys
   - Determine scope of breach

2. **Immediate Lockdown** (if needed):
```bash
# Disable all suspicious keys
curl -X POST http://localhost:8080/api/v1/admin/accounts/dave/keys/suspicious-key-1/disable \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reason": "Security incident SI-2025-1117: Suspicious transactions detected. Key disabled pending investigation. Incident response: security@example.com"
  }'
```

3. **Contact User**:
   - Email user about security incident
   - Request user verify recent activity
   - Guide user through key rotation if needed

4. **Restore Access** (if user verified):
```bash
# Add new recovery key after user verification
curl -X POST http://localhost:8080/api/v1/admin/accounts/dave/recovery-key \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "publicKey": "user-verified-new-key-base64",
    "reason": "Security incident SI-2025-1117 resolved: User verified via video call on 2025-11-17. No unauthorized access confirmed. New key provided. Incident closed by: SecOps Team"
  }'
```

5. **Post-Incident**:
   - Document incident in security logs
   - Review and improve security policies
   - Update user on resolution

---

### Scenario 4: Bulk Key Rotation (Security Policy)

**Situation**: Organization requires periodic key rotation for compliance.

**Steps**:

1. **Notify Users** (30 days in advance):
   - Email all users about upcoming rotation
   - Provide instructions for generating new keys
   - Set deadline

2. **Generate Report of Non-Compliant Users**:
```bash
# Query accounts with old keys (requires custom SQL or API endpoint)
# This is a manual process - query signature_audit for key ages
```

3. **Coordinate with Users**:
   - Users add new keys themselves (preferred)
   - Users authorize admin to add recovery key (if needed)

4. **For Users Unable to Rotate**:
```bash
# Admin adds recovery key after user provides new public key
curl -X POST http://localhost:8080/api/v1/admin/accounts/eve/recovery-key \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "publicKey": "user-new-key-base64",
    "reason": "Annual key rotation policy 2025: User authorized admin to add new key via email 2025-11-15. Old key to be disabled on 2025-12-01. Policy: POL-2025-KR"
  }'
```

5. **Disable Old Keys** (after grace period):
```bash
curl -X POST http://localhost:8080/api/v1/admin/accounts/eve/keys/old-key-id/disable \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reason": "Annual key rotation policy 2025: Grace period expired. Old key disabled per POL-2025-KR"
  }'
```

---

## Security Best Practices

### 1. Verification Requirements

**Before Admin Recovery Key Addition**:
- ✅ **Email verification**: Send code to registered email
- ✅ **Phone verification**: SMS or voice call to registered phone
- ✅ **KYC documents**: Government-issued ID if available
- ✅ **Transaction history**: Verify user knows recent transactions
- ✅ **Security questions**: If configured
- ✅ **Time delay**: Consider 24-48 hour waiting period for high-value accounts

**Document Everything**:
- Who verified the user (admin name)
- How verification was performed (methods used)
- When verification occurred (timestamp)
- Why action was needed (user's situation)
- Support ticket reference number

### 2. Admin Token Management

**Storage**:
```bash
# ✅ Good: Environment variable from secrets manager
export ADMIN_TOKEN=$(aws secretsmanager get-secret-value --secret-id admin-token --query SecretString --output text)

# ✅ Good: Docker secrets
docker secret create admin_token /run/secrets/admin_token

# ❌ Bad: Hardcoded in config file
ADMIN_TOKEN=abc123  # Never do this!
```

**Rotation Schedule**:
```bash
# Rotate every 90 days
# 1. Generate new token
NEW_TOKEN=$(openssl rand -hex 32)

# 2. Update environment variable
export ADMIN_TOKEN=$NEW_TOKEN

# 3. Restart application
systemctl restart icp-marketplace-api

# 4. Revoke old token (update secrets manager)
```

### 3. Audit Trail Review

**Regular Monitoring**:
```sql
-- Review admin actions in last 7 days
SELECT
    created_at,
    action,
    account_id,
    payload,
    public_key
FROM signature_audit
WHERE is_admin_action = 1
    AND datetime(created_at) > datetime('now', '-7 days')
ORDER BY created_at DESC;
```

**Alerts**:
- Set up alerts for admin actions
- Review all admin operations weekly
- Flag unusual patterns (e.g., many recoveries in short time)

### 4. Rate Limiting

**Recommended Limits**:
- Max 10 admin operations per account per day
- Max 100 admin operations total per day
- Alert if limits exceeded (potential abuse)

**Implementation** (future enhancement):
- Add rate limiting middleware for admin endpoints
- Track operations per account and globally
- Return 429 Too Many Requests if exceeded

---

## Troubleshooting

### Issue 1: "Invalid admin credentials" (401)

**Cause**: Admin token is missing or incorrect.

**Solutions**:
```bash
# Check token is set
echo $ADMIN_TOKEN

# Verify token in request
curl -v http://localhost:8080/api/v1/admin/accounts/alice/recovery-key \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  # Check the Authorization header in verbose output

# Test with known token
curl -X POST http://localhost:8080/api/v1/admin/accounts/alice/recovery-key \
  -H "Authorization: Bearer change-me-in-production" \
  -H "Content-Type: application/json" \
  -d '{"publicKey":"test","reason":"test"}'
```

### Issue 2: "Account not found" (404)

**Cause**: Username doesn't exist or is misspelled.

**Solutions**:
```bash
# Verify username exists
curl http://localhost:8080/api/v1/accounts/alice

# Check for typos (usernames are case-sensitive after normalization)
# Username "Alice" is normalized to "alice"
```

### Issue 3: "Public key already registered" (400)

**Cause**: The public key is already associated with another account.

**Solutions**:
```bash
# User must generate a NEW key pair
# Cannot reuse keys across accounts (security policy)

# Verify key is unique (requires direct DB query or search endpoint)
```

### Issue 4: "Maximum number of keys (10) reached" (400)

**Cause**: Account already has 10 keys (active + disabled).

**Solutions**:
```bash
# 1. Get account to see all keys
curl http://localhost:8080/api/v1/accounts/alice

# 2. Admin cannot add more keys
# 3. Policy decision needed:
#    - User must remove old disabled keys (requires DB operation)
#    - Or increase max limit (code change)
```

### Issue 5: Invalid public key format

**Cause**: Public key is not valid base64 or not 32 bytes.

**Solutions**:
```bash
# Ed25519 public keys must be:
# - 32 bytes long
# - Base64 encoded
# - Valid Ed25519 format

# Example valid key (base64 of 32 random bytes):
python3 -c "import base64, os; print(base64.b64encode(os.urandom(32)).decode())"
```

---

## Audit Trail

### Viewing Admin Actions

All admin operations are recorded in the `signature_audit` table with `is_admin_action = true`.

**Query Recent Admin Actions**:
```sql
SELECT
    created_at AS timestamp,
    action,
    account_id,
    json_extract(payload, '$.username') AS username,
    json_extract(payload, '$.reason') AS reason,
    json_extract(payload, '$.keyId') AS key_id,
    json_extract(payload, '$.newPublicKey') AS new_public_key
FROM signature_audit
WHERE is_admin_action = 1
ORDER BY created_at DESC
LIMIT 50;
```

**Admin Action Types**:
- `admin_disable_key`: Admin disabled a public key
- `admin_add_recovery_key`: Admin added a recovery key

**Audit Fields**:
```json
{
  "id": "audit-record-uuid",
  "account_id": "account-uuid",
  "action": "admin_disable_key",
  "payload": "{\"action\":\"admin_disable_key\",\"keyId\":\"...\",\"reason\":\"...\",\"username\":\"alice\"}",
  "signature": "admin-action",
  "public_key": "admin",
  "timestamp": 1700000000,
  "nonce": "unique-uuid",
  "is_admin_action": true,
  "created_at": "2025-11-17T10:30:00Z"
}
```

### Compliance Reports

**Monthly Admin Activity Report**:
```sql
SELECT
    DATE(created_at) AS date,
    action,
    COUNT(*) AS count
FROM signature_audit
WHERE is_admin_action = 1
    AND datetime(created_at) >= datetime('now', 'start of month')
GROUP BY DATE(created_at), action
ORDER BY date DESC, action;
```

**Admin Actions by Account**:
```sql
SELECT
    a.username,
    COUNT(*) AS admin_action_count,
    MAX(sa.created_at) AS last_admin_action
FROM signature_audit sa
JOIN accounts a ON sa.account_id = a.id
WHERE sa.is_admin_action = 1
    AND datetime(sa.created_at) >= datetime('now', '-30 days')
GROUP BY a.username
ORDER BY admin_action_count DESC;
```

---

## Background Cleanup Job

The signature audit cleanup job runs automatically every 24 hours to remove records older than 90 days.

### Monitoring

**Check Cleanup Logs**:
```bash
# View cleanup activity
grep "signature audit cleanup" /var/log/app.log

# Expected output:
# 2025-11-17T00:00:00Z Starting signature audit cleanup background job
# 2025-11-17T00:00:01Z Running signature audit cleanup...
# 2025-11-17T00:00:02Z Signature audit cleanup completed: 150 records deleted
```

### Manual Cleanup (if needed)

```sql
-- Delete records older than 90 days
DELETE FROM signature_audit
WHERE datetime(created_at) < datetime('now', '-90 days');
```

### Retention Policy Adjustment

To change the 90-day retention period, modify `backend/src/cleanup.rs:31`:

```rust
// Change from 90 days to 180 days
DELETE FROM signature_audit
WHERE datetime(created_at) < datetime('now', '-180 days')
```

Then rebuild and restart the application.

---

## API Testing Examples

### Test Admin Authentication

```bash
# Should succeed with valid token
curl -X POST http://localhost:8080/api/v1/admin/accounts/testuser/recovery-key \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"publicKey":"dGVzdC1rZXk=","reason":"test"}'

# Should fail with invalid token
curl -X POST http://localhost:8080/api/v1/admin/accounts/testuser/recovery-key \
  -H "Authorization: Bearer invalid-token" \
  -H "Content-Type: application/json" \
  -d '{"publicKey":"dGVzdC1rZXk=","reason":"test"}'

# Should fail without token
curl -X POST http://localhost:8080/api/v1/admin/accounts/testuser/recovery-key \
  -H "Content-Type: application/json" \
  -d '{"publicKey":"dGVzdC1rZXk=","reason":"test"}'
```

### Test Admin Operations

```bash
# 1. Register test account (normal user operation)
curl -X POST http://localhost:8080/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testadmin",
    "publicKey": "base64-encoded-key",
    "timestamp": 1700000000,
    "nonce": "550e8400-e29b-41d4-a716-446655440000",
    "signature": "valid-signature"
  }'

# 2. Get account to find key ID
curl http://localhost:8080/api/v1/accounts/testadmin

# 3. Admin disable key
curl -X POST http://localhost:8080/api/v1/admin/accounts/testadmin/keys/KEY_ID_HERE/disable \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reason":"Testing admin disable functionality"}'

# 4. Admin add recovery key
curl -X POST http://localhost:8080/api/v1/admin/accounts/testadmin/recovery-key \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "publicKey": "new-base64-encoded-key",
    "reason": "Testing admin recovery key functionality"
  }'

# 5. Verify account now has new key
curl http://localhost:8080/api/v1/accounts/testadmin
```

---

## Support Workflow Template

### Account Recovery Request Template

```
Support Ticket: #[TICKET_NUMBER]
Date: [DATE]
User: [USERNAME]
Requester Email: [EMAIL]
Requester Phone: [PHONE]

Issue: User has lost access to all keys and requests account recovery

Verification Completed:
[ ] Email verification (code sent to [EMAIL])
[ ] Phone verification (code sent to [PHONE])
[ ] KYC documents reviewed (if applicable)
[ ] Transaction history verified
[ ] Security questions answered (if configured)
[ ] Waiting period: [24/48] hours completed

New Public Key Provided by User:
[BASE64_ENCODED_PUBLIC_KEY]

Admin Action Required:
Add recovery key to account: [USERNAME]

Reason for Audit Trail:
"Account recovery for [USERNAME]: User verified via email ([EMAIL]) and phone ([PHONE]) on [DATE]. User lost device with all keys. Support ticket #[TICKET_NUMBER]. Verified by: [ADMIN_NAME]"

Admin Command:
curl -X POST http://localhost:8080/api/v1/admin/accounts/[USERNAME]/recovery-key \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "publicKey": "[BASE64_ENCODED_PUBLIC_KEY]",
    "reason": "Account recovery for [USERNAME]: User verified via email ([EMAIL]) and phone ([PHONE]) on [DATE]. User lost device with all keys. Support ticket #[TICKET_NUMBER]. Verified by: [ADMIN_NAME]"
  }'

Follow-up:
[ ] User confirmed access with new key
[ ] User advised to add backup keys
[ ] User advised to enable 2FA (if available)
[ ] Ticket closed with resolution notes
```

---

## Related Documentation

- **Account Profiles Design**: `/docs/ACCOUNT_PROFILES_DESIGN.md`
- **API Documentation**: `/docs/API.md` (if exists)
- **Security Policies**: `/docs/SECURITY.md` (if exists)
- **Audit & Compliance**: `/docs/COMPLIANCE.md` (if exists)

---

## Contact

For questions or issues with admin operations:
- **Support Team**: support@example.com
- **Security Team**: security@example.com
- **Development Team**: dev@example.com

---

**Last Updated**: 2025-11-17
**Version**: 1.0
**Maintained By**: Backend Team
