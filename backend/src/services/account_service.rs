use crate::auth::{
    create_canonical_payload, derive_ic_principal, validate_replay_prevention, validate_username,
    verify_signature, AuthError,
};
use crate::models::{
    Account, AccountPublicKey, AccountPublicKeyResponse, AccountResponse, RegisterAccountRequest,
};
use crate::repositories::AccountRepository;
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
        let normalized_username = validate_username(&req.username)
            .map_err(|e| format!("Invalid username: {}", e))?;

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
            .record_signature_audit(
                &audit_id,
                Some(&account_id),
                "register_account",
                &canonical_json,
                &req.signature,
                &req.public_key,
                req.timestamp,
                &req.nonce,
                false,
                &now,
            )
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
        let normalized_username = validate_username(username)
            .map_err(|e| format!("Invalid username: {}", e))?;

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
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::initialize_database;
    use base64::{engine::general_purpose, Engine as _};
    use ed25519_dalek::{SigningKey, Signer};
    use sqlx::sqlite::SqlitePoolOptions;

    async fn setup_test_db() -> SqlitePool {
        let pool = SqlitePoolOptions::new().connect(":memory:").await.unwrap();
        initialize_database(&pool).await;
        pool
    }

    fn create_test_keypair() -> (SigningKey, String) {
        let signing_key = SigningKey::from_bytes(&[1u8; 32]);
        let public_key = general_purpose::STANDARD.encode(signing_key.verifying_key().to_bytes());
        (signing_key, public_key)
    }

    fn sign_payload(signing_key: &SigningKey, payload: &str) -> String {
        // Ed25519 signs the payload directly (no hash - dalek lib does it internally)
        let signature = signing_key.sign(payload.as_bytes());
        general_purpose::STANDARD.encode(signature.to_bytes())
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
}
