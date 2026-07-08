//! A-4 W4 acceptance tests: `/api/v1/vault` is a pure opaque-blob store.
//!
//! These tests prove the zero-knowledge property at the service layer against
//! a REAL in-memory SQLite database (no mocks): the backend stores exactly the
//! bytes it is given and returns them verbatim — it has no decryption code
//! path. The password and plaintext never appear in any of these calls.

use base64::Engine;
use icp_marketplace_api::{
    db::initialize_database,
    services::{PasskeyService, VaultData},
};
use poem::error::ResponseError;
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};

const B64: base64::engine::general_purpose::GeneralPurpose =
    base64::engine::general_purpose::STANDARD;

/// Builds an in-memory DB + PasskeyService, the same pattern as search_tests.
/// Returns the pool too so tests can seed `keypair_profiles` rows (the vault
/// FK target) — this keeps the test honest about the real schema relationships.
async fn setup_vault_service() -> (PasskeyService, SqlitePool) {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("failed to create in-memory sqlite pool");
    initialize_database(&pool).await;
    let service = PasskeyService::new(pool.clone(), "localhost", "http://localhost:58000")
        .expect("Failed to create PasskeyService");
    (service, pool)
}

/// Inserts a `keypair_profiles` row for `principal` so the vault FK is
/// satisfied. Mirrors what production flow would do before a vault is created.
async fn seed_principal(pool: &SqlitePool, principal: &str) {
    let now = "2026-07-04T00:00:00Z";
    sqlx::query(
        r#"INSERT INTO keypair_profiles
               (id, principal, display_name, username, created_at, updated_at)
           VALUES (?, ?, ?, NULL, ?, ?)"#,
    )
    .bind(format!("id-{principal}"))
    .bind(principal)
    .bind(format!("display-{principal}"))
    .bind(now)
    .bind(now)
    .execute(pool)
    .await
    .expect("failed to seed keypair_profiles row");
}

/// The opaque blob the client would have produced via local FFI crypto. We use
/// deterministic, arbitrary bytes here — the server must NOT interpret them.
struct Blob {
    encrypted_data: Vec<u8>,
    salt: Vec<u8>,
    nonce: Vec<u8>,
}

impl Blob {
    fn assert_round_trips(&self, data: &VaultData) {
        assert_eq!(
            B64.decode(&data.encrypted_data).unwrap(),
            self.encrypted_data,
            "encrypted_data must round-trip byte-for-byte",
        );
        assert_eq!(
            B64.decode(&data.salt).unwrap(),
            self.salt,
            "salt must round-trip byte-for-byte",
        );
        assert_eq!(
            B64.decode(&data.nonce).unwrap(),
            self.nonce,
            "nonce must round-trip byte-for-byte",
        );
    }
}

fn sample_blob_a() -> Blob {
    Blob {
        encrypted_data: vec![0xC0, 0xFF, 0xEE, 0x11, 0x22, 0x33, 0x44],
        salt: vec![0xA1; 16],
        nonce: vec![0xB2; 12],
    }
}

fn sample_blob_b() -> Blob {
    Blob {
        encrypted_data: vec![0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x99],
        salt: vec![0x55; 16],
        nonce: vec![0x77; 12],
    }
}

#[tokio::test]
async fn create_then_get_round_trips_blob_verbatim() {
    let (service, pool) = setup_vault_service().await;
    let account_id = "principal-aaaaa-1";
    seed_principal(&pool, account_id).await;
    let blob = sample_blob_a();

    service
        .create_vault(account_id, &blob.encrypted_data, &blob.salt, &blob.nonce)
        .await
        .expect("create_vault must succeed with a valid opaque blob");

    let stored = service
        .get_vault(account_id)
        .await
        .expect("get_vault must not return a DB error")
        .expect("vault must exist after create");

    blob.assert_round_trips(&stored);
}

