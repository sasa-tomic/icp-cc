//! Passkey authentication service (WebAuthn + vault + recovery)
//! Passkey backend is scaffolded but not yet wired into API routes.
#![allow(dead_code)]

use crate::repositories::PasskeyRepository;
use crate::services::error::PasskeyError;
use crate::vault::{generate_recovery_codes, hash_recovery_code, verify_recovery_code};
use chrono::{Duration, Utc};
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;
use std::sync::Arc;
use webauthn_rs::prelude::*;
use webauthn_rs_proto::{
    PublicKeyCredentialCreationOptions, PublicKeyCredentialRequestOptions,
};

const CHALLENGE_EXPIRY_MINUTES: i64 = 5;

// ============================================================================
// Request/Response types
// ============================================================================

#[derive(Debug, Serialize)]
pub struct PasskeyRegistrationStart {
    pub challenge_id: String,
    /// Flat WebAuthn options, matching the Dart `passkeys` package's
    /// `RegisterRequestType.fromJson` shape. The `webauthn-rs-proto`
    /// `CreationChallengeResponse` wraps the same inner type under a
    /// `public_key` field; we unwrap here because the frontend
    /// (PasskeyService.registerPasskey → NativePasskeyAuthenticator.register
    /// → RegisterRequestType.fromJson) expects `rp`, `user`, `challenge`,
    /// … at the top level, NOT under `publicKey`. See WEB-1-PASSKEY-SHAPE
    /// in docs/OPEN_ISSUES.md for the full investigation.
    pub options: PublicKeyCredentialCreationOptions,
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
    /// Flat WebAuthn options, matching the Dart `passkeys` package's
    /// `AuthenticateRequestType.fromJson` shape. See
    /// `PasskeyRegistrationStart.options` doc for the shape rationale.
    pub options: PublicKeyCredentialRequestOptions,
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
    pub fn new(pool: SqlitePool, rp_id: &str, rp_origin: &str) -> Result<Self, PasskeyError> {
        let rp_origin = Url::parse(rp_origin)
            .map_err(|e| PasskeyError::Internal(format!("Invalid RP origin URL: {e}")))?;

        let builder = WebauthnBuilder::new(rp_id, &rp_origin)
            .map_err(|e| PasskeyError::Internal(format!("WebAuthn builder error: {e}")))?
            .rp_name("ICP Script Marketplace");

        let webauthn = Arc::new(
            builder
                .build()
                .map_err(|e| PasskeyError::Internal(format!("WebAuthn build error: {e}")))?,
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

    /// Best-effort cleanup of a single-use WebAuthn challenge. The challenge
    /// is already consumed (registration/authentication succeeded OR was
    /// determined expired/invalid); a delete failure here is suspicious but
    /// NOT fatal — the row expires within `CHALLENGE_EXPIRY_MINUTES`
    /// regardless, and the periodic sweep reaps any stragglers. We LOG the
    /// failure loudly (W7-12) instead of silently swallowing it with `.ok()`
    /// so a persistent delete fault (e.g. DB pressure) is visible in logs.
    async fn consume_challenge(&self, challenge_id: &str) {
        if let Err(e) = self.repo.delete_challenge(challenge_id).await {
            tracing::warn!(
                challenge_id,
                "Failed to delete consumed WebAuthn challenge (best-effort cleanup); \
                 it will expire via the background sweep, but the failure is unexpected: {e}"
            );
        }
    }

    /// Start passkey registration for an account
    pub async fn start_registration(
        &self,
        account_id: &str,
        username: &str,
    ) -> Result<PasskeyRegistrationStart, PasskeyError> {
        // Get existing passkeys to exclude from registration
        let existing = self
            .repo
            .list_passkeys_by_account(account_id)
            .await
            .map_err(|e| PasskeyError::BadRequest(format!("DB error: {e}")))?;

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
            .map_err(|e| PasskeyError::BadRequest(format!("WebAuthn error: {e}")))?;

        // Store challenge state
        let challenge_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now();
        let expires_at = now + Duration::minutes(CHALLENGE_EXPIRY_MINUTES);

        // Serialize registration state
        let state_bytes = serde_json::to_vec(&reg_state)
            .map_err(|e| PasskeyError::BadRequest(format!("Serialize error: {e}")))?;

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
            .map_err(|e| PasskeyError::BadRequest(format!("DB error: {e}")))?;

        Ok(PasskeyRegistrationStart {
            challenge_id,
            // Flatten `CreationChallengeResponse.public_key` into the response
            // — see `PasskeyRegistrationStart.options` doc + WEB-1-PASSKEY-SHAPE.
            options: ccr.public_key,
        })
    }

    /// Complete passkey registration
    pub async fn finish_registration(
        &self,
        req: PasskeyRegistrationFinish,
    ) -> Result<PasskeyInfo, PasskeyError> {
        // Retrieve and validate challenge
        let challenge = self
            .repo
            .find_challenge(&req.challenge_id)
            .await
            .map_err(|e| PasskeyError::BadRequest(format!("DB error: {e}")))?
            .ok_or_else(|| {
                PasskeyError::BadRequest("Challenge not found or expired".to_string())
            })?;

        if challenge.challenge_type != "registration" {
            return Err(PasskeyError::BadRequest(
                "Invalid challenge type".to_string(),
            ));
        }

        let account_id = challenge.account_id.ok_or_else(|| {
            PasskeyError::BadRequest("Missing account_id in challenge".to_string())
        })?;

        // Check expiry
        let expires_at = chrono::DateTime::parse_from_rfc3339(&challenge.expires_at)
            .map_err(|e| PasskeyError::BadRequest(format!("Invalid expires_at: {e}")))?;
        if Utc::now() > expires_at {
            self.consume_challenge(&req.challenge_id).await;
            return Err(PasskeyError::BadRequest("Challenge expired".to_string()));
        }

        // Deserialize registration state
        let reg_state: PasskeyRegistration = serde_json::from_slice(&challenge.challenge)
            .map_err(|e| PasskeyError::BadRequest(format!("Deserialize error: {e}")))?;

        // Verify the credential
        let passkey = self
            .webauthn
            .finish_passkey_registration(&req.credential, &reg_state)
            .map_err(|e| PasskeyError::BadRequest(format!("WebAuthn verification failed: {e}")))?;

        // Store the passkey
        let passkey_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();
        let cred_id = passkey.cred_id().to_vec();
        let public_key = serde_json::to_vec(&passkey)
            .map_err(|e| PasskeyError::BadRequest(format!("Serialize error: {e}")))?;

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
            .map_err(|e| PasskeyError::BadRequest(format!("DB error: {e}")))?;

        // Clean up challenge
        self.consume_challenge(&req.challenge_id).await;

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
    ) -> Result<PasskeyAuthenticationStart, PasskeyError> {
        // Get existing passkeys
        let passkeys = self
            .repo
            .list_passkeys_by_account(account_id)
            .await
            .map_err(|e| PasskeyError::BadRequest(format!("DB error: {e}")))?;

        if passkeys.is_empty() {
            return Err(PasskeyError::BadRequest(
                "No passkeys registered for this account".to_string(),
            ));
        }

        // Deserialize passkeys for WebAuthn
        let allow_credentials: Vec<Passkey> = passkeys
            .iter()
            .filter_map(|p| serde_json::from_slice(&p.public_key).ok())
            .collect();

        if allow_credentials.is_empty() {
            return Err(PasskeyError::BadRequest(
                "No valid passkeys found".to_string(),
            ));
        }

        let (rcr, auth_state) = self
            .webauthn
            .start_passkey_authentication(&allow_credentials)
            .map_err(|e| PasskeyError::BadRequest(format!("WebAuthn error: {e}")))?;

        // Store challenge state
        let challenge_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now();
        let expires_at = now + Duration::minutes(CHALLENGE_EXPIRY_MINUTES);

        let state_bytes = serde_json::to_vec(&auth_state)
            .map_err(|e| PasskeyError::BadRequest(format!("Serialize error: {e}")))?;

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
            .map_err(|e| PasskeyError::BadRequest(format!("DB error: {e}")))?;

        Ok(PasskeyAuthenticationStart {
            challenge_id,
            // Flatten `RequestChallengeResponse.public_key` into the response
            // — see `PasskeyRegistrationStart.options` doc + WEB-1-PASSKEY-SHAPE.
            options: rcr.public_key,
        })
    }

    /// Complete passkey authentication
    pub async fn finish_authentication(
        &self,
        req: PasskeyAuthenticationFinish,
    ) -> Result<String, PasskeyError> {
        // Retrieve and validate challenge
        let challenge = self
            .repo
            .find_challenge(&req.challenge_id)
            .await
            .map_err(|e| PasskeyError::Unauthorized(format!("DB error: {e}")))?
            .ok_or_else(|| {
                PasskeyError::Unauthorized("Challenge not found or expired".to_string())
            })?;

        if challenge.challenge_type != "authentication" {
            return Err(PasskeyError::Unauthorized(
                "Invalid challenge type".to_string(),
            ));
        }

        let account_id = challenge.account_id.ok_or_else(|| {
            PasskeyError::Unauthorized("Missing account_id in challenge".to_string())
        })?;

        // Check expiry
        let expires_at = chrono::DateTime::parse_from_rfc3339(&challenge.expires_at)
            .map_err(|e| PasskeyError::Unauthorized(format!("Invalid expires_at: {e}")))?;
        if Utc::now() > expires_at {
            self.consume_challenge(&req.challenge_id).await;
            return Err(PasskeyError::Unauthorized("Challenge expired".to_string()));
        }

        // Deserialize auth state
        let auth_state: PasskeyAuthentication = serde_json::from_slice(&challenge.challenge)
            .map_err(|e| PasskeyError::Unauthorized(format!("Deserialize error: {e}")))?;

        // Verify the credential
        let auth_result = self
            .webauthn
            .finish_passkey_authentication(&req.credential, &auth_state)
            .map_err(|e| {
                PasskeyError::Unauthorized(format!("WebAuthn verification failed: {e}"))
            })?;

        // Update counter for the used passkey.
        //
        // NOTE: look up by `raw_id` (the raw credential-id bytes the authenticator
        // produced and the server stored), NOT `id` (the base64url *string* of
        // that id). `id.as_ref()` previously resolved to the UTF-8 bytes of the
        // base64url string via `String: AsRef<[u8]>`, so the lookup always
        // missed and the counter/last_used_at were silently never advanced.
        // (Surfaced by the W6-13 real-crypto auth round-trip test.)
        let cred_id = req.credential.get_credential_id();
        if let Some(passkey_row) = self
            .repo
            .find_passkey_by_credential_id(cred_id)
            .await
            .map_err(|e| PasskeyError::Unauthorized(format!("DB error: {e}")))?
        {
            let now = Utc::now().to_rfc3339();
            self.repo
                .update_passkey_counter(&passkey_row.id, auth_result.counter() as i64, &now)
                .await
                .map_err(|e| PasskeyError::Unauthorized(format!("DB error: {e}")))?;

            // Re-serialise the Passkey blob so the monotonic counter (and backup
            // flags) advance in persistent storage. Without this,
            // `start_authentication` always deserialises the stale blob and
            // webauthn-rs's in-blob counter-replay protection never fires — a
            // captured assertion could be replayed indefinitely. `update_credential`
            // returns `Some(true)` only when the counter/flags actually changed.
            if let Ok(mut stored_passkey) =
                serde_json::from_slice::<Passkey>(&passkey_row.public_key)
            {
                if stored_passkey.update_credential(&auth_result) == Some(true) {
                    let updated_blob = serde_json::to_vec(&stored_passkey)
                        .map_err(|e| PasskeyError::Internal(format!("Serialize error: {e}")))?;
                    self.repo
                        .update_passkey_public_key(&passkey_row.id, &updated_blob)
                        .await
                        .map_err(|e| PasskeyError::Unauthorized(format!("DB error: {e}")))?;
                }
            }
        }

        // Clean up challenge
        self.consume_challenge(&req.challenge_id).await;

        Ok(account_id)
    }

    // ========================================================================
    // Passkey Management
    // ========================================================================

    pub async fn list_passkeys(&self, account_id: &str) -> Result<Vec<PasskeyInfo>, PasskeyError> {
        let passkeys = self
            .repo
            .list_passkeys_by_account(account_id)
            .await
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?;

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

    pub async fn delete_passkey(
        &self,
        passkey_id: &str,
        account_id: &str,
    ) -> Result<(), PasskeyError> {
        // Ensure at least one passkey remains
        let count = self
            .repo
            .list_passkeys_by_account(account_id)
            .await
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?
            .len();

        if count <= 1 {
            return Err(PasskeyError::BadRequest(
                "Cannot delete last passkey".to_string(),
            ));
        }

        let deleted = self
            .repo
            .delete_passkey(passkey_id, account_id)
            .await
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?;

        if !deleted {
            return Err(PasskeyError::NotFound("Passkey not found".to_string()));
        }

        Ok(())
    }

    // ========================================================================
    // Recovery Codes
    // ========================================================================

    pub async fn generate_recovery_codes_for_account(
        &self,
        account_id: &str,
    ) -> Result<RecoveryCodesResponse, PasskeyError> {
        // Delete existing codes
        self.repo
            .delete_recovery_codes(account_id)
            .await
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?;

        // Generate new codes
        let codes = generate_recovery_codes();
        let now = Utc::now().to_rfc3339();

        // Hash codes for storage. Argon2id is fallible (param / memory pressure),
        // so propagate as a typed Internal error instead of panicking the
        // request handler (W7-13). Matches the `verify_recovery_code` mapping
        // a few lines below.
        let code_hashes = codes
            .iter()
            .map(|code| -> Result<(String, String), PasskeyError> {
                let id = uuid::Uuid::new_v4().to_string();
                let hash = hash_recovery_code(code).map_err(PasskeyError::Internal)?;
                Ok((id, hash))
            })
            .collect::<Result<Vec<_>, _>>()?;

        self.repo
            .create_recovery_codes(account_id, &code_hashes, &now)
            .await
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?;

        Ok(RecoveryCodesResponse {
            codes,
            remaining_unused: 12,
        })
    }

    pub async fn verify_recovery_code_for_account(
        &self,
        account_id: &str,
        code: &str,
    ) -> Result<bool, PasskeyError> {
        let stored_codes = self
            .repo
            .list_recovery_codes(account_id)
            .await
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?;

        for stored in stored_codes {
            if stored.used {
                continue;
            }
            if verify_recovery_code(code, &stored.code_hash).map_err(PasskeyError::Internal)? {
                // Mark as used
                let now = Utc::now().to_rfc3339();
                self.repo
                    .mark_recovery_code_used(&stored.id, &now)
                    .await
                    .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?;
                return Ok(true);
            }
        }

        Ok(false)
    }

    pub async fn get_recovery_code_status(&self, account_id: &str) -> Result<usize, PasskeyError> {
        let codes = self
            .repo
            .list_recovery_codes(account_id)
            .await
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?;

        Ok(codes.iter().filter(|c| !c.used).count())
    }

    // ========================================================================
    // Vault Operations
    // ========================================================================
    //
    // A-4 (zero-knowledge vault): the backend is a PURE OPAQUE-BLOB STORE.
    // The client encrypts locally (Argon2id + AES-256-GCM via FFI) and POSTs
    // the resulting bytes; these methods persist/return those bytes verbatim.
    // The password and plaintext NEVER transit the server. See the wire
    // contract documented on `VaultBlobRequest` in `main.rs`.

    /// Stores a client-encrypted vault blob for `account_id`.
    ///
    /// `encrypted_data` / `salt` / `nonce` are the opaque bytes produced by
    /// the client; the server stores them without inspection. Fails if a vault
    /// already exists for this account.
    pub async fn create_vault(
        &self,
        account_id: &str,
        encrypted_data: &[u8],
        salt: &[u8],
        nonce: &[u8],
    ) -> Result<(), PasskeyError> {
        // Check if vault already exists
        if self
            .repo
            .find_vault(account_id)
            .await
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?
            .is_some()
        {
            return Err(PasskeyError::Conflict("Vault already exists".to_string()));
        }

        let vault_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();

        self.repo
            .create_vault(&vault_id, account_id, encrypted_data, salt, nonce, &now)
            .await
            // TD-2: DB write failures are server errors (were 400 under the
            // old fixed-status handler — a DB fault is not a client problem).
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?;

        Ok(())
    }

    /// Returns the stored opaque vault blob for `account_id` (if any), with
    /// each component base64-encoded for the JSON wire response. The bytes are
    /// returned exactly as the client previously stored them — the server
    /// cannot decrypt them.
    pub async fn get_vault(&self, account_id: &str) -> Result<Option<VaultData>, PasskeyError> {
        let vault = self
            .repo
            .find_vault(account_id)
            .await
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?;

        Ok(vault.map(|v| VaultData {
            encrypted_data: base64::Engine::encode(
                &base64::engine::general_purpose::STANDARD,
                &v.encrypted_data,
            ),
            salt: base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &v.salt),
            nonce: base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &v.nonce),
        }))
    }

    /// Overwrites the stored opaque vault blob for `account_id` with a new
    /// client-produced blob. Fails if no vault exists for this account.
    pub async fn update_vault(
        &self,
        account_id: &str,
        encrypted_data: &[u8],
        salt: &[u8],
        nonce: &[u8],
    ) -> Result<(), PasskeyError> {
        let now = Utc::now().to_rfc3339();

        let updated = self
            .repo
            .update_vault(account_id, encrypted_data, salt, nonce, &now)
            .await
            // TD-2: DB write failures are server errors (were 400 under the
            // old `.contains("not found") → else → 400` heuristic; a DB fault
            // is not a client problem).
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))?;

        if !updated {
            return Err(PasskeyError::NotFound("Vault not found".to_string()));
        }

        Ok(())
    }

    /// Cleanup expired challenges (should be called periodically)
    pub async fn cleanup_expired_challenges(&self) -> Result<u64, PasskeyError> {
        self.repo
            .cleanup_expired_challenges()
            .await
            .map_err(|e| PasskeyError::Internal(format!("DB error: {e}")))
    }
}
