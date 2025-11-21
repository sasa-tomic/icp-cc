use crate::auth::{
    create_canonical_payload, derive_ic_principal, validate_replay_prevention, validate_username,
    verify_signature,
};
use crate::models::{
    AccountPublicKeyResponse, AccountResponse, AddPublicKeyRequest, RegisterAccountRequest,
    RemovePublicKeyRequest, UpdateAccountRequest,
};
use crate::repositories::{
    AccountRepository, CreateAccountParams, SignatureAuditParams, UpdateAccountParams,
};
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
            .create_account(CreateAccountParams {
                account_id: &account_id,
                username: &normalized_username,
                display_name: &req.display_name,
                contact_email: req.contact_email.as_deref(),
                contact_telegram: req.contact_telegram.as_deref(),
                contact_twitter: req.contact_twitter.as_deref(),
                contact_discord: req.contact_discord.as_deref(),
                website_url: req.website_url.as_deref(),
                bio: req.bio.as_deref(),
                now: &now,
            })
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
            display_name: req.display_name,
            contact_email: req.contact_email,
            contact_telegram: req.contact_telegram,
            contact_twitter: req.contact_twitter,
            contact_discord: req.contact_discord,
            website_url: req.website_url,
            bio: req.bio,
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
            display_name: account.display_name,
            contact_email: account.contact_email,
            contact_telegram: account.contact_telegram,
            contact_twitter: account.contact_twitter,
            contact_discord: account.contact_discord,
            website_url: account.website_url,
            bio: account.bio,
            created_at: account.created_at,
            updated_at: Some(account.updated_at),
            public_keys,
        }))
    }

    /// Gets account by public key with all public keys
    ///
    /// This allows clients to find their account without knowing the username,
    /// using only their cryptographic keypair (public key).
    pub async fn get_account_by_public_key(
        &self,
        public_key: &str,
    ) -> Result<Option<AccountResponse>, String> {
        // Find the public key record
        let key_record = self
            .repo
            .find_public_key_by_value(public_key)
            .await
            .map_err(|e| format!("Database error: {}", e))?;

        let key_record = match key_record {
            Some(k) => k,
            None => return Ok(None), // Public key not registered
        };

        // Get the account by ID
        let account = self
            .repo
            .find_by_id(&key_record.account_id)
            .await
            .map_err(|e| format!("Database error: {}", e))?
            .ok_or_else(|| "Account not found for public key".to_string())?;

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
            display_name: account.display_name,
            contact_email: account.contact_email,
            contact_telegram: account.contact_telegram,
            contact_twitter: account.contact_twitter,
            contact_discord: account.contact_discord,
            website_url: account.website_url,
            bio: account.bio,
            created_at: account.created_at,
            updated_at: Some(account.updated_at),
            public_keys,
        }))
    }

    /// Updates account profile information
    pub async fn update_profile(
        &self,
        username: &str,
        req: UpdateAccountRequest,
    ) -> Result<AccountResponse, String> {
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
        let mut payload = serde_json::json!({
            "action": "update_profile",
            "nonce": req.nonce,
            "signingPublicKey": req.signing_public_key,
            "timestamp": req.timestamp,
            "username": normalized_username,
        });

        // Macro to reduce duplication for adding optional fields to payload
        macro_rules! add_payload_field {
            ($field:expr, $key:literal) => {
                if let Some(ref value) = $field {
                    payload[$key] = serde_json::json!(value);
                }
            };
        }

        // Include only fields being updated in the signature payload
        add_payload_field!(req.display_name, "displayName");
        add_payload_field!(req.contact_email, "contactEmail");
        add_payload_field!(req.contact_telegram, "contactTelegram");
        add_payload_field!(req.contact_twitter, "contactTwitter");
        add_payload_field!(req.contact_discord, "contactDiscord");
        add_payload_field!(req.website_url, "websiteUrl");
        add_payload_field!(req.bio, "bio");

        let canonical_json = create_canonical_payload(&payload);
        let payload_bytes = canonical_json.as_bytes();

        // 5. Verify signature
        verify_signature(&req.signature, payload_bytes, &req.signing_public_key)
            .map_err(|e| format!("Signature verification failed: {}", e))?;

        // 6. Update account
        let audit_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();

        self.repo
            .update_account(UpdateAccountParams {
                account_id: &account.id,
                display_name: req.display_name.as_deref(),
                contact_email: req.contact_email.as_deref(),
                contact_telegram: req.contact_telegram.as_deref(),
                contact_twitter: req.contact_twitter.as_deref(),
                contact_discord: req.contact_discord.as_deref(),
                website_url: req.website_url.as_deref(),
                bio: req.bio.as_deref(),
                now: &now,
            })
            .await
            .map_err(|e| format!("Failed to update account: {}", e))?;

        // 7. Record signature audit
        self.repo
            .record_signature_audit(SignatureAuditParams {
                audit_id: &audit_id,
                account_id: Some(&account.id),
                action: "update_profile",
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

        // 8. Return updated account (fetch fresh from DB)
        self.get_account(&normalized_username)
            .await?
            .ok_or_else(|| "Failed to fetch updated account".to_string())
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

    /// Test fixture providing common test setup
    struct TestContext {
        service: AccountService,
        signing_key: SigningKey,
        public_key: String,
        timestamp: i64,
    }

    impl TestContext {
        async fn new() -> Self {
            let pool = setup_test_db().await;
            let service = AccountService::new(pool);
            let (signing_key, public_key) = create_test_keypair();
            let timestamp = Utc::now().timestamp();
            Self {
                service,
                signing_key,
                public_key,
                timestamp,
            }
        }
    }

    fn create_test_keypair() -> (SigningKey, String) {
        use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
        // Generate a unique keypair using UUID for unique seed
        let uuid_bytes = uuid::Uuid::new_v4().as_bytes().to_owned();
        let mut seed = [0u8; 32];
        // Fill seed with UUID bytes (16 bytes) doubled
        seed[..16].copy_from_slice(&uuid_bytes);
        seed[16..].copy_from_slice(&uuid_bytes);
        let signing_key = SigningKey::from_bytes(&seed);
        // Return base64-encoded public key (matches Flutter app format)
        let public_key = B64.encode(signing_key.verifying_key().to_bytes());
        (signing_key, public_key)
    }

    fn sign_payload(signing_key: &SigningKey, payload: &str) -> String {
        use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
        // Standard Ed25519: sign message directly (RFC 8032)
        // The algorithm does SHA-512 internally as part of the signature process
        let signature = signing_key.sign(payload.as_bytes());

        // Return base64-encoded signature (matches Flutter app format)
        B64.encode(signature.to_bytes())
    }

    fn build_register_account_request(
        username: &str,
        public_key: String,
        timestamp: i64,
        nonce: String,
        signature: String,
    ) -> RegisterAccountRequest {
        RegisterAccountRequest {
            username: username.to_string(),
            display_name: format!("{username}-display"),
            contact_email: None,
            contact_telegram: None,
            contact_twitter: None,
            contact_discord: None,
            website_url: None,
            bio: None,
            public_key,
            timestamp,
            nonce,
            signature,
        }
    }

    /// Helper: Register account and return the account response
    async fn test_register_account(
        service: &AccountService,
        username: &str,
        signing_key: &SigningKey,
        public_key: &str,
        timestamp: i64,
    ) -> AccountResponse {
        let nonce = uuid::Uuid::new_v4().to_string();
        let payload = serde_json::json!({
            "action": "register_account",
            "nonce": nonce,
            "publicKey": public_key,
            "timestamp": timestamp,
            "username": username,
        });
        let canonical = create_canonical_payload(&payload);
        let signature = sign_payload(signing_key, &canonical);

        service
            .register_account(build_register_account_request(
                username,
                public_key.to_string(),
                timestamp,
                nonce,
                signature,
            ))
            .await
            .unwrap()
    }

    /// Helper: Create and sign an AddPublicKeyRequest
    fn create_add_key_request(
        username: &str,
        new_public_key: &str,
        signing_key: &SigningKey,
        signing_public_key: &str,
        timestamp: i64,
    ) -> AddPublicKeyRequest {
        let nonce = uuid::Uuid::new_v4().to_string();
        let payload = serde_json::json!({
            "action": "add_key",
            "newPublicKey": new_public_key,
            "nonce": nonce,
            "signingPublicKey": signing_public_key,
            "timestamp": timestamp,
            "username": username,
        });
        let canonical = create_canonical_payload(&payload);
        let signature = sign_payload(signing_key, &canonical);

        AddPublicKeyRequest {
            new_public_key: new_public_key.to_string(),
            signing_public_key: signing_public_key.to_string(),
            timestamp,
            nonce,
            signature,
        }
    }

    /// Helper: Create and sign a RemovePublicKeyRequest
    fn create_remove_key_request(
        username: &str,
        key_id: &str,
        signing_key: &SigningKey,
        signing_public_key: &str,
        timestamp: i64,
    ) -> RemovePublicKeyRequest {
        let nonce = uuid::Uuid::new_v4().to_string();
        let payload = serde_json::json!({
            "action": "remove_key",
            "keyId": key_id,
            "nonce": nonce,
            "signingPublicKey": signing_public_key,
            "timestamp": timestamp,
            "username": username,
        });
        let canonical = create_canonical_payload(&payload);
        let signature = sign_payload(signing_key, &canonical);

        RemovePublicKeyRequest {
            signing_public_key: signing_public_key.to_string(),
            timestamp,
            nonce,
            signature,
        }
    }

    /// Helper: Create and sign an UpdateAccountRequest
    fn create_update_account_request(
        username: &str,
        signing_key: &SigningKey,
        signing_public_key: &str,
        timestamp: i64,
        display_name: Option<String>,
        bio: Option<String>,
    ) -> UpdateAccountRequest {
        let nonce = uuid::Uuid::new_v4().to_string();
        let mut payload = serde_json::json!({
            "action": "update_profile",
            "nonce": nonce,
            "signingPublicKey": signing_public_key,
            "timestamp": timestamp,
            "username": username,
        });

        if let Some(ref dn) = display_name {
            payload["displayName"] = serde_json::json!(dn);
        }
        if let Some(ref b) = bio {
            payload["bio"] = serde_json::json!(b);
        }

        let canonical = create_canonical_payload(&payload);
        let signature = sign_payload(signing_key, &canonical);

        UpdateAccountRequest {
            display_name,
            contact_email: None,
            contact_telegram: None,
            contact_twitter: None,
            contact_discord: None,
            website_url: None,
            bio,
            signing_public_key: signing_public_key.to_string(),
            timestamp,
            nonce,
            signature,
        }
    }

    #[tokio::test]
    async fn test_register_account_success() {
        let ctx = TestContext::new().await;
        let nonce = uuid::Uuid::new_v4().to_string();

        // Create canonical payload
        let payload = serde_json::json!({
            "action": "register_account",
            "nonce": nonce,
            "publicKey": ctx.public_key,
            "timestamp": ctx.timestamp,
            "username": "alice",
        });
        let canonical = create_canonical_payload(&payload);
        let signature = sign_payload(&ctx.signing_key, &canonical);

        let req = build_register_account_request(
            "alice",
            ctx.public_key.clone(),
            ctx.timestamp,
            nonce,
            signature,
        );

        let result = ctx.service.register_account(req).await;
        assert!(result.is_ok());

        let account = result.unwrap();
        assert_eq!(account.username, "alice");
        assert_eq!(account.display_name, "alice-display");
        assert_eq!(account.public_keys.len(), 1);
        assert_eq!(account.public_keys[0].public_key, ctx.public_key);
        assert!(account.public_keys[0].is_active);
    }

    #[tokio::test]
    async fn test_register_account_duplicate_username() {
        let ctx = TestContext::new().await;

        // First registration should succeed
        test_register_account(
            &ctx.service,
            "alice",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Second registration with same username should fail
        let (signing_key2, public_key2) = create_test_keypair();
        let nonce2 = uuid::Uuid::new_v4().to_string();

        let payload2 = serde_json::json!({
            "action": "register_account",
            "nonce": nonce2,
            "publicKey": public_key2,
            "timestamp": ctx.timestamp,
            "username": "alice",
        });
        let canonical2 = create_canonical_payload(&payload2);
        let signature2 = sign_payload(&signing_key2, &canonical2);

        let req2 =
            build_register_account_request("alice", public_key2, ctx.timestamp, nonce2, signature2);

        let result = ctx.service.register_account(req2).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("already exists"));
    }

    #[tokio::test]
    async fn test_register_account_invalid_username() {
        let ctx = TestContext::new().await;
        let nonce = uuid::Uuid::new_v4().to_string();

        let payload = serde_json::json!({
            "action": "register_account",
            "nonce": nonce,
            "publicKey": ctx.public_key,
            "timestamp": ctx.timestamp,
            "username": "ab", // Too short
        });
        let canonical = create_canonical_payload(&payload);
        let signature = sign_payload(&ctx.signing_key, &canonical);

        let req =
            build_register_account_request("ab", ctx.public_key, ctx.timestamp, nonce, signature);

        let result = ctx.service.register_account(req).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid username"));
    }

    #[tokio::test]
    async fn test_get_account_success() {
        let ctx = TestContext::new().await;

        // Register account first
        test_register_account(
            &ctx.service,
            "alice",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Get account
        let result = ctx.service.get_account("alice").await;
        assert!(result.is_ok());

        let account = result.unwrap();
        assert!(account.is_some());

        let account = account.unwrap();
        assert_eq!(account.username, "alice");
        assert_eq!(account.public_keys.len(), 1);
        assert_eq!(account.public_keys[0].public_key, ctx.public_key);
    }

    #[tokio::test]
    async fn test_get_account_not_found() {
        let ctx = TestContext::new().await;

        let result = ctx.service.get_account("nonexistent").await;
        assert!(result.is_ok());
        assert!(result.unwrap().is_none());
    }

    #[tokio::test]
    async fn test_add_public_key_success() {
        let ctx = TestContext::new().await;

        // Register account first
        test_register_account(
            &ctx.service,
            "alice",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Add second key
        let (_, public_key2) = create_test_keypair();
        let add_req = create_add_key_request(
            "alice",
            &public_key2,
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        );

        let result = ctx.service.add_public_key("alice", add_req).await;
        assert!(result.is_ok());

        let key = result.unwrap();
        assert_eq!(key.public_key, public_key2);
        assert!(key.is_active);
        assert!(key.disabled_at.is_none());

        // Verify account now has 2 keys
        let account = ctx.service.get_account("alice").await.unwrap().unwrap();
        assert_eq!(account.public_keys.len(), 2);
    }

    #[tokio::test]
    async fn test_add_public_key_max_keys_exceeded() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "bob",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Add 9 more keys (total 10)
        for _ in 0..9 {
            let (_, new_key) = create_test_keypair();
            let add_req = create_add_key_request(
                "bob",
                &new_key,
                &ctx.signing_key,
                &ctx.public_key,
                ctx.timestamp,
            );
            ctx.service.add_public_key("bob", add_req).await.unwrap();
        }

        // Try to add 11th key (should fail)
        let (_, key11) = create_test_keypair();
        let add_req = create_add_key_request(
            "bob",
            &key11,
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        );

        let result = ctx.service.add_public_key("bob", add_req).await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Maximum number"));
    }

    #[tokio::test]
    async fn test_add_public_key_duplicate_rejected() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "charlie",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Try to add the same key again (should fail)
        let add_req = create_add_key_request(
            "charlie",
            &ctx.public_key,
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        );

        let result = ctx.service.add_public_key("charlie", add_req).await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("already registered"));
    }

    #[tokio::test]
    async fn test_add_public_key_inactive_signing_key() {
        let ctx = TestContext::new().await;

        // Create second keypair
        let (signing_key2, public_key2) = create_test_keypair();

        // Register with first key
        test_register_account(
            &ctx.service,
            "dave",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Add second key
        let add_req = create_add_key_request(
            "dave",
            &public_key2,
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        );
        ctx.service.add_public_key("dave", add_req).await.unwrap();

        // Get key1 ID for removal
        let account = ctx.service.get_account("dave").await.unwrap().unwrap();
        let key1_id = account
            .public_keys
            .iter()
            .find(|k| k.public_key == ctx.public_key)
            .unwrap()
            .id
            .clone();

        // Remove first key (using second key to sign)
        let remove_req =
            create_remove_key_request("dave", &key1_id, &signing_key2, &public_key2, ctx.timestamp);
        ctx.service
            .remove_public_key("dave", &key1_id, remove_req)
            .await
            .unwrap();

        // Now try to add a third key using the removed (inactive) first key
        let (_, public_key3) = create_test_keypair();
        let add_req = create_add_key_request(
            "dave",
            &public_key3,
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        );

        let result = ctx.service.add_public_key("dave", add_req).await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not active"));
    }

    #[tokio::test]
    async fn test_remove_public_key_success() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "eve",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Add second key
        let (_, public_key2) = create_test_keypair();
        let add_req = create_add_key_request(
            "eve",
            &public_key2,
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        );
        ctx.service.add_public_key("eve", add_req).await.unwrap();

        // Get key2 ID
        let account = ctx.service.get_account("eve").await.unwrap().unwrap();
        let key2_id = account
            .public_keys
            .iter()
            .find(|k| k.public_key == public_key2)
            .unwrap()
            .id
            .clone();

        // Remove second key
        let remove_req = create_remove_key_request(
            "eve",
            &key2_id,
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        );

        let result = ctx
            .service
            .remove_public_key("eve", &key2_id, remove_req)
            .await;

        assert!(result.is_ok());

        let removed_key = result.unwrap();
        assert_eq!(removed_key.public_key, public_key2);
        assert!(!removed_key.is_active);
        assert!(removed_key.disabled_at.is_some());
        assert!(removed_key.disabled_by_key_id.is_some());

        // Verify account still has 2 keys, but only 1 active
        let account = ctx.service.get_account("eve").await.unwrap().unwrap();
        assert_eq!(account.public_keys.len(), 2);
        assert_eq!(
            account.public_keys.iter().filter(|k| k.is_active).count(),
            1
        );
    }

    #[tokio::test]
    async fn test_remove_last_active_key_rejected() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "frank",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Get key1 ID
        let account = ctx.service.get_account("frank").await.unwrap().unwrap();
        let key1_id = account.public_keys[0].id.clone();

        // Try to remove the only active key
        let remove_req = create_remove_key_request(
            "frank",
            &key1_id,
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        );

        let result = ctx
            .service
            .remove_public_key("frank", &key1_id, remove_req)
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("last active key"));
    }

    // Admin Operation Tests

    #[tokio::test]
    async fn test_admin_disable_key_success() {
        let ctx = TestContext::new().await;

        // Register account with two keys
        test_register_account(
            &ctx.service,
            "george",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Add second key
        let (_, public_key2) = create_test_keypair();
        let add_req = create_add_key_request(
            "george",
            &public_key2,
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        );
        ctx.service.add_public_key("george", add_req).await.unwrap();

        // Get key2 ID
        let account = ctx.service.get_account("george").await.unwrap().unwrap();
        let key2_id = account
            .public_keys
            .iter()
            .find(|k| k.public_key == public_key2)
            .unwrap()
            .id
            .clone();

        // Admin disables second key
        let result = ctx
            .service
            .admin_disable_key("george", &key2_id, "User reported compromise")
            .await;

        assert!(result.is_ok());
        let disabled_key = result.unwrap();
        assert_eq!(disabled_key.public_key, public_key2);
        assert!(!disabled_key.is_active);
        assert!(disabled_key.disabled_at.is_some());
        assert_eq!(disabled_key.disabled_by_admin, Some(true));

        // Verify account still has 2 keys, but only 1 active
        let account = ctx.service.get_account("george").await.unwrap().unwrap();
        assert_eq!(account.public_keys.len(), 2);
        assert_eq!(
            account.public_keys.iter().filter(|k| k.is_active).count(),
            1
        );
    }

    #[tokio::test]
    async fn test_admin_disable_key_account_not_found() {
        let ctx = TestContext::new().await;

        let result = ctx
            .service
            .admin_disable_key("nonexistent", "some-key-id", "test reason")
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Account not found"));
    }

    #[tokio::test]
    async fn test_admin_disable_key_not_found() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "harry",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Try to disable non-existent key
        let result = ctx
            .service
            .admin_disable_key("harry", "nonexistent-key-id", "test reason")
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Key not found"));
    }

    #[tokio::test]
    async fn test_admin_add_recovery_key_success() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "iris",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Admin adds recovery key
        let (_, recovery_key) = create_test_keypair();
        let result = ctx
            .service
            .admin_add_recovery_key("iris", &recovery_key, "User lost all keys")
            .await;

        assert!(result.is_ok());
        let added_key = result.unwrap();
        assert_eq!(added_key.public_key, recovery_key);
        assert!(added_key.is_active);
        assert_eq!(added_key.added_by_admin, Some(true));
        assert!(added_key.added_at.is_some());

        // Verify account now has 2 keys
        let account = ctx.service.get_account("iris").await.unwrap().unwrap();
        assert_eq!(account.public_keys.len(), 2);
        assert_eq!(
            account.public_keys.iter().filter(|k| k.is_active).count(),
            2
        );
    }

    #[tokio::test]
    async fn test_admin_add_recovery_key_account_not_found() {
        let ctx = TestContext::new().await;

        let (_, recovery_key) = create_test_keypair();
        let result = ctx
            .service
            .admin_add_recovery_key("nonexistent", &recovery_key, "test reason")
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Account not found"));
    }

    #[tokio::test]
    async fn test_admin_add_recovery_key_duplicate_rejected() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "jack",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Try to add existing key as recovery key
        let result = ctx
            .service
            .admin_add_recovery_key("jack", &ctx.public_key, "test reason")
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("already registered"));
    }

    #[tokio::test]
    async fn test_update_profile_success() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "testuser",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Update profile with full request (non-helper to test all fields)
        let nonce = uuid::Uuid::new_v4().to_string();
        let payload = serde_json::json!({
            "action": "update_profile",
            "bio": "New bio",
            "contactEmail": "test@example.com",
            "displayName": "Updated Name",
            "nonce": nonce,
            "signingPublicKey": ctx.public_key,
            "timestamp": ctx.timestamp,
            "username": "testuser",
        });
        let canonical = create_canonical_payload(&payload);
        let signature = sign_payload(&ctx.signing_key, &canonical);

        let update_req = UpdateAccountRequest {
            display_name: Some("Updated Name".to_string()),
            contact_email: Some("test@example.com".to_string()),
            contact_telegram: None,
            contact_twitter: None,
            contact_discord: None,
            website_url: None,
            bio: Some("New bio".to_string()),
            signing_public_key: ctx.public_key,
            timestamp: ctx.timestamp,
            nonce,
            signature,
        };

        let account = ctx
            .service
            .update_profile("testuser", update_req)
            .await
            .unwrap();
        assert_eq!(account.display_name, "Updated Name");
        assert_eq!(account.contact_email, Some("test@example.com".to_string()));
        assert_eq!(account.bio, Some("New bio".to_string()));
    }

    #[tokio::test]
    async fn test_update_profile_partial_update() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "partialuser",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Update only bio (partial update using helper)
        let update_req = create_update_account_request(
            "partialuser",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
            None,
            Some("Only updating bio".to_string()),
        );

        let account = ctx
            .service
            .update_profile("partialuser", update_req)
            .await
            .unwrap();
        assert_eq!(account.display_name, "partialuser-display"); // Original value unchanged
        assert_eq!(account.bio, Some("Only updating bio".to_string()));
    }

    #[tokio::test]
    async fn test_update_profile_invalid_signature() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "baduser",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Try to update with invalid signature
        let mut update_req = create_update_account_request(
            "baduser",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
            Some("Hacked Name".to_string()),
            None,
        );
        update_req.signature = "invalid_signature".to_string(); // Tamper with signature

        let result = ctx.service.update_profile("baduser", update_req).await;
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .contains("Signature verification failed"));
    }

    #[tokio::test]
    async fn test_update_profile_inactive_signing_key() {
        let ctx = TestContext::new().await;

        // Create second keypair
        let (signing_key2, public_key2) = create_test_keypair();

        // Register account with first key
        test_register_account(
            &ctx.service,
            "multikey",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Add second key
        let add_req = create_add_key_request(
            "multikey",
            &public_key2,
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        );
        ctx.service
            .add_public_key("multikey", add_req)
            .await
            .unwrap();

        // Get and remove first key
        let account = ctx.service.get_account("multikey").await.unwrap().unwrap();
        let key1_id = account
            .public_keys
            .iter()
            .find(|k| k.public_key == ctx.public_key)
            .unwrap()
            .id
            .clone();

        let remove_req = create_remove_key_request(
            "multikey",
            &key1_id,
            &signing_key2,
            &public_key2,
            ctx.timestamp,
        );
        ctx.service
            .remove_public_key("multikey", &key1_id, remove_req)
            .await
            .unwrap();

        // Try to update profile with disabled key
        let nonce4 = uuid::Uuid::new_v4().to_string();
        let payload4 = serde_json::json!({
            "action": "update_profile",
            "bio": "Trying with inactive key",
            "nonce": nonce4,
            "signingPublicKey": ctx.public_key,
            "timestamp": ctx.timestamp,
            "username": "multikey",
        });
        let canonical4 = create_canonical_payload(&payload4);
        let signature4 = sign_payload(&ctx.signing_key, &canonical4);

        let update_req = UpdateAccountRequest {
            display_name: None,
            contact_email: None,
            contact_telegram: None,
            contact_twitter: None,
            contact_discord: None,
            website_url: None,
            bio: Some("Trying with inactive key".to_string()),
            signing_public_key: ctx.public_key,
            timestamp: ctx.timestamp,
            nonce: nonce4,
            signature: signature4,
        };

        let result = ctx.service.update_profile("multikey", update_req).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not active"));
    }

    #[tokio::test]
    async fn test_update_profile_account_not_found() {
        let ctx = TestContext::new().await;

        // Try to update nonexistent account
        let update_req = create_update_account_request(
            "nonexistent",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
            None,
            Some("Test".to_string()),
        );

        let result = ctx.service.update_profile("nonexistent", update_req).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Account not found"));
    }

    #[tokio::test]
    async fn test_update_profile_replay_attack() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "replay",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // First update
        let update_req1 = create_update_account_request(
            "replay",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
            None,
            Some("First update".to_string()),
        );
        let nonce = update_req1.nonce.clone();
        let signature = update_req1.signature.clone();

        assert!(ctx
            .service
            .update_profile("replay", update_req1)
            .await
            .is_ok());

        // Try to replay the same request (same nonce and signature)
        let mut update_req2 = create_update_account_request(
            "replay",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
            None,
            Some("Replay attempt".to_string()),
        );
        update_req2.nonce = nonce; // Use same nonce
        update_req2.signature = signature; // Use same signature

        let result = ctx.service.update_profile("replay", update_req2).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("replay attack"));
    }

    #[tokio::test]
    async fn test_admin_add_recovery_key_max_keys_exceeded() {
        let ctx = TestContext::new().await;

        // Register account
        test_register_account(
            &ctx.service,
            "kate",
            &ctx.signing_key,
            &ctx.public_key,
            ctx.timestamp,
        )
        .await;

        // Add 9 more keys (total 10)
        for _ in 0..9 {
            let (_, new_key) = create_test_keypair();
            let add_req = create_add_key_request(
                "kate",
                &new_key,
                &ctx.signing_key,
                &ctx.public_key,
                ctx.timestamp,
            );
            ctx.service.add_public_key("kate", add_req).await.unwrap();
        }

        // Try to add 11th key via admin (should fail)
        let (_, key11) = create_test_keypair();
        let result = ctx
            .service
            .admin_add_recovery_key("kate", &key11, "test reason")
            .await;

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Maximum number"));
    }
}
