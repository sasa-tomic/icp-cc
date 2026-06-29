//! Passkey authentication service (WebAuthn + vault + recovery)

use crate::repositories::PasskeyRepository;
use crate::vault::{
    encrypt_vault as vault_encrypt, generate_recovery_codes, hash_recovery_code,
    verify_recovery_code,
};
use chrono::{Duration, Utc};
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;
use std::sync::Arc;
use webauthn_rs::prelude::*;

const CHALLENGE_EXPIRY_MINUTES: i64 = 5;

// ============================================================================
// Request/Response types
// ============================================================================

#[derive(Debug, Serialize)]
pub struct PasskeyRegistrationStart {
    pub challenge_id: String,
    pub options: CreationChallengeResponse,
}

#[derive(Debug, Deserialize)]
pub struct PasskeyRegistrationFinish {
    pub challenge_id: String,
    pub credential: RegisterPublicKeyCredential,
    pub device_name: Option<String>,
    pub device_type: Option<String>, // "platform" or "cross-platform"
}

#[derive(Debug, Serialize)]
pub struct PasskeyAuthenticationStart {
    pub challenge_id: String,
    pub options: RequestChallengeResponse,
}

#[derive(Debug, Deserialize)]
pub struct PasskeyAuthenticationFinish {
    pub challenge_id: String,
    pub credential: PublicKeyCredential,
}

#[derive(Debug, Serialize)]
pub struct PasskeyInfo {
    pub id: String,
    pub device_name: Option<String>,
    pub device_type: Option<String>,
    pub created_at: String,
    pub last_used_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct RecoveryCodesResponse {
    pub codes: Vec<String>,
    pub remaining_unused: usize,
}

#[derive(Debug, Serialize)]
pub struct VaultData {
    pub encrypted_data: String, // base64
    pub salt: String,           // base64
    pub nonce: String,          // base64
}

// ============================================================================
// Service
// ============================================================================

pub struct PasskeyService {
    repo: PasskeyRepository,
    webauthn: Arc<Webauthn>,
    pool: SqlitePool,
}

impl PasskeyService {
    pub fn new(pool: SqlitePool, rp_id: &str, rp_origin: &str) -> Result<Self, String> {
        let rp_origin =
            Url::parse(rp_origin).map_err(|e| format!("Invalid RP origin URL: {}", e))?;

        let builder = WebauthnBuilder::new(rp_id, &rp_origin)
            .map_err(|e| format!("WebAuthn builder error: {}", e))?
            .rp_name("ICP Script Marketplace");

        let webauthn = Arc::new(
            builder
                .build()
                .map_err(|e| format!("WebAuthn build error: {}", e))?,
        );

        Ok(Self {
            repo: PasskeyRepository::new(pool.clone()),
            webauthn,
            pool,
        })
    }

    // ========================================================================
    // Passkey Registration
    // ========================================================================

