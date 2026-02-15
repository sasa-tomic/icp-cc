//! Repository for passkey-related database operations

use sqlx::SqlitePool;

pub struct PasskeyRepository {
    pool: SqlitePool,
}

#[derive(Debug, sqlx::FromRow)]
pub struct PasskeyRow {
    pub id: String,
    pub account_id: String,
    pub credential_id: Vec<u8>,
    pub public_key: Vec<u8>,
    pub counter: i64,
    pub device_name: Option<String>,
    pub device_type: Option<String>,
    pub created_at: String,
    pub last_used_at: Option<String>,
}

#[derive(Debug, sqlx::FromRow)]
pub struct RecoveryCodeRow {
    pub id: String,
    pub account_id: String,
    pub code_hash: String,
    pub used: bool,
    pub used_at: Option<String>,
    pub created_at: String,
}

#[derive(Debug, sqlx::FromRow)]
pub struct VaultRow {
    pub id: String,
    pub account_id: String,
    pub encrypted_data: Vec<u8>,
    pub salt: Vec<u8>,
    pub nonce: Vec<u8>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, sqlx::FromRow)]
pub struct ChallengeRow {
    pub id: String,
    pub account_id: Option<String>,
    pub challenge: Vec<u8>,
    pub challenge_type: String,
    pub expires_at: String,
    pub created_at: String,
}

impl PasskeyRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    // ========================================================================
    // Passkey CRUD
    // ========================================================================

    pub async fn create_passkey(
        &self,
        id: &str,
        account_id: &str,
        credential_id: &[u8],
        public_key: &[u8],
        device_name: Option<&str>,
        device_type: Option<&str>,
        now: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"INSERT INTO passkeys (id, account_id, credential_id, public_key, counter, device_name, device_type, created_at)
               VALUES (?, ?, ?, ?, 0, ?, ?, ?)"#,
        )
        .bind(id)
        .bind(account_id)
        .bind(credential_id)
        .bind(public_key)
        .bind(device_name)
        .bind(device_type)
        .bind(now)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn find_passkey_by_credential_id(&self, credential_id: &[u8]) -> Result<Option<PasskeyRow>, sqlx::Error> {
        sqlx::query_as::<_, PasskeyRow>("SELECT * FROM passkeys WHERE credential_id = ?")
            .bind(credential_id)
            .fetch_optional(&self.pool)
            .await
    }

    pub async fn list_passkeys_by_account(&self, account_id: &str) -> Result<Vec<PasskeyRow>, sqlx::Error> {
        sqlx::query_as::<_, PasskeyRow>("SELECT * FROM passkeys WHERE account_id = ? ORDER BY created_at DESC")
            .bind(account_id)
            .fetch_all(&self.pool)
            .await
    }

    pub async fn update_passkey_counter(&self, id: &str, counter: i64, now: &str) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE passkeys SET counter = ?, last_used_at = ? WHERE id = ?")
            .bind(counter)
            .bind(now)
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn delete_passkey(&self, id: &str, account_id: &str) -> Result<bool, sqlx::Error> {
        let result = sqlx::query("DELETE FROM passkeys WHERE id = ? AND account_id = ?")
            .bind(id)
            .bind(account_id)
            .execute(&self.pool)
            .await?;
        Ok(result.rows_affected() > 0)
    }

    // ========================================================================
    // WebAuthn Challenges
    // ========================================================================

    pub async fn store_challenge(
        &self,
        id: &str,
        account_id: Option<&str>,
        challenge: &[u8],
        challenge_type: &str,
        expires_at: &str,
        now: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"INSERT INTO webauthn_challenges (id, account_id, challenge, challenge_type, expires_at, created_at)
               VALUES (?, ?, ?, ?, ?, ?)"#,
        )
        .bind(id)
        .bind(account_id)
        .bind(challenge)
        .bind(challenge_type)
        .bind(expires_at)
        .bind(now)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn find_challenge(&self, id: &str) -> Result<Option<ChallengeRow>, sqlx::Error> {
        sqlx::query_as::<_, ChallengeRow>("SELECT * FROM webauthn_challenges WHERE id = ?")
            .bind(id)
            .fetch_optional(&self.pool)
            .await
    }

    pub async fn delete_challenge(&self, id: &str) -> Result<(), sqlx::Error> {
        sqlx::query("DELETE FROM webauthn_challenges WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn cleanup_expired_challenges(&self) -> Result<u64, sqlx::Error> {
        let result = sqlx::query("DELETE FROM webauthn_challenges WHERE datetime(expires_at) < datetime('now')")
            .execute(&self.pool)
            .await?;
        Ok(result.rows_affected())
    }

    // ========================================================================
    // Recovery Codes
    // ========================================================================

    pub async fn create_recovery_codes(&self, account_id: &str, code_hashes: &[(String, String)], now: &str) -> Result<(), sqlx::Error> {
        for (id, hash) in code_hashes {
            sqlx::query(
                r#"INSERT INTO recovery_codes (id, account_id, code_hash, used, created_at)
                   VALUES (?, ?, ?, 0, ?)"#,
            )
            .bind(id)
            .bind(account_id)
            .bind(hash)
            .bind(now)
            .execute(&self.pool)
            .await?;
        }
        Ok(())
    }

    pub async fn list_recovery_codes(&self, account_id: &str) -> Result<Vec<RecoveryCodeRow>, sqlx::Error> {
        sqlx::query_as::<_, RecoveryCodeRow>("SELECT * FROM recovery_codes WHERE account_id = ? ORDER BY created_at")
            .bind(account_id)
            .fetch_all(&self.pool)
            .await
    }

    pub async fn mark_recovery_code_used(&self, id: &str, now: &str) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE recovery_codes SET used = 1, used_at = ? WHERE id = ?")
            .bind(now)
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn delete_recovery_codes(&self, account_id: &str) -> Result<(), sqlx::Error> {
        sqlx::query("DELETE FROM recovery_codes WHERE account_id = ?")
            .bind(account_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    // ========================================================================
    // User Vault
    // ========================================================================

    pub async fn create_vault(
        &self,
        id: &str,
        account_id: &str,
        encrypted_data: &[u8],
        salt: &[u8],
        nonce: &[u8],
        now: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"INSERT INTO user_vaults (id, account_id, encrypted_data, salt, nonce, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)"#,
        )
        .bind(id)
        .bind(account_id)
        .bind(encrypted_data)
        .bind(salt)
        .bind(nonce)
        .bind(now)
        .bind(now)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn find_vault(&self, account_id: &str) -> Result<Option<VaultRow>, sqlx::Error> {
        sqlx::query_as::<_, VaultRow>("SELECT * FROM user_vaults WHERE account_id = ?")
            .bind(account_id)
            .fetch_optional(&self.pool)
            .await
    }

    pub async fn update_vault(
        &self,
        account_id: &str,
        encrypted_data: &[u8],
        salt: &[u8],
        nonce: &[u8],
        now: &str,
    ) -> Result<bool, sqlx::Error> {
        let result = sqlx::query(
            "UPDATE user_vaults SET encrypted_data = ?, salt = ?, nonce = ?, updated_at = ? WHERE account_id = ?",
        )
        .bind(encrypted_data)
        .bind(salt)
        .bind(nonce)
        .bind(now)
        .bind(account_id)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() > 0)
    }
}
