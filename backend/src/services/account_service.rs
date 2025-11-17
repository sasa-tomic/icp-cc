use crate::auth::{
    create_canonical_payload, derive_ic_principal, validate_replay_prevention, validate_username,
    verify_signature,
};
use crate::models::{
    AccountPublicKeyResponse, AccountResponse, AddPublicKeyRequest, RegisterAccountRequest,
    RemovePublicKeyRequest,
};
use crate::repositories::{AccountRepository, SignatureAuditParams};
use chrono::Utc;
use sqlx::SqlitePool;

pub struct AccountService {
    repo: AccountRepository,
    pool: SqlitePool,
}

impl AccountService {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            repo: AccountRepository::new(pool.clone()),
            pool,
        }
    }

    /// Registers a new account with the first public key
    pub async fn register_account(
        &self,
        req: RegisterAccountRequest,
    ) -> Result<AccountResponse, String> {
        // 1. Validate username format and check if reserved
        let normalized_username =
            validate_username(&req.username).map_err(|e| format!("Invalid username: {}", e))?;

        // 2. Validate replay prevention (timestamp + nonce)
        validate_replay_prevention(&self.pool, req.timestamp, &req.nonce)
            .await
            .map_err(|e| format!("Replay prevention failed: {}", e))?;

        // 3. Create canonical JSON payload for signature verification
        let payload = serde_json::json!({
            "action": "register_account",
            "nonce": req.nonce,
            "publicKey": req.public_key,
            "timestamp": req.timestamp,
            "username": normalized_username,
        });

        let canonical_json = create_canonical_payload(&payload);
        let payload_bytes = canonical_json.as_bytes();

        // 4. Verify signature
        verify_signature(&req.signature, payload_bytes, &req.public_key)
            .map_err(|e| format!("Signature verification failed: {}", e))?;

        // 5. Check username not already taken
        if self
            .repo
            .find_by_username(&normalized_username)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .is_some()
        {
            return Err(format!("Username '{}' already exists", normalized_username));
        }

        // 6. Check public key not already registered
        if self
            .repo
            .find_public_key_by_value(&req.public_key)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .is_some()
        {
            return Err("Public key already registered".to_string());
        }

        // 7. Derive IC principal from public key (backend computes, never trusts user input)
        let ic_principal = derive_ic_principal(&req.public_key)
            .map_err(|e| format!("Failed to derive IC principal: {}", e))?;

        // 8. Create account and add first public key
        let account_id = uuid::Uuid::new_v4().to_string();
        let key_id = uuid::Uuid::new_v4().to_string();
        let audit_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();

        self.repo
            .create_account(&account_id, &normalized_username, &now)
            .await
            .map_err(|e| format!("Failed to create account: {}", e))?;

        self.repo
            .add_public_key(&key_id, &account_id, &req.public_key, &ic_principal, &now)
            .await
            .map_err(|e| format!("Failed to add public key: {}", e))?;

        // 9. Record signature audit
        self.repo
            .record_signature_audit(SignatureAuditParams {
                audit_id: &audit_id,
                account_id: Some(&account_id),
                action: "register_account",
                payload: &canonical_json,
                signature: &req.signature,
                public_key: &req.public_key,
                timestamp: req.timestamp,
                nonce: &req.nonce,
                is_admin_action: false,
                now: &now,
            })
            .await
            .map_err(|e| format!("Failed to record audit: {}", e))?;

        // 10. Return created account
        Ok(AccountResponse {
            id: account_id,
            username: normalized_username,
            created_at: now.clone(),
            updated_at: Some(now.clone()),
            public_keys: vec![AccountPublicKeyResponse {
                id: key_id,
                public_key: req.public_key,
                ic_principal,
                added_at: now,
                is_active: true,
                disabled_at: None,
                disabled_by_key_id: None,
            }],
        })
    }

    /// Gets account by username with all public keys
    pub async fn get_account(&self, username: &str) -> Result<Option<AccountResponse>, String> {
        // Validate and normalize username
        let normalized_username =
            validate_username(username).map_err(|e| format!("Invalid username: {}", e))?;

        // Find account
        let account = self
            .repo
            .find_by_username(&normalized_username)
            .await
            .map_err(|e| format!("Database error: {}", e))?;

        let account = match account {
            Some(acc) => acc,
            None => return Ok(None),
        };

        // Get all public keys for account
        let keys = self
            .repo
            .get_account_keys(&account.id)
            .await
            .map_err(|e| format!("Database error: {}", e))?;

        let public_keys = keys
            .into_iter()
            .map(|k| AccountPublicKeyResponse {
                id: k.id,
                public_key: k.public_key,
                ic_principal: k.ic_principal,
                added_at: k.added_at,
                is_active: k.is_active,
                disabled_at: k.disabled_at,
                disabled_by_key_id: k.disabled_by_key_id,
            })
            .collect();

        Ok(Some(AccountResponse {
            id: account.id,
            username: account.username,
            created_at: account.created_at,
            updated_at: Some(account.updated_at),
            public_keys,
        }))
    }

    /// Adds a new public key to an existing account
    pub async fn add_public_key(
        &self,
        username: &str,
        req: AddPublicKeyRequest,
    ) -> Result<AccountPublicKeyResponse, String> {
        // 1. Validate username and get account
        let normalized_username =
            validate_username(username).map_err(|e| format!("Invalid username: {}", e))?;

        let account = self
            .repo
            .find_by_username(&normalized_username)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .ok_or_else(|| "Account not found".to_string())?;

        // 2. Validate replay prevention (timestamp + nonce)
        validate_replay_prevention(&self.pool, req.timestamp, &req.nonce)
            .await
            .map_err(|e| format!("Replay prevention failed: {}", e))?;

        // 3. Verify signing public key belongs to account and is active
        let signing_key = self
            .repo
            .find_public_key_by_value(&req.signing_public_key)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .ok_or_else(|| "Signing public key not found".to_string())?;

        if signing_key.account_id != account.id {
            return Err("Signing public key does not belong to this account".to_string());
        }

        if !signing_key.is_active {
            return Err("Signing public key is not active".to_string());
        }

        // 4. Create canonical JSON payload for signature verification
        let payload = serde_json::json!({
            "action": "add_key",
            "newPublicKey": req.new_public_key,
            "nonce": req.nonce,
            "signingPublicKey": req.signing_public_key,
            "timestamp": req.timestamp,
            "username": normalized_username,
        });

        let canonical_json = create_canonical_payload(&payload);
        let payload_bytes = canonical_json.as_bytes();

        // 5. Verify signature
        verify_signature(&req.signature, payload_bytes, &req.signing_public_key)
            .map_err(|e| format!("Signature verification failed: {}", e))?;

        // 6. Check new public key not already registered (anywhere)
        if self
            .repo
            .find_public_key_by_value(&req.new_public_key)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .is_some()
        {
            return Err("Public key already registered".to_string());
        }

        // 7. Check account has < 10 keys (max limit)
        let total_keys = self
            .repo
            .count_all_keys(&account.id)
            .await
            .map_err(|e| format!("Database error: {}", e))?;

        if total_keys >= 10 {
            return Err("Maximum number of keys (10) reached for this account".to_string());
        }

        // 8. Derive IC principal from new public key
        let ic_principal = derive_ic_principal(&req.new_public_key)
            .map_err(|e| format!("Failed to derive IC principal: {}", e))?;

        // 9. Add new public key to account
        let key_id = uuid::Uuid::new_v4().to_string();
        let audit_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();

        self.repo
            .add_public_key(
                &key_id,
                &account.id,
                &req.new_public_key,
                &ic_principal,
                &now,
            )
            .await
            .map_err(|e| format!("Failed to add public key: {}", e))?;

        // 10. Record signature audit
        self.repo
            .record_signature_audit(SignatureAuditParams {
                audit_id: &audit_id,
                account_id: Some(&account.id),
                action: "add_key",
                payload: &canonical_json,
                signature: &req.signature,
                public_key: &req.signing_public_key,
                timestamp: req.timestamp,
                nonce: &req.nonce,
                is_admin_action: false,
                now: &now,
            })
            .await
            .map_err(|e| format!("Failed to record audit: {}", e))?;

        // 11. Return created key
        Ok(AccountPublicKeyResponse {
            id: key_id,
            public_key: req.new_public_key,
            ic_principal,
            added_at: now,
            is_active: true,
            disabled_at: None,
            disabled_by_key_id: None,
        })
    }

    /// Removes a public key from an account (soft delete)
    pub async fn remove_public_key(
        &self,
        username: &str,
        key_id: &str,
        req: RemovePublicKeyRequest,
    ) -> Result<AccountPublicKeyResponse, String> {
        // 1. Validate username and get account
        let normalized_username =
            validate_username(username).map_err(|e| format!("Invalid username: {}", e))?;

        let account = self
            .repo
            .find_by_username(&normalized_username)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .ok_or_else(|| "Account not found".to_string())?;

        // 2. Validate replay prevention (timestamp + nonce)
        validate_replay_prevention(&self.pool, req.timestamp, &req.nonce)
            .await
            .map_err(|e| format!("Replay prevention failed: {}", e))?;

        // 3. Verify signing public key belongs to account and is active
        let signing_key = self
            .repo
            .find_public_key_by_value(&req.signing_public_key)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .ok_or_else(|| "Signing public key not found".to_string())?;

        if signing_key.account_id != account.id {
            return Err("Signing public key does not belong to this account".to_string());
        }

        if !signing_key.is_active {
            return Err("Signing public key is not active".to_string());
        }

        // 4. Create canonical JSON payload for signature verification
        let payload = serde_json::json!({
            "action": "remove_key",
            "keyId": key_id,
            "nonce": req.nonce,
            "signingPublicKey": req.signing_public_key,
            "timestamp": req.timestamp,
            "username": normalized_username,
        });

        let canonical_json = create_canonical_payload(&payload);
        let payload_bytes = canonical_json.as_bytes();

        // 5. Verify signature
        verify_signature(&req.signature, payload_bytes, &req.signing_public_key)
            .map_err(|e| format!("Signature verification failed: {}", e))?;

        // 6. Get key to remove and verify it belongs to account
        let key_to_remove = self
            .repo
            .find_key_by_id(key_id)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .ok_or_else(|| "Key not found".to_string())?;

        if key_to_remove.account_id != account.id {
            return Err("Key does not belong to this account".to_string());
        }

        // 7. Check we're not removing the last active key
        let active_keys_count = self
            .repo
            .count_active_keys(&account.id)
            .await
            .map_err(|e| format!("Database error: {}", e))?;

        if active_keys_count <= 1 {
            return Err("Cannot remove the last active key from account".to_string());
        }

        // 8. Disable the key (soft delete)
        let audit_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();

        self.repo
            .disable_key(key_id, &signing_key.id, &now)
            .await
            .map_err(|e| format!("Failed to disable key: {}", e))?;

        // 9. Record signature audit
        self.repo
            .record_signature_audit(SignatureAuditParams {
                audit_id: &audit_id,
                account_id: Some(&account.id),
                action: "remove_key",
                payload: &canonical_json,
                signature: &req.signature,
                public_key: &req.signing_public_key,
                timestamp: req.timestamp,
                nonce: &req.nonce,
                is_admin_action: false,
                now: &now,
            })
            .await
            .map_err(|e| format!("Failed to record audit: {}", e))?;

        // 10. Return disabled key
        Ok(AccountPublicKeyResponse {
            id: key_to_remove.id,
            public_key: key_to_remove.public_key,
            ic_principal: key_to_remove.ic_principal,
            added_at: key_to_remove.added_at,
            is_active: false,
            disabled_at: Some(now),
            disabled_by_key_id: Some(signing_key.id),
        })
    }

    /// Admin: Disables a public key (for compromised keys or account recovery)
    pub async fn admin_disable_key(
        &self,
        username: &str,
        key_id: &str,
        reason: &str,
    ) -> Result<crate::models::AdminKeyResponse, String> {
        // 1. Validate username and get account
        let normalized_username =
            validate_username(username).map_err(|e| format!("Invalid username: {}", e))?;

        let account = self
            .repo
            .find_by_username(&normalized_username)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .ok_or_else(|| "Account not found".to_string())?;

        // 2. Get key to disable and verify it belongs to account
        let key_to_disable = self
            .repo
            .find_key_by_id(key_id)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .ok_or_else(|| "Key not found".to_string())?;

        if key_to_disable.account_id != account.id {
            return Err("Key does not belong to this account".to_string());
        }

        // 3. Disable the key (soft delete)
        let audit_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();

        self.repo
            .disable_key(key_id, key_id, &now)
            .await
            .map_err(|e| format!("Failed to disable key: {}", e))?;

        // 4. Record admin action in audit trail
        let payload = serde_json::json!({
            "action": "admin_disable_key",
            "keyId": key_id,
            "reason": reason,
            "username": normalized_username,
        });
        let canonical_json = create_canonical_payload(&payload);

        self.repo
            .record_signature_audit(SignatureAuditParams {
                audit_id: &audit_id,
                account_id: Some(&account.id),
                action: "admin_disable_key",
                payload: &canonical_json,
                signature: "admin-action",
                public_key: "admin",
                timestamp: Utc::now().timestamp(),
                nonce: &uuid::Uuid::new_v4().to_string(),
                is_admin_action: true,
                now: &now,
            })
            .await
            .map_err(|e| format!("Failed to record audit: {}", e))?;

        // 5. Return disabled key
        Ok(crate::models::AdminKeyResponse {
            id: key_to_disable.id,
            public_key: key_to_disable.public_key,
            ic_principal: key_to_disable.ic_principal,
            is_active: false,
            disabled_at: Some(now),
            disabled_by_admin: Some(true),
            added_by_admin: None,
            added_at: None,
        })
    }

    /// Admin: Adds a recovery key to an account (for account recovery scenarios)
    pub async fn admin_add_recovery_key(
        &self,
        username: &str,
        public_key: &str,
        reason: &str,
    ) -> Result<crate::models::AdminKeyResponse, String> {
        // 1. Validate username and get account
        let normalized_username =
            validate_username(username).map_err(|e| format!("Invalid username: {}", e))?;

        let account = self
            .repo
            .find_by_username(&normalized_username)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .ok_or_else(|| "Account not found".to_string())?;

        // 2. Check new public key not already registered (anywhere)
        if self
            .repo
            .find_public_key_by_value(public_key)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .is_some()
        {
            return Err("Public key already registered".to_string());
        }

        // 3. Check account has < 10 keys (max limit)
        let total_keys = self
            .repo
            .count_all_keys(&account.id)
            .await
            .map_err(|e| format!("Database error: {}", e))?;

        if total_keys >= 10 {
            return Err("Maximum number of keys (10) reached for this account".to_string());
        }

        // 4. Derive IC principal from new public key
        let ic_principal = derive_ic_principal(public_key)
            .map_err(|e| format!("Failed to derive IC principal: {}", e))?;

        // 5. Add new public key to account
        let key_id = uuid::Uuid::new_v4().to_string();
        let audit_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();

        self.repo
            .add_public_key(&key_id, &account.id, public_key, &ic_principal, &now)
            .await
            .map_err(|e| format!("Failed to add public key: {}", e))?;

        // 6. Record admin action in audit trail
        let payload = serde_json::json!({
            "action": "admin_add_recovery_key",
            "newPublicKey": public_key,
            "reason": reason,
            "username": normalized_username,
        });
        let canonical_json = create_canonical_payload(&payload);

        self.repo
            .record_signature_audit(SignatureAuditParams {
                audit_id: &audit_id,
                account_id: Some(&account.id),
                action: "admin_add_recovery_key",
                payload: &canonical_json,
                signature: "admin-action",
                public_key: "admin",
                timestamp: Utc::now().timestamp(),
                nonce: &uuid::Uuid::new_v4().to_string(),
                is_admin_action: true,
                now: &now,
            })
            .await
            .map_err(|e| format!("Failed to record audit: {}", e))?;

        // 7. Return created key
        Ok(crate::models::AdminKeyResponse {
            id: key_id,
            public_key: public_key.to_string(),
            ic_principal,
            is_active: true,
            disabled_at: None,
            disabled_by_admin: None,
            added_by_admin: Some(true),
            added_at: Some(now),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::initialize_database;
    use ed25519_dalek::{Signer, SigningKey};
    use sqlx::sqlite::SqlitePoolOptions;

    async fn setup_test_db() -> SqlitePool {
        let pool = SqlitePoolOptions::new().connect(":memory:").await.unwrap();
        initialize_database(&pool).await;
        pool
    }

    fn create_test_keypair() -> (SigningKey, String) {
        // Generate a unique keypair using UUID for unique seed
        let uuid_bytes = uuid::Uuid::new_v4().as_bytes().to_owned();
        let mut seed = [0u8; 32];
        // Fill seed with UUID bytes (16 bytes) doubled
        seed[..16].copy_from_slice(&uuid_bytes);
        seed[16..].copy_from_slice(&uuid_bytes);
        let signing_key = SigningKey::from_bytes(&seed);
        // Return hex-encoded public key (matches Flutter app format)
        let public_key = hex::encode(signing_key.verifying_key().to_bytes());
        (signing_key, public_key)
    }

    fn sign_payload(signing_key: &SigningKey, payload: &str) -> String {
        // Standard Ed25519: sign message directly (RFC 8032)
        // The algorithm does SHA-512 internally as part of the signature process
        let signature = signing_key.sign(payload.as_bytes());

        // Return hex-encoded signature (matches Flutter app format)
        hex::encode(signature.to_bytes())
    }

    #[tokio::test]
    async fn test_register_account_success() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        let (signing_key, public_key) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce = uuid::Uuid::new_v4().to_string();

        // Create canonical payload
        let payload = serde_json::json!({
            "action": "register_account",
            "nonce": nonce,
            "publicKey": public_key,
            "timestamp": timestamp,
            "username": "alice",
        });
        let canonical = create_canonical_payload(&payload);
        let signature = sign_payload(&signing_key, &canonical);

        let req = RegisterAccountRequest {
            username: "alice".to_string(),
            public_key: public_key.clone(),
            timestamp,
            nonce,
            signature,
        };

        let result = service.register_account(req).await;
        assert!(result.is_ok());

        let account = result.unwrap();
        assert_eq!(account.username, "alice");
        assert_eq!(account.public_keys.len(), 1);
        assert_eq!(account.public_keys[0].public_key, public_key);
        assert!(account.public_keys[0].is_active);
    }

    #[tokio::test]
    async fn test_register_account_duplicate_username() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        let (signing_key, public_key) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key,
            "timestamp": timestamp,
            "username": "alice",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key, &canonical1);

        let req1 = RegisterAccountRequest {
            username: "alice".to_string(),
            public_key: public_key.clone(),
            timestamp,
            nonce: nonce1,
            signature: signature1,
        };

        // First registration should succeed
        assert!(service.register_account(req1).await.is_ok());

        // Second registration with same username should fail
        let (signing_key2, public_key2) = create_test_keypair();
        let nonce2 = uuid::Uuid::new_v4().to_string();

        let payload2 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce2,
            "publicKey": public_key2,
            "timestamp": timestamp,
            "username": "alice",
        });
        let canonical2 = create_canonical_payload(&payload2);
        let signature2 = sign_payload(&signing_key2, &canonical2);

        let req2 = RegisterAccountRequest {
            username: "alice".to_string(),
            public_key: public_key2,
            timestamp,
            nonce: nonce2,
            signature: signature2,
        };

        let result = service.register_account(req2).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("already exists"));
    }

    #[tokio::test]
    async fn test_register_account_invalid_username() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        let (signing_key, public_key) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce = uuid::Uuid::new_v4().to_string();

        let payload = serde_json::json!({
            "action": "register_account",
            "nonce": nonce,
            "publicKey": public_key,
            "timestamp": timestamp,
            "username": "ab", // Too short
        });
        let canonical = create_canonical_payload(&payload);
        let signature = sign_payload(&signing_key, &canonical);

        let req = RegisterAccountRequest {
            username: "ab".to_string(),
            public_key,
            timestamp,
            nonce,
            signature,
        };

        let result = service.register_account(req).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid username"));
    }

    #[tokio::test]
    async fn test_get_account_success() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account first
        let (signing_key, public_key) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce = uuid::Uuid::new_v4().to_string();

        let payload = serde_json::json!({
            "action": "register_account",
            "nonce": nonce,
            "publicKey": public_key,
            "timestamp": timestamp,
            "username": "alice",
        });
        let canonical = create_canonical_payload(&payload);
        let signature = sign_payload(&signing_key, &canonical);

        let req = RegisterAccountRequest {
            username: "alice".to_string(),
            public_key: public_key.clone(),
            timestamp,
            nonce,
            signature,
        };

        service.register_account(req).await.unwrap();

        // Get account
        let result = service.get_account("alice").await;
        assert!(result.is_ok());

        let account = result.unwrap();
        assert!(account.is_some());

        let account = account.unwrap();
        assert_eq!(account.username, "alice");
        assert_eq!(account.public_keys.len(), 1);
        assert_eq!(account.public_keys[0].public_key, public_key);
    }

    #[tokio::test]
    async fn test_get_account_not_found() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        let result = service.get_account("nonexistent").await;
        assert!(result.is_ok());
        assert!(result.unwrap().is_none());
    }

    #[tokio::test]
    async fn test_add_public_key_success() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account first
        let (signing_key1, public_key1) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "alice",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        let reg_req = RegisterAccountRequest {
            username: "alice".to_string(),
            public_key: public_key1.clone(),
            timestamp,
            nonce: nonce1,
            signature: signature1,
        };

        service.register_account(reg_req).await.unwrap();

        // Add second key
        let (_, public_key2) = create_test_keypair();
        let nonce2 = uuid::Uuid::new_v4().to_string();

        let payload2 = serde_json::json!({
            "action": "add_key",
            "newPublicKey": public_key2,
            "nonce": nonce2,
            "signingPublicKey": public_key1,
            "timestamp": timestamp,
            "username": "alice",
        });
        let canonical2 = create_canonical_payload(&payload2);
        let signature2 = sign_payload(&signing_key1, &canonical2);

        let add_req = AddPublicKeyRequest {
            new_public_key: public_key2.clone(),
            signing_public_key: public_key1.clone(),
            timestamp,
            nonce: nonce2,
            signature: signature2,
        };

        let result = service.add_public_key("alice", add_req).await;
        assert!(result.is_ok());

        let key = result.unwrap();
        assert_eq!(key.public_key, public_key2);
        assert!(key.is_active);
        assert!(key.disabled_at.is_none());

        // Verify account now has 2 keys
        let account = service.get_account("alice").await.unwrap().unwrap();
        assert_eq!(account.public_keys.len(), 2);
    }

    #[tokio::test]
    async fn test_add_public_key_max_keys_exceeded() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account
        let (signing_key1, public_key1) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "bob",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        service
            .register_account(RegisterAccountRequest {
                username: "bob".to_string(),
                public_key: public_key1.clone(),
                timestamp,
                nonce: nonce1,
                signature: signature1,
            })
            .await
            .unwrap();

        // Add 9 more keys (total 10)
        for _ in 0..9 {
            let (_, new_key) = create_test_keypair();
            let nonce = uuid::Uuid::new_v4().to_string();

            let payload = serde_json::json!({
                "action": "add_key",
                "newPublicKey": new_key,
                "nonce": nonce,
                "signingPublicKey": public_key1,
                "timestamp": timestamp,
                "username": "bob",
            });
            let canonical = create_canonical_payload(&payload);
            let signature = sign_payload(&signing_key1, &canonical);

            service
                .add_public_key(
                    "bob",
                    AddPublicKeyRequest {
                        new_public_key: new_key,
                        signing_public_key: public_key1.clone(),
                        timestamp,
                        nonce,
                        signature,
                    },
                )
                .await
                .unwrap();
        }

        // Try to add 11th key (should fail)
        let (_, key11) = create_test_keypair();
        let nonce11 = uuid::Uuid::new_v4().to_string();

        let payload11 = serde_json::json!({
            "action": "add_key",
            "newPublicKey": key11,
            "nonce": nonce11,
            "signingPublicKey": public_key1,
            "timestamp": timestamp,
            "username": "bob",
        });
        let canonical11 = create_canonical_payload(&payload11);
        let signature11 = sign_payload(&signing_key1, &canonical11);

        let result = service
            .add_public_key(
                "bob",
                AddPublicKeyRequest {
                    new_public_key: key11,
                    signing_public_key: public_key1,
                    timestamp,
                    nonce: nonce11,
                    signature: signature11,
                },
            )
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Maximum number"));
    }

    #[tokio::test]
    async fn test_add_public_key_duplicate_rejected() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account
        let (signing_key1, public_key1) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "charlie",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        service
            .register_account(RegisterAccountRequest {
                username: "charlie".to_string(),
                public_key: public_key1.clone(),
                timestamp,
                nonce: nonce1,
                signature: signature1,
            })
            .await
            .unwrap();

        // Try to add the same key again (should fail)
        let nonce2 = uuid::Uuid::new_v4().to_string();

        let payload2 = serde_json::json!({
            "action": "add_key",
            "newPublicKey": public_key1,
            "nonce": nonce2,
            "signingPublicKey": public_key1,
            "timestamp": timestamp,
            "username": "charlie",
        });
        let canonical2 = create_canonical_payload(&payload2);
        let signature2 = sign_payload(&signing_key1, &canonical2);

        let result = service
            .add_public_key(
                "charlie",
                AddPublicKeyRequest {
                    new_public_key: public_key1.clone(),
                    signing_public_key: public_key1,
                    timestamp,
                    nonce: nonce2,
                    signature: signature2,
                },
            )
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("already registered"));
    }

    #[tokio::test]
    async fn test_add_public_key_inactive_signing_key() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account with two keys
        let (signing_key1, public_key1) = create_test_keypair();
        let (signing_key2, public_key2) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        // Register with first key
        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "dave",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        service
            .register_account(RegisterAccountRequest {
                username: "dave".to_string(),
                public_key: public_key1.clone(),
                timestamp,
                nonce: nonce1,
                signature: signature1,
            })
            .await
            .unwrap();

        // Add second key
        let nonce2 = uuid::Uuid::new_v4().to_string();
        let payload2 = serde_json::json!({
            "action": "add_key",
            "newPublicKey": public_key2,
            "nonce": nonce2,
            "signingPublicKey": public_key1,
            "timestamp": timestamp,
            "username": "dave",
        });
        let canonical2 = create_canonical_payload(&payload2);
        let signature2 = sign_payload(&signing_key1, &canonical2);

        service
            .add_public_key(
                "dave",
                AddPublicKeyRequest {
                    new_public_key: public_key2.clone(),
                    signing_public_key: public_key1.clone(),
                    timestamp,
                    nonce: nonce2,
                    signature: signature2,
                },
            )
            .await
            .unwrap();

        // Get key2 ID for removal
        let account = service.get_account("dave").await.unwrap().unwrap();
        let key1_id = account
            .public_keys
            .iter()
            .find(|k| k.public_key == public_key1)
            .unwrap()
            .id
            .clone();

        // Remove first key (using second key to sign)
        let nonce3 = uuid::Uuid::new_v4().to_string();
        let payload3 = serde_json::json!({
            "action": "remove_key",
            "keyId": key1_id,
            "nonce": nonce3,
            "signingPublicKey": public_key2,
            "timestamp": timestamp,
            "username": "dave",
        });
        let canonical3 = create_canonical_payload(&payload3);
        let signature3 = sign_payload(&signing_key2, &canonical3);

        service
            .remove_public_key(
                "dave",
                &key1_id,
                RemovePublicKeyRequest {
                    signing_public_key: public_key2.clone(),
                    timestamp,
                    nonce: nonce3,
                    signature: signature3,
                },
            )
            .await
            .unwrap();

        // Now try to add a third key using the removed (inactive) first key
        let (_, public_key3) = create_test_keypair();
        let nonce4 = uuid::Uuid::new_v4().to_string();

        let payload4 = serde_json::json!({
            "action": "add_key",
            "newPublicKey": public_key3,
            "nonce": nonce4,
            "signingPublicKey": public_key1,
            "timestamp": timestamp,
            "username": "dave",
        });
        let canonical4 = create_canonical_payload(&payload4);
        let signature4 = sign_payload(&signing_key1, &canonical4);

        let result = service
            .add_public_key(
                "dave",
                AddPublicKeyRequest {
                    new_public_key: public_key3,
                    signing_public_key: public_key1,
                    timestamp,
                    nonce: nonce4,
                    signature: signature4,
                },
            )
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not active"));
    }

    #[tokio::test]
    async fn test_remove_public_key_success() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account
        let (signing_key1, public_key1) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "eve",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        service
            .register_account(RegisterAccountRequest {
                username: "eve".to_string(),
                public_key: public_key1.clone(),
                timestamp,
                nonce: nonce1,
                signature: signature1,
            })
            .await
            .unwrap();

        // Add second key
        let (_, public_key2) = create_test_keypair();
        let nonce2 = uuid::Uuid::new_v4().to_string();

        let payload2 = serde_json::json!({
            "action": "add_key",
            "newPublicKey": public_key2,
            "nonce": nonce2,
            "signingPublicKey": public_key1,
            "timestamp": timestamp,
            "username": "eve",
        });
        let canonical2 = create_canonical_payload(&payload2);
        let signature2 = sign_payload(&signing_key1, &canonical2);

        service
            .add_public_key(
                "eve",
                AddPublicKeyRequest {
                    new_public_key: public_key2.clone(),
                    signing_public_key: public_key1.clone(),
                    timestamp,
                    nonce: nonce2,
                    signature: signature2,
                },
            )
            .await
            .unwrap();

        // Get key2 ID
        let account = service.get_account("eve").await.unwrap().unwrap();
        let key2_id = account
            .public_keys
            .iter()
            .find(|k| k.public_key == public_key2)
            .unwrap()
            .id
            .clone();

        // Remove second key
        let nonce3 = uuid::Uuid::new_v4().to_string();
        let payload3 = serde_json::json!({
            "action": "remove_key",
            "keyId": key2_id,
            "nonce": nonce3,
            "signingPublicKey": public_key1,
            "timestamp": timestamp,
            "username": "eve",
        });
        let canonical3 = create_canonical_payload(&payload3);
        let signature3 = sign_payload(&signing_key1, &canonical3);

        let result = service
            .remove_public_key(
                "eve",
                &key2_id,
                RemovePublicKeyRequest {
                    signing_public_key: public_key1,
                    timestamp,
                    nonce: nonce3,
                    signature: signature3,
                },
            )
            .await;

        assert!(result.is_ok());

        let removed_key = result.unwrap();
        assert_eq!(removed_key.public_key, public_key2);
        assert!(!removed_key.is_active);
        assert!(removed_key.disabled_at.is_some());
        assert!(removed_key.disabled_by_key_id.is_some());

        // Verify account still has 2 keys, but only 1 active
        let account = service.get_account("eve").await.unwrap().unwrap();
        assert_eq!(account.public_keys.len(), 2);
        assert_eq!(
            account.public_keys.iter().filter(|k| k.is_active).count(),
            1
        );
    }

    #[tokio::test]
    async fn test_remove_last_active_key_rejected() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account
        let (signing_key1, public_key1) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "frank",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        service
            .register_account(RegisterAccountRequest {
                username: "frank".to_string(),
                public_key: public_key1.clone(),
                timestamp,
                nonce: nonce1,
                signature: signature1,
            })
            .await
            .unwrap();

        // Get key1 ID
        let account = service.get_account("frank").await.unwrap().unwrap();
        let key1_id = account.public_keys[0].id.clone();

        // Try to remove the only active key
        let nonce2 = uuid::Uuid::new_v4().to_string();
        let payload2 = serde_json::json!({
            "action": "remove_key",
            "keyId": key1_id,
            "nonce": nonce2,
            "signingPublicKey": public_key1,
            "timestamp": timestamp,
            "username": "frank",
        });
        let canonical2 = create_canonical_payload(&payload2);
        let signature2 = sign_payload(&signing_key1, &canonical2);

        let result = service
            .remove_public_key(
                "frank",
                &key1_id,
                RemovePublicKeyRequest {
                    signing_public_key: public_key1,
                    timestamp,
                    nonce: nonce2,
                    signature: signature2,
                },
            )
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("last active key"));
    }

    // Admin Operation Tests

    #[tokio::test]
    async fn test_admin_disable_key_success() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account with two keys
        let (signing_key1, public_key1) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "george",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        service
            .register_account(RegisterAccountRequest {
                username: "george".to_string(),
                public_key: public_key1.clone(),
                timestamp,
                nonce: nonce1,
                signature: signature1,
            })
            .await
            .unwrap();

        // Add second key
        let (_, public_key2) = create_test_keypair();
        let nonce2 = uuid::Uuid::new_v4().to_string();
        let payload2 = serde_json::json!({
            "action": "add_key",
            "newPublicKey": public_key2,
            "nonce": nonce2,
            "signingPublicKey": public_key1,
            "timestamp": timestamp,
            "username": "george",
        });
        let canonical2 = create_canonical_payload(&payload2);
        let signature2 = sign_payload(&signing_key1, &canonical2);

        service
            .add_public_key(
                "george",
                AddPublicKeyRequest {
                    new_public_key: public_key2.clone(),
                    signing_public_key: public_key1.clone(),
                    timestamp,
                    nonce: nonce2,
                    signature: signature2,
                },
            )
            .await
            .unwrap();

        // Get key2 ID
        let account = service.get_account("george").await.unwrap().unwrap();
        let key2_id = account
            .public_keys
            .iter()
            .find(|k| k.public_key == public_key2)
            .unwrap()
            .id
            .clone();

        // Admin disables second key
        let result = service
            .admin_disable_key("george", &key2_id, "User reported compromise")
            .await;

        assert!(result.is_ok());
        let disabled_key = result.unwrap();
        assert_eq!(disabled_key.public_key, public_key2);
        assert!(!disabled_key.is_active);
        assert!(disabled_key.disabled_at.is_some());
        assert_eq!(disabled_key.disabled_by_admin, Some(true));

        // Verify account still has 2 keys, but only 1 active
        let account = service.get_account("george").await.unwrap().unwrap();
        assert_eq!(account.public_keys.len(), 2);
        assert_eq!(
            account.public_keys.iter().filter(|k| k.is_active).count(),
            1
        );
    }

    #[tokio::test]
    async fn test_admin_disable_key_account_not_found() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        let result = service
            .admin_disable_key("nonexistent", "some-key-id", "test reason")
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Account not found"));
    }

    #[tokio::test]
    async fn test_admin_disable_key_not_found() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account
        let (signing_key1, public_key1) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "harry",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        service
            .register_account(RegisterAccountRequest {
                username: "harry".to_string(),
                public_key: public_key1,
                timestamp,
                nonce: nonce1,
                signature: signature1,
            })
            .await
            .unwrap();

        // Try to disable non-existent key
        let result = service
            .admin_disable_key("harry", "nonexistent-key-id", "test reason")
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Key not found"));
    }

    #[tokio::test]
    async fn test_admin_add_recovery_key_success() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account
        let (signing_key1, public_key1) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "iris",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        service
            .register_account(RegisterAccountRequest {
                username: "iris".to_string(),
                public_key: public_key1,
                timestamp,
                nonce: nonce1,
                signature: signature1,
            })
            .await
            .unwrap();

        // Admin adds recovery key
        let (_, recovery_key) = create_test_keypair();
        let result = service
            .admin_add_recovery_key("iris", &recovery_key, "User lost all keys")
            .await;

        assert!(result.is_ok());
        let added_key = result.unwrap();
        assert_eq!(added_key.public_key, recovery_key);
        assert!(added_key.is_active);
        assert_eq!(added_key.added_by_admin, Some(true));
        assert!(added_key.added_at.is_some());

        // Verify account now has 2 keys
        let account = service.get_account("iris").await.unwrap().unwrap();
        assert_eq!(account.public_keys.len(), 2);
        assert_eq!(
            account.public_keys.iter().filter(|k| k.is_active).count(),
            2
        );
    }

    #[tokio::test]
    async fn test_admin_add_recovery_key_account_not_found() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        let (_, recovery_key) = create_test_keypair();
        let result = service
            .admin_add_recovery_key("nonexistent", &recovery_key, "test reason")
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Account not found"));
    }

    #[tokio::test]
    async fn test_admin_add_recovery_key_duplicate_rejected() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account
        let (signing_key1, public_key1) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "jack",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        service
            .register_account(RegisterAccountRequest {
                username: "jack".to_string(),
                public_key: public_key1.clone(),
                timestamp,
                nonce: nonce1,
                signature: signature1,
            })
            .await
            .unwrap();

        // Try to add existing key as recovery key
        let result = service
            .admin_add_recovery_key("jack", &public_key1, "test reason")
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("already registered"));
    }

    #[tokio::test]
    async fn test_admin_add_recovery_key_max_keys_exceeded() {
        let pool = setup_test_db().await;
        let service = AccountService::new(pool);

        // Register account
        let (signing_key1, public_key1) = create_test_keypair();
        let timestamp = Utc::now().timestamp();
        let nonce1 = uuid::Uuid::new_v4().to_string();

        let payload1 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce1,
            "publicKey": public_key1,
            "timestamp": timestamp,
            "username": "kate",
        });
        let canonical1 = create_canonical_payload(&payload1);
        let signature1 = sign_payload(&signing_key1, &canonical1);

        service
            .register_account(RegisterAccountRequest {
                username: "kate".to_string(),
                public_key: public_key1.clone(),
                timestamp,
                nonce: nonce1,
                signature: signature1,
            })
            .await
            .unwrap();

        // Add 9 more keys (total 10)
        for _ in 0..9 {
            let (_, new_key) = create_test_keypair();
            let nonce = uuid::Uuid::new_v4().to_string();

            let payload = serde_json::json!({
                "action": "add_key",
                "newPublicKey": new_key,
                "nonce": nonce,
                "signingPublicKey": public_key1,
                "timestamp": timestamp,
                "username": "kate",
            });
            let canonical = create_canonical_payload(&payload);
            let signature = sign_payload(&signing_key1, &canonical);

            service
                .add_public_key(
                    "kate",
                    AddPublicKeyRequest {
                        new_public_key: new_key,
                        signing_public_key: public_key1.clone(),
                        timestamp,
                        nonce,
                        signature,
                    },
                )
                .await
                .unwrap();
        }

        // Try to add 11th key via admin (should fail)
        let (_, key11) = create_test_keypair();
        let result = service
            .admin_add_recovery_key("kate", &key11, "test reason")
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Maximum number"));
    }
}