    /// Start passkey registration for an account
    pub async fn start_registration(
        &self,
        account_id: &str,
        username: &str,
    ) -> Result<PasskeyRegistrationStart, String> {
        // Get existing passkeys to exclude from registration
        let existing = self
            .repo
            .list_passkeys_by_account(account_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        let exclude_credentials: Vec<CredentialID> = existing
            .iter()
            .map(|p| CredentialID::from(p.credential_id.clone()))
            .collect();

        let (ccr, reg_state) = self
            .webauthn
            .start_passkey_registration(
                Uuid::new_v4(),
                username,
                username,
                Some(exclude_credentials),
            )
            .map_err(|e| format!("WebAuthn error: {}", e))?;

        // Store challenge state
        let challenge_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now();
        let expires_at = now + Duration::minutes(CHALLENGE_EXPIRY_MINUTES);

        // Serialize registration state
        let state_bytes =
            serde_json::to_vec(&reg_state).map_err(|e| format!("Serialize error: {}", e))?;

        self.repo
            .store_challenge(
                &challenge_id,
                Some(account_id),
                &state_bytes,
                "registration",
                &expires_at.to_rfc3339(),
                &now.to_rfc3339(),
            )
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        Ok(PasskeyRegistrationStart {
            challenge_id,
            options: ccr,
        })
    }

    /// Complete passkey registration
    pub async fn finish_registration(
        &self,
        req: PasskeyRegistrationFinish,
    ) -> Result<PasskeyInfo, String> {
        // Retrieve and validate challenge
        let challenge = self
            .repo
            .find_challenge(&req.challenge_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?
            .ok_or("Challenge not found or expired")?;

        if challenge.challenge_type != "registration" {
            return Err("Invalid challenge type".to_string());
        }

        let account_id = challenge
            .account_id
            .ok_or("Missing account_id in challenge")?;

        // Check expiry
        let expires_at = chrono::DateTime::parse_from_rfc3339(&challenge.expires_at)
            .map_err(|e| format!("Invalid expires_at: {}", e))?;
        if Utc::now() > expires_at {
            self.repo.delete_challenge(&req.challenge_id).await.ok();
            return Err("Challenge expired".to_string());
        }

        // Deserialize registration state
        let reg_state: PasskeyRegistration = serde_json::from_slice(&challenge.challenge)
            .map_err(|e| format!("Deserialize error: {}", e))?;

        // Verify the credential
        let passkey = self
            .webauthn
            .finish_passkey_registration(&req.credential, &reg_state)
            .map_err(|e| format!("WebAuthn verification failed: {}", e))?;

        // Store the passkey
        let passkey_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();
        let cred_id = passkey.cred_id().to_vec();
        let public_key =
            serde_json::to_vec(&passkey).map_err(|e| format!("Serialize error: {}", e))?;

        self.repo
            .create_passkey(
                &passkey_id,
                &account_id,
                &cred_id,
                &public_key,
                req.device_name.as_deref(),
                req.device_type.as_deref(),
                &now,
            )
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        // Clean up challenge
        self.repo.delete_challenge(&req.challenge_id).await.ok();

        Ok(PasskeyInfo {
            id: passkey_id,
            device_name: req.device_name,
            device_type: req.device_type,
            created_at: now,
            last_used_at: None,
        })
    }

    // ========================================================================
    // Passkey Authentication
    // ========================================================================

    /// Start passkey authentication for an account
    pub async fn start_authentication(
        &self,
        account_id: &str,
    ) -> Result<PasskeyAuthenticationStart, String> {
        // Get existing passkeys
        let passkeys = self
            .repo
            .list_passkeys_by_account(account_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        if passkeys.is_empty() {
            return Err("No passkeys registered for this account".to_string());
        }

        // Deserialize passkeys for WebAuthn
        let allow_credentials: Vec<Passkey> = passkeys
            .iter()
            .filter_map(|p| serde_json::from_slice(&p.public_key).ok())
            .collect();

        if allow_credentials.is_empty() {
            return Err("No valid passkeys found".to_string());
        }

        let (rcr, auth_state) = self
            .webauthn
            .start_passkey_authentication(&allow_credentials)
            .map_err(|e| format!("WebAuthn error: {}", e))?;

        // Store challenge state
        let challenge_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now();
        let expires_at = now + Duration::minutes(CHALLENGE_EXPIRY_MINUTES);

        let state_bytes =
            serde_json::to_vec(&auth_state).map_err(|e| format!("Serialize error: {}", e))?;

        self.repo
            .store_challenge(
                &challenge_id,
                Some(account_id),
                &state_bytes,
                "authentication",
                &expires_at.to_rfc3339(),
                &now.to_rfc3339(),
            )
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        Ok(PasskeyAuthenticationStart {
            challenge_id,
            options: rcr,
        })
    }

    /// Complete passkey authentication
    pub async fn finish_authentication(
        &self,
        req: PasskeyAuthenticationFinish,
    ) -> Result<String, String> {
        // Retrieve and validate challenge
        let challenge = self
            .repo
            .find_challenge(&req.challenge_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?
            .ok_or("Challenge not found or expired")?;

        if challenge.challenge_type != "authentication" {
            return Err("Invalid challenge type".to_string());
        }

        let account_id = challenge
            .account_id
            .ok_or("Missing account_id in challenge")?;

        // Check expiry
        let expires_at = chrono::DateTime::parse_from_rfc3339(&challenge.expires_at)
            .map_err(|e| format!("Invalid expires_at: {}", e))?;
        if Utc::now() > expires_at {
            self.repo.delete_challenge(&req.challenge_id).await.ok();
            return Err("Challenge expired".to_string());
        }

        // Deserialize auth state
        let auth_state: PasskeyAuthentication = serde_json::from_slice(&challenge.challenge)
            .map_err(|e| format!("Deserialize error: {}", e))?;

        // Verify the credential
        let auth_result = self
            .webauthn
            .finish_passkey_authentication(&req.credential, &auth_state)
            .map_err(|e| format!("WebAuthn verification failed: {}", e))?;

        // Update counter for the used passkey
        let cred_id = req.credential.id.as_ref();
        if let Some(passkey) = self
            .repo
            .find_passkey_by_credential_id(cred_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?
        {
            let now = Utc::now().to_rfc3339();
            self.repo
                .update_passkey_counter(&passkey.id, auth_result.counter() as i64, &now)
                .await
                .map_err(|e| format!("DB error: {}", e))?;
        }

        // Clean up challenge
        self.repo.delete_challenge(&req.challenge_id).await.ok();

        Ok(account_id)
    }

    // ========================================================================
    // Passkey Management
    // ========================================================================

    pub async fn list_passkeys(&self, account_id: &str) -> Result<Vec<PasskeyInfo>, String> {
        let passkeys = self
            .repo
            .list_passkeys_by_account(account_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        Ok(passkeys
            .into_iter()
            .map(|p| PasskeyInfo {
                id: p.id,
                device_name: p.device_name,
                device_type: p.device_type,
                created_at: p.created_at,
                last_used_at: p.last_used_at,
            })
            .collect())
    }

    pub async fn delete_passkey(&self, passkey_id: &str, account_id: &str) -> Result<(), String> {
        // Ensure at least one passkey remains
        let count = self
            .repo
            .list_passkeys_by_account(account_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?
            .len();

        if count <= 1 {
            return Err("Cannot delete last passkey".to_string());
        }

        let deleted = self
            .repo
            .delete_passkey(passkey_id, account_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        if !deleted {
            return Err("Passkey not found".to_string());
        }

        Ok(())
    }

    // ========================================================================
    // Recovery Codes
    // ========================================================================

    pub async fn generate_recovery_codes_for_account(
        &self,
        account_id: &str,
    ) -> Result<RecoveryCodesResponse, String> {
        // Delete existing codes
        self.repo
            .delete_recovery_codes(account_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        // Generate new codes
        let codes = generate_recovery_codes();
        let now = Utc::now().to_rfc3339();

        // Hash codes for storage
        let code_hashes: Vec<(String, String)> = codes
            .iter()
            .map(|code| {
                let id = uuid::Uuid::new_v4().to_string();
                let hash = hash_recovery_code(code).expect("hash should succeed");
                (id, hash)
            })
            .collect();

        self.repo
            .create_recovery_codes(account_id, &code_hashes, &now)
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        Ok(RecoveryCodesResponse {
            codes,
            remaining_unused: 12,
        })
    }

    pub async fn verify_recovery_code_for_account(
        &self,
        account_id: &str,
        code: &str,
    ) -> Result<bool, String> {
        let stored_codes = self
            .repo
            .list_recovery_codes(account_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        for stored in stored_codes {
            if stored.used {
                continue;
            }
            if verify_recovery_code(code, &stored.code_hash)? {
                // Mark as used
                let now = Utc::now().to_rfc3339();
                self.repo
                    .mark_recovery_code_used(&stored.id, &now)
                    .await
                    .map_err(|e| format!("DB error: {}", e))?;
                return Ok(true);
            }
        }

        Ok(false)
    }

    pub async fn get_recovery_code_status(&self, account_id: &str) -> Result<usize, String> {
        let codes = self
            .repo
            .list_recovery_codes(account_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        Ok(codes.iter().filter(|c| !c.used).count())
    }

    // ========================================================================
    // Vault Operations
    // ========================================================================

    pub async fn create_vault(
        &self,
        account_id: &str,
        password: &str,
        data: &[u8],
    ) -> Result<(), String> {
        // Check if vault already exists
        if self
            .repo
            .find_vault(account_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?
            .is_some()
        {
            return Err("Vault already exists".to_string());
        }

        let encrypted = vault_encrypt(password, data)?;
        let vault_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();

        self.repo
            .create_vault(
                &vault_id,
                account_id,
                &encrypted.encrypted_data,
                &encrypted.salt,
                &encrypted.nonce,
                &now,
            )
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        Ok(())
    }

    pub async fn get_vault(&self, account_id: &str) -> Result<Option<VaultData>, String> {
        let vault = self
            .repo
            .find_vault(account_id)
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        Ok(vault.map(|v| VaultData {
            encrypted_data: base64::Engine::encode(
                &base64::engine::general_purpose::STANDARD,
                &v.encrypted_data,
            ),
            salt: base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &v.salt),
            nonce: base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &v.nonce),
        }))
    }

    pub async fn update_vault(
        &self,
        account_id: &str,
        password: &str,
        data: &[u8],
    ) -> Result<(), String> {
        let encrypted = vault_encrypt(password, data)?;
        let now = Utc::now().to_rfc3339();

        let updated = self
            .repo
            .update_vault(
                account_id,
                &encrypted.encrypted_data,
                &encrypted.salt,
                &encrypted.nonce,
                &now,
            )
            .await
            .map_err(|e| format!("DB error: {}", e))?;

        if !updated {
            return Err("Vault not found".to_string());
        }

        Ok(())
    }

    /// Cleanup expired challenges (should be called periodically)
    pub async fn cleanup_expired_challenges(&self) -> Result<u64, String> {
        self.repo
            .cleanup_expired_challenges()
            .await
            .map_err(|e| format!("DB error: {}", e))
    }
}