#[tokio::test]
async fn update_replaces_blob_and_get_returns_new_bytes() {
    let (service, pool) = setup_vault_service().await;
    let account_id = "principal-bbbbb-2";
    seed_principal(&pool, account_id).await;

    let initial = sample_blob_a();
    service
        .create_vault(
            account_id,
            &initial.encrypted_data,
            &initial.salt,
            &initial.nonce,
        )
        .await
        .expect("initial create_vault must succeed");

    // Overwrite with a different client-produced blob.
    let replacement = sample_blob_b();
    service
        .update_vault(
            account_id,
            &replacement.encrypted_data,
            &replacement.salt,
            &replacement.nonce,
        )
        .await
        .expect("update_vault must succeed for an existing vault");

    let stored = service
        .get_vault(account_id)
        .await
        .expect("get_vault must not return a DB error")
        .expect("vault must still exist after update");

    // The server MUST hold the new bytes, not the old ones.
    replacement.assert_round_trips(&stored);
    assert_ne!(
        B64.decode(&stored.encrypted_data).unwrap(),
        initial.encrypted_data,
        "update must actually replace encrypted_data",
    );
}

#[tokio::test]
async fn create_rejects_duplicate_account() {
    let (service, pool) = setup_vault_service().await;
    let account_id = "principal-ccccc-3";
    seed_principal(&pool, account_id).await;
    let blob = sample_blob_a();

    service
        .create_vault(account_id, &blob.encrypted_data, &blob.salt, &blob.nonce)
        .await
        .expect("first create_vault must succeed");

    let err = service
        .create_vault(account_id, &blob.encrypted_data, &blob.salt, &blob.nonce)
        .await
        .expect_err("second create_vault for the same account must fail");
    assert!(
        err.message().contains("already exists"),
        "duplicate-create error must explain the conflict, got: {err}"
    );
}

#[tokio::test]
async fn update_fails_when_no_vault_exists() {
    let (service, pool) = setup_vault_service().await;
    let account_id = "principal-ddddd-4";
    seed_principal(&pool, account_id).await;
    let blob = sample_blob_a();

    let err = service
        .update_vault(account_id, &blob.encrypted_data, &blob.salt, &blob.nonce)
        .await
        .expect_err("update_vault on a missing vault must fail");
    assert!(
        err.message().contains("not found"),
        "missing-vault update error must say 'not found', got: {err}"
    );
}

#[tokio::test]
async fn get_returns_none_when_no_vault_exists() {
    let (service, _pool) = setup_vault_service().await;
    let stored = service
        .get_vault("principal-eeeee-5")
        .await
        .expect("get_vault for a missing vault must be Ok(None), not an error");
    assert!(stored.is_none(), "missing vault must map to Ok(None)");
}

/// Two different accounts must each hold their own blob independently — no
/// cross-talk, and the server stores both verbatim.
#[tokio::test]
async fn distinct_accounts_hold_distinct_blobs() {
    let (service, pool) = setup_vault_service().await;
    seed_principal(&pool, "principal-acc-a").await;
    seed_principal(&pool, "principal-acc-b").await;
    let blob_a = sample_blob_a();
    let blob_b = sample_blob_b();

    service
        .create_vault(
            "principal-acc-a",
            &blob_a.encrypted_data,
            &blob_a.salt,
            &blob_a.nonce,
        )
        .await
        .expect("create_vault for account A");
    service
        .create_vault(
            "principal-acc-b",
            &blob_b.encrypted_data,
            &blob_b.salt,
            &blob_b.nonce,
        )
        .await
        .expect("create_vault for account B");

    let stored_a = service
        .get_vault("principal-acc-a")
        .await
        .unwrap()
        .expect("vault A must exist");
    let stored_b = service
        .get_vault("principal-acc-b")
        .await
        .unwrap()
        .expect("vault B must exist");

    blob_a.assert_round_trips(&stored_a);
    blob_b.assert_round_trips(&stored_b);
}
