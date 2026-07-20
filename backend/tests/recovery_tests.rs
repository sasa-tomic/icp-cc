//! W6-13 (TQ-W6-2c): coverage for vault-loss recovery codes.
//!
//! Tests the recovery-code lifecycle against REAL in-memory SQLite + the REAL
//! Argon2id hashing in `vault.rs` (no mocking of the crypto). The one-shot
//! contract is the security-critical invariant (AGENTS.md "Loss isolation"):
//! each code is usable exactly once, so an attacker who intercepts a used code
//! cannot replay it to reset the vault.
//!
//! ## Argon2 note
//! `hash_recovery_code` / `verify_recovery_code` use the production params
//! (Argon2id, 64 MB, time=3) — ~5 s per op. To keep the suite fast we exercise
//! the 12-code `generate` contract in ONE test (12 hashes), and seed a SINGLE
//! code via `hash_recovery_code` + the repo everywhere else so the one-shot /
//! negative paths need ≤1 hash each.

use icp_marketplace_api::{
    db::initialize_database,
    repositories::PasskeyRepository,
    services::PasskeyService,
    vault::{generate_recovery_codes, hash_recovery_code},
};
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};

const NOW: &str = "2026-07-10T00:00:00Z";

/// In-memory DB + PasskeyService (the recovery methods live on it).
async fn setup() -> (PasskeyService, SqlitePool) {
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

/// `recovery_codes` has an FK `account_id → accounts(id)`, so a
/// row must exist before codes are stored.
async fn seed_principal(pool: &SqlitePool, principal: &str) {
    sqlx::query(
        r#"INSERT INTO accounts
               (id, username, display_name, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?)"#,
    )
    .bind(principal)
    .bind(format!("user-{principal}"))
    .bind(format!("display-{principal}"))
    .bind(NOW)
    .bind(NOW)
    .execute(pool)
    .await
    .expect("failed to seed accounts row");
}

/// Store ONE recovery code for `account_id` with a known plaintext, returning
/// that plaintext so the test can verify it. Uses the real Argon2id hasher
/// (exactly ONE hash op).
async fn seed_one_code(pool: &SqlitePool, account_id: &str, plaintext: &str) -> String {
    let repo = PasskeyRepository::new(pool.clone());
    let hash = hash_recovery_code(plaintext).expect("hash must succeed");
    let id = uuid::Uuid::new_v4().to_string();
    repo.create_recovery_codes(account_id, &[(id, hash)], NOW)
        .await
        .expect("create_recovery_codes must succeed");
    plaintext.to_string()
}

const ALPHABET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I/O/0/1

// ============================================================================
// generate
// ============================================================================

/// This test is `#[ignore]`-by-default because `generate_recovery_codes_for_account`
/// hashes all 12 codes with production Argon2id params (64 MB, time=3) → ~5 s per
/// hash × 12 ≈ 60 s total, which dominates the dev cycle. Run it explicitly for
/// pre-release verification:
///
/// ```sh
/// cargo nextest run --run-ignored only-ignored generate_returns_twelve
/// # or
/// cargo test --test recovery_tests -- --ignored --nocapture
/// ```
///
/// The rest of this file (one-shot, exhaust, negatives) seeds ≤1 pre-hashed code
/// per test so it stays sub-second; this is the ONLY test that exercises the full
/// 12-hash generate path end-to-end.
#[tokio::test]
#[ignore = "slow: 12× production Argon2id (~60s); run with --run-ignored or --ignored"]
async fn generate_returns_twelve_unique_codes_and_status_reflects_them() {
    let (service, pool) = setup().await;
    let account_id = "principal-gen";
    seed_principal(&pool, account_id).await;

    // Pre-seed a single leftover code so we ALSO prove generate deletes existing
    // codes (status must end at 12, not 13).
    seed_one_code(&pool, account_id, "LEFTOVER1").await;
    assert_eq!(
        service.get_recovery_code_status(account_id).await.unwrap(),
        1,
        "seeded leftover code must show status 1 before generate",
    );

    let result = service
        .generate_recovery_codes_for_account(account_id)
        .await
        .expect("generate must succeed");

    assert_eq!(
        result.codes.len(),
        12,
        "generate must produce exactly 12 codes"
    );
    assert_eq!(
        result.remaining_unused, 12,
        "remaining_unused must be 12 for a fresh set",
    );

    // All codes unique (one-time codes must not collide).
    let unique: std::collections::HashSet<&String> = result.codes.iter().collect();
    assert_eq!(unique.len(), 12, "all 12 codes must be distinct");

    // Format contract: 8 chars from the code alphabet (no ambiguous glyphs).
    for code in &result.codes {
        assert_eq!(code.len(), 8, "each code must be 8 chars: {code}");
        assert!(
            code.bytes().all(|b| ALPHABET.contains(&b)),
            "code '{code}' contains a character outside the alphabet",
        );
    }

    // Status must reflect all 12 (and NOT the leftover 1 — generate deletes
    // existing codes first). This is the proof the old set was replaced.
    assert_eq!(
        service.get_recovery_code_status(account_id).await.unwrap(),
        12,
        "status must be exactly 12 after generate (old codes must be replaced)",
    );
}

// ============================================================================
// status
// ============================================================================

#[tokio::test]
async fn status_returns_zero_for_account_with_no_codes() {
    let (service, pool) = setup().await;
    let account_id = "principal-empty";
    seed_principal(&pool, account_id).await;

    let remaining = service
        .get_recovery_code_status(account_id)
        .await
        .expect("status for an account with no codes must be Ok(0)");
    assert_eq!(
        remaining, 0,
        "an account with no codes must report 0 remaining"
    );
}

// ============================================================================
// verify — the one-shot contract
// ============================================================================

#[tokio::test]
async fn verify_consumes_code_one_shot() {
    // The security-critical invariant: a valid code is accepted ONCE; the
    // exact-same code presented again is rejected.
    let (service, pool) = setup().await;
    let account_id = "principal-oneshot";
    seed_principal(&pool, account_id).await;
    let code = seed_one_code(&pool, account_id, "ONESHOTA").await;

    // First presentation: valid.
    let first = service
        .verify_recovery_code_for_account(account_id, &code)
        .await
        .expect("first verify must not error");
    assert!(first, "a freshly-seeded code must verify as valid");

    // Status now reflects the consumption.
    assert_eq!(
        service.get_recovery_code_status(account_id).await.unwrap(),
        0,
        "consuming the only code must drop remaining to 0",
    );

    // Replay the SAME code: must be rejected (one-shot). The used code is
    // skipped, so this returns false — NOT an error.
    let replay = service
        .verify_recovery_code_for_account(account_id, &code)
        .await
        .expect("replay must be Ok(false), not an error");
    assert!(
        !replay,
        "a used code must NOT verify again — the one-shot contract",
    );
}

#[tokio::test]
async fn verify_rejects_wrong_code() {
    let (service, pool) = setup().await;
    let account_id = "principal-wrong";
    seed_principal(&pool, account_id).await;
    let _ = seed_one_code(&pool, account_id, "CORRECT1").await;

    let result = service
        .verify_recovery_code_for_account(account_id, "ZZZNOSUCH")
        .await
        .expect("a non-matching code must be Ok(false)");
    assert!(
        !result,
        "a code that matches nothing must verify as invalid",
    );

    // The real (correct) code must remain usable — a wrong guess does not
    // consume a slot.
    assert_eq!(
        service.get_recovery_code_status(account_id).await.unwrap(),
        1,
        "a wrong guess must NOT consume a code slot",
    );
}

#[tokio::test]
async fn verify_returns_false_when_account_has_no_codes() {
    let (service, pool) = setup().await;
    let account_id = "principal-none";
    seed_principal(&pool, account_id).await;

    let result = service
        .verify_recovery_code_for_account(account_id, "ANYCODE1")
        .await
        .expect("verify on an account with no codes must be Ok(false)");
    assert!(!result, "no codes stored must verify as invalid, not error",);
}

// ============================================================================
// Vault reset path (recovery unlocks a vault overwrite)
// ============================================================================

#[tokio::test]
async fn recovery_code_enables_vault_reset_after_loss() {
    // Mirrors the documented product flow: a user who lost their passkey uses a
    // recovery code to authenticate, then resets their vault. We assert the
    // pieces compose: a valid recovery code → true, and a subsequent vault
    // create/update succeeds (the recovery path doesn't block the opaque-blob
    // store). This ties the recovery + vault subsystems together.
    let (service, pool) = setup().await;
    let account_id = "principal-reset";
    seed_principal(&pool, account_id).await;
    let code = seed_one_code(&pool, account_id, "RESET123").await;

    // 1. The recovery code authenticates the reset request.
    assert!(
        service
            .verify_recovery_code_for_account(account_id, &code)
            .await
            .unwrap(),
        "recovery code must verify to authorise the reset",
    );

    // 2. Create the initial vault blob (client-side encrypted, opaque).
    service
        .create_vault(account_id, &[0xC0; 16], &[0xA1; 16], &[0xB2; 12])
        .await
        .expect("initial vault create must succeed");

    // 3. Reset: overwrite the vault with a new blob (new password → new salt).
    service
        .update_vault(account_id, &[0xDE; 16], &[0x55; 16], &[0x77; 12])
        .await
        .expect("vault update (reset) must succeed after recovery auth");

    // The stored blob is the NEW one.
    let stored = service
        .get_vault(account_id)
        .await
        .unwrap()
        .expect("vault must exist");
    use base64::Engine;
    assert_eq!(
        base64::engine::general_purpose::STANDARD
            .decode(&stored.encrypted_data)
            .unwrap(),
        vec![0xDE; 16],
        "vault reset must persist the new blob",
    );
}

// ============================================================================
// Sanity: the raw generator (no DB) — fast, no Argon2.
// ============================================================================

#[test]
fn raw_generate_recovery_codes_produces_twelve_formatted_codes() {
    // `generate_recovery_codes` (the plaintext generator, no hashing) is the
    // input to the service path. Confirms the count + alphabet independent of
    // the slow Argon2 store.
    let codes = generate_recovery_codes();
    assert_eq!(codes.len(), 12);
    for c in &codes {
        assert_eq!(c.len(), 8);
        assert!(c.bytes().all(|b| ALPHABET.contains(&b)), "bad char in {c}");
    }
}

// ============================================================================
// W7-14: HTTP-level rate-limit on the open POST /recovery/verify oracle.
// ============================================================================

/// `POST /recovery/verify` stays open (a locked-out user has no keypair), but
/// after 5 failed codes in 15 min it MUST return 429 (W7-007 brute-force
/// throttle). Proven end-to-end through the real handler + TestClient.
#[tokio::test]
async fn recovery_verify_rate_limits_after_five_failed_attempts() {
    use icp_marketplace_api::handlers::recovery_verify;
    use poem::{post, test::TestClient, EndpointExt, Route};
    use std::sync::Arc;

    let pool = sqlx::sqlite::SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("pool");
    icp_marketplace_api::db::initialize_database(&pool).await;

    let (service, _) = setup().await;
    // Reuse the setup's service is awkward (separate pool); build state here so
    // the handler, the seeded code, and the rate-limiter share ONE pool.
    let _ = service; // drop the helper's service (its pool is unrelated)
    let account_id = "principal-ratelimit";
    seed_principal(&pool, account_id).await;
    // Seed ONE real-hashed code so verify returns `false` (not an error) for
    // wrong guesses — exercising the failure-counting path.
    let _ = seed_one_code(&pool, account_id, "REALCODE1").await;

    let passkey_service = icp_marketplace_api::services::PasskeyService::new(
        pool.clone(),
        "localhost",
        "http://localhost:58000",
    )
    .expect("PasskeyService");
    let state = Arc::new(icp_marketplace_api::test_support::app_state_stub(
        pool,
        passkey_service,
        Arc::new(icp_marketplace_api::rate_limit::SlidingWindowRateLimiter::new(
            5,
            15 * 60,
        )),
    ));

    let app = Route::new()
        .at("/recovery/verify", post(recovery_verify))
        .data(state);
    let client = TestClient::new(app);

    // 5 wrong codes → each 200 with valid:false (under the limit).
    for i in 1..=5 {
        let resp = client
            .post("/recovery/verify")
            .body_json(&serde_json::json!({
                "account_id": account_id,
                "code": format!("WRONG{i}"),
            }))
            .send()
            .await;
        resp.assert_status(poem::http::StatusCode::OK);
        let body: serde_json::Value = resp.0.into_body().into_json().await.unwrap();
        assert_eq!(
            body["data"]["valid"], false,
            "attempt {i}: wrong code → invalid"
        );
    }

    // 6th wrong code → 429 (rate-limited).
    let resp = client
        .post("/recovery/verify")
        .body_json(&serde_json::json!({
            "account_id": account_id,
            "code": "WRONG6",
        }))
        .send()
        .await;
    resp.assert_status(poem::http::StatusCode::TOO_MANY_REQUESTS);
}
