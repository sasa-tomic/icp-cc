//! TQ-W6-2e: Dedicated unit tests for the account, script, and review
//! repositories.
//!
//! These tests exercise the repositories directly against a real in-memory
//! SQLite database (real schema via `initialize_database`, no mocks) — proving
//! that every SQL statement the repositories emit behaves correctly in
//! isolation from the HTTP/service layers.
//!
//! Coverage rules per AGENTS.md: every public method gets at least one positive
//! path and a negative/edge path where applicable. No overlap with existing
//! integration tests (`scripts_categories_tests.rs` exercises
//! `distinct_categories` at the handler layer; `search_tests.rs` re-implements
//! the search SQL rather than calling `ScriptRepository::search`).
//!
//! The passkey repository is already covered by `passkey_tests.rs`.

use icp_marketplace_api::{
    db::initialize_database,
    models::SearchRequest,
    repositories::{
        AccountRepository, CreateAccountParams, ReviewRepository, ScriptRepository,
        SignatureAuditParams, UpdateAccountParams,
    },
};
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};

const NOW: &str = "2026-07-11T00:00:00Z";

async fn setup() -> SqlitePool {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("failed to create in-memory sqlite pool");
    initialize_database(&pool).await;
    pool
}

// ===========================================================================
// AccountRepository
// ===========================================================================

async fn create_account_full(repo: &AccountRepository, id: &str, username: &str) {
    repo.create_account(CreateAccountParams {
        account_id: id,
        username,
        display_name: &format!("Display {username}"),
        contact_email: Some("user@example.com"),
        contact_telegram: Some("@user"),
        contact_twitter: Some("@user_tw"),
        contact_discord: Some("user#1234"),
        website_url: Some("https://example.com"),
        bio: Some("A bio"),
        now: NOW,
    })
    .await
    .expect("create_account failed");
}

async fn add_key(
    repo: &AccountRepository,
    key_id: &str,
    account_id: &str,
    pubkey: &str,
    principal: &str,
    added_at: &str,
) {
    repo.add_public_key(key_id, account_id, pubkey, principal, added_at)
        .await
        .expect("add_public_key failed");
}

#[tokio::test]
async fn account_create_and_find_by_username_round_trips_all_fields() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    create_account_full(&repo, "acc-1", "alice").await;

    let account = repo
        .find_by_username("alice")
        .await
        .expect("find_by_username failed")
        .expect("account should exist");

    assert_eq!(account.id, "acc-1");
    assert_eq!(account.username, "alice");
    assert_eq!(account.display_name, "Display alice");
    assert_eq!(account.contact_email.as_deref(), Some("user@example.com"));
    assert_eq!(account.contact_telegram.as_deref(), Some("@user"));
    assert_eq!(account.contact_twitter.as_deref(), Some("@user_tw"));
    assert_eq!(account.contact_discord.as_deref(), Some("user#1234"));
    assert_eq!(account.website_url.as_deref(), Some("https://example.com"));
    assert_eq!(account.bio.as_deref(), Some("A bio"));
    assert_eq!(account.created_at, NOW);
    assert_eq!(account.updated_at, NOW);
}

#[tokio::test]
async fn account_find_by_id_returns_account() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    create_account_full(&repo, "acc-1", "alice").await;

    let account = repo
        .find_by_id("acc-1")
        .await
        .expect("find_by_id failed")
        .expect("account should exist");
    assert_eq!(account.username, "alice");
}

#[tokio::test]
async fn account_find_returns_none_for_unknown_id() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    let found = repo
        .find_by_id("ghost")
        .await
        .expect("find_by_id failed");
    assert!(found.is_none());
}

#[tokio::test]
async fn account_find_returns_none_for_unknown_username() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    let found = repo
        .find_by_username("ghost")
        .await
        .expect("find_by_username failed");
    assert!(found.is_none());
}

#[tokio::test]
async fn account_update_changes_specified_fields_and_preserves_others() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    create_account_full(&repo, "acc-1", "alice").await;

    repo.update_account(UpdateAccountParams {
        account_id: "acc-1",
        display_name: Some("Alice Updated"),
        bio: Some("New bio"),
        contact_email: None,
        contact_telegram: None,
        contact_twitter: None,
        contact_discord: None,
        website_url: None,
        now: "2026-07-11T12:00:00Z",
    })
    .await
    .expect("update_account failed");

    let account = repo
        .find_by_id("acc-1")
        .await
        .unwrap()
        .expect("account should exist");
    assert_eq!(account.display_name, "Alice Updated");
    assert_eq!(account.bio.as_deref(), Some("New bio"));
    // Untouched fields are preserved.
    assert_eq!(account.contact_email.as_deref(), Some("user@example.com"));
    assert_eq!(account.contact_telegram.as_deref(), Some("@user"));
    assert_eq!(account.updated_at, "2026-07-11T12:00:00Z");
}

#[tokio::test]
async fn account_update_with_no_fields_is_noop() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    create_account_full(&repo, "acc-1", "alice").await;

    repo.update_account(UpdateAccountParams {
        account_id: "acc-1",
        display_name: None,
        bio: None,
        contact_email: None,
        contact_telegram: None,
        contact_twitter: None,
        contact_discord: None,
        website_url: None,
        now: "2026-07-11T12:00:00Z",
    })
    .await
    .expect("noop update should succeed");

    // updated_at must NOT change — the method short-circuits when no fields.
    let account = repo.find_by_id("acc-1").await.unwrap().unwrap();
    assert_eq!(account.updated_at, NOW);
}

#[tokio::test]
async fn account_keys_ordered_by_added_at_ascending() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    create_account_full(&repo, "acc-1", "alice").await;
    // Insert out of chronological order to prove ORDER BY added_at works.
    add_key(&repo, "key-b", "acc-1", "pk-bbb", "principal-bbb", "2026-07-11T10:00:00Z").await;
    add_key(&repo, "key-a", "acc-1", "pk-aaa", "principal-aaa", "2026-07-11T05:00:00Z").await;
    add_key(&repo, "key-c", "acc-1", "pk-ccc", "principal-ccc", "2026-07-11T15:00:00Z").await;

    let keys = repo
        .get_account_keys("acc-1")
        .await
        .expect("get_account_keys failed");
    assert_eq!(keys.len(), 3);
    assert_eq!(keys[0].id, "key-a"); // earliest added_at
    assert_eq!(keys[1].id, "key-b");
    assert_eq!(keys[2].id, "key-c"); // latest added_at
    assert!(keys.iter().all(|k| k.is_active));
}

#[tokio::test]
async fn account_get_keys_empty_for_unknown_account() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    let keys = repo
        .get_account_keys("nope")
        .await
        .expect("get_account_keys failed");
    assert!(keys.is_empty());
}

#[tokio::test]
async fn account_find_public_key_by_value() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    create_account_full(&repo, "acc-1", "alice").await;
    add_key(&repo, "key-1", "acc-1", "pk-aaa", "principal-aaa", NOW).await;

    let key = repo
        .find_public_key_by_value("pk-aaa")
        .await
        .expect("find_public_key_by_value failed")
        .expect("key should exist");
    assert_eq!(key.id, "key-1");
    assert_eq!(key.account_id, "acc-1");
    assert_eq!(key.ic_principal, "principal-aaa");
    assert!(key.is_active);
}

#[tokio::test]
async fn account_find_public_key_by_value_returns_none_for_unknown() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    let found = repo
        .find_public_key_by_value("ghost")
        .await
        .expect("find_public_key_by_value failed");
    assert!(found.is_none());
}

#[tokio::test]
async fn account_find_key_by_id() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    create_account_full(&repo, "acc-1", "alice").await;
    add_key(&repo, "key-1", "acc-1", "pk-aaa", "principal-aaa", NOW).await;

    let key = repo
        .find_key_by_id("key-1")
        .await
        .expect("find_key_by_id failed")
        .expect("key should exist");
    assert_eq!(key.public_key, "pk-aaa");
}

#[tokio::test]
async fn account_find_key_by_id_returns_none_for_unknown() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    let found = repo
        .find_key_by_id("ghost")
        .await
        .expect("find_key_by_id failed");
    assert!(found.is_none());
}

#[tokio::test]
async fn account_count_active_and_count_all_after_disable() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool);

    create_account_full(&repo, "acc-1", "alice").await;
    add_key(&repo, "key-1", "acc-1", "pk-aaa", "principal-aaa", NOW).await;
    add_key(&repo, "key-2", "acc-1", "pk-bbb", "principal-bbb", NOW).await;
    add_key(&repo, "key-3", "acc-1", "pk-ccc", "principal-ccc", NOW).await;

    // 3 active, 3 total.
    assert_eq!(repo.count_active_keys("acc-1").await.unwrap(), 3);
    assert_eq!(repo.count_all_keys("acc-1").await.unwrap(), 3);

    // Disable key-2, recording key-1 as the disabler.
    repo.disable_key("key-2", "key-1", "2026-07-11T12:00:00Z")
        .await
        .expect("disable_key failed");

    // 2 active, 3 total (soft-delete).
    assert_eq!(repo.count_active_keys("acc-1").await.unwrap(), 2);
    assert_eq!(repo.count_all_keys("acc-1").await.unwrap(), 3);

    // Verify the disabled key's metadata.
    let disabled = repo.find_key_by_id("key-2").await.unwrap().unwrap();
    assert!(!disabled.is_active);
    assert_eq!(disabled.disabled_at.as_deref(), Some("2026-07-11T12:00:00Z"));
    assert_eq!(disabled.disabled_by_key_id.as_deref(), Some("key-1"));

    // key-1 and key-3 still active.
    let k1 = repo.find_key_by_id("key-1").await.unwrap().unwrap();
    let k3 = repo.find_key_by_id("key-3").await.unwrap().unwrap();
    assert!(k1.is_active);
    assert!(k3.is_active);
}

#[tokio::test]
async fn account_record_signature_audit_persists_row() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool.clone());

    create_account_full(&repo, "acc-1", "alice").await;

    repo.record_signature_audit(SignatureAuditParams {
        audit_id: "audit-1",
        account_id: Some("acc-1"),
        action: "upload_script",
        payload: "payload-bytes",
        signature: "sig-hex",
        public_key: "pk-aaa",
        timestamp: 1_720_000_000_i64,
        nonce: "nonce-123",
        is_admin_action: false,
        now: NOW,
    })
    .await
    .expect("record_signature_audit failed");

    // No find method on the repo — verify via a raw count.
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM signature_audit")
        .fetch_one(&pool)
        .await
        .expect("count query failed");
    assert_eq!(count, 1);

    let is_admin: i64 =
        sqlx::query_scalar("SELECT is_admin_action FROM signature_audit WHERE id = ?1")
            .bind("audit-1")
            .fetch_one(&pool)
            .await
            .expect("fetch is_admin failed");
    assert_eq!(is_admin, 0);
}

#[tokio::test]
async fn account_record_signature_audit_admin_flag_stored_as_one() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool.clone());

    repo.record_signature_audit(SignatureAuditParams {
        audit_id: "audit-admin",
        account_id: None,
        action: "disable_key",
        payload: "payload",
        signature: "sig",
        public_key: "pk",
        timestamp: 0,
        nonce: "n",
        is_admin_action: true,
        now: NOW,
    })
    .await
    .expect("record_signature_audit failed");

    let is_admin: i64 =
        sqlx::query_scalar("SELECT is_admin_action FROM signature_audit WHERE id = ?1")
            .bind("audit-admin")
            .fetch_one(&pool)
            .await
            .expect("fetch failed");
    assert_eq!(is_admin, 1);
}

// ---------------------------------------------------------------------------
// W7-011: the `signature_audit.nonce` UNIQUE constraint is the race-proof
// source of truth for replay prevention. These tests prove (a) a duplicate
// nonce INSERT fails at the DB (killing the TOCTOU window between
// `validate_replay_prevention`'s SELECT-COUNT and the audit INSERT), and (b)
// `auth::is_audit_replay_error` classifies that failure as a replay while a
// different SQL fault is NOT misclassified.
// ---------------------------------------------------------------------------

#[tokio::test]
async fn account_record_signature_audit_rejects_duplicate_nonce() {
    let pool = setup().await;
    let repo = AccountRepository::new(pool.clone());
    create_account_full(&repo, "acc-dup", "dupalice").await;

    // First insert with nonce "nonce-shared" succeeds.
    repo.record_signature_audit(SignatureAuditParams {
        audit_id: "audit-first",
        account_id: Some("acc-dup"),
        action: "register_account",
        payload: "p",
        signature: "s",
        public_key: "pk",
        timestamp: 1,
        nonce: "nonce-shared",
        is_admin_action: false,
        now: NOW,
    })
    .await
    .expect("first audit insert should succeed");

    // Second insert with the SAME nonce must fail — the UNIQUE constraint is
    // what closes the TOCTOU replay window. Two concurrent identical-nonce
    // requests can no longer both pass the SELECT-COUNT gate before either
    // INSERTs.
    let err = repo
        .record_signature_audit(SignatureAuditParams {
            audit_id: "audit-second",
            account_id: Some("acc-dup"),
            action: "register_account",
            payload: "p2",
            signature: "s2",
            public_key: "pk2",
            timestamp: 2,
            nonce: "nonce-shared",
            is_admin_action: false,
            now: NOW,
        })
        .await
        .expect_err("duplicate-nonce INSERT must fail the UNIQUE constraint");

    // And the shared classifier recognises it as a replay (not a generic fault).
    assert!(
        icp_marketplace_api::auth::is_audit_replay_error(&err),
        "duplicate-nonce violation must classify as a replay, got: {err:?}"
    );
}

#[tokio::test]
async fn account_record_signature_audit_distinct_nonces_both_succeed() {
    // Negative control for the above: distinct nonces are both accepted, so
    // the constraint is specifically on `nonce` (not overzealous).
    let pool = setup().await;
    let repo = AccountRepository::new(pool.clone());
    create_account_full(&repo, "acc-distinct", "distalice").await;

    for (audit_id, nonce) in [("audit-a", "nonce-a"), ("audit-b", "nonce-b")] {
        repo.record_signature_audit(SignatureAuditParams {
            audit_id,
            account_id: Some("acc-distinct"),
            action: "register_account",
            payload: "p",
            signature: "s",
            public_key: "pk",
            timestamp: 1,
            nonce,
            is_admin_action: false,
            now: NOW,
        })
        .await
        .expect("distinct-nonce insert should succeed");
    }

    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM signature_audit")
        .fetch_one(&pool)
        .await
        .expect("count query failed");
    assert_eq!(count, 2);
}

// ===========================================================================
// ScriptRepository
// ===========================================================================

/// Convenience: create a script with sensible defaults; override via parameters.
async fn create_script(
    repo: &ScriptRepository,
    id: &str,
    category: &str,
    is_public: bool,
    title: &str,
) {
    repo.create(
        id,
        &format!("slug-{id}"),
        None, // owner_account_id
        title,
        "A description",
        category,
        "bundle-bytes",
        Some("principal-author"),
        Some("pk-author"),
        Some("sig-author"),
        "1.0.0",
        0.0,
        is_public,
        Some(">=1.0"),
        Some(r#"["tag1","tag2"]"#),
        NOW,
    )
    .await
    .expect("create script failed");
}

#[tokio::test]
async fn script_create_and_find_by_id_round_trips_all_fields() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "My Script").await;

    let s = repo
        .find_by_id("s-1")
        .await
        .expect("find_by_id failed")
        .expect("script should exist");

    assert_eq!(s.id, "s-1");
    assert_eq!(s.slug, "slug-s-1");
    assert_eq!(s.title, "My Script");
    assert_eq!(s.description, "A description");
    assert_eq!(s.category, "Utilities");
    assert_eq!(s.bundle, "bundle-bytes");
    assert_eq!(s.author_principal.as_deref(), Some("principal-author"));
    assert_eq!(s.author_public_key.as_deref(), Some("pk-author"));
    assert_eq!(s.upload_signature.as_deref(), Some("sig-author"));
    assert_eq!(s.version, "1.0.0");
    assert_eq!(s.price, 0.0);
    assert!(s.is_public);
    assert_eq!(s.downloads, 0); // schema default
    assert_eq!(s.rating, 0.0); // schema default
    assert_eq!(s.review_count, 0); // schema default
    assert_eq!(s.compatibility.as_deref(), Some(">=1.0"));
    assert_eq!(s.tags.as_deref(), Some(r#"["tag1","tag2"]"#));
    assert!(s.deleted_at.is_none());
    assert_eq!(s.created_at, NOW);
}

#[tokio::test]
async fn script_find_by_id_returns_none_for_unknown() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    let found = repo.find_by_id("ghost").await.expect("find_by_id failed");
    assert!(found.is_none());
}

#[tokio::test]
async fn script_find_by_id_excludes_soft_deleted() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "Title").await;
    repo.delete("s-1", "2026-07-11T12:00:00Z")
        .await
        .expect("delete failed");

    let found = repo.find_by_id("s-1").await.expect("find_by_id failed");
    assert!(found.is_none());
}

#[tokio::test]
async fn script_count_public_excludes_private_and_deleted() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await;
    create_script(&repo, "s-2", "Utilities", true, "B").await;
    create_script(&repo, "s-3", "Utilities", false, "C").await; // private
    create_script(&repo, "s-4", "Utilities", true, "D").await;
    repo.delete("s-4", "2026-07-11T12:00:00Z")
        .await
        .expect("delete failed"); // soft-deleted

    assert_eq!(repo.count_public().await.unwrap(), 2); // s-1, s-2
}

#[tokio::test]
async fn script_count_by_id_excludes_soft_deleted() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await;
    assert_eq!(repo.count_by_id("s-1").await.unwrap(), 1);

    repo.delete("s-1", NOW).await.unwrap();
    assert_eq!(repo.count_by_id("s-1").await.unwrap(), 0);
}

#[tokio::test]
async fn script_count_by_id_returns_zero_for_unknown() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    assert_eq!(repo.count_by_id("ghost").await.unwrap(), 0);
}

#[tokio::test]
async fn script_find_all_privacy_filter_excludes_private() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "Pub").await;
    create_script(&repo, "s-2", "Utilities", false, "Priv").await;

    let public_only = repo
        .find_all(100, 0, None, false)
        .await
        .expect("find_all failed");
    assert_eq!(public_only.len(), 1);
    assert_eq!(public_only[0].id, "s-1");

    let including_private = repo
        .find_all(100, 0, None, true)
        .await
        .expect("find_all failed");
    assert_eq!(including_private.len(), 2);
}

#[tokio::test]
async fn script_find_all_category_filter() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await;
    create_script(&repo, "s-2", "Finance", true, "B").await;
    create_script(&repo, "s-3", "Utilities", true, "C").await;

    let utils = repo
        .find_all(100, 0, Some("Utilities".to_string()), false)
        .await
        .expect("find_all failed");
    assert_eq!(utils.len(), 2);
    assert!(utils.iter().all(|s| s.category == "Utilities"));
}

/// W7-1 (security): the `category` argument to `find_all` MUST be bound as a
/// SQL parameter, never string-interpolated. This test drives the classic
/// injection payload `zzz' OR 1=1--` through `find_all` with
/// `include_private = false`:
///
/// - **Pre-fix** the payload escapes the quote, ORs in `1=1`, and comments out
///   the trailing `AND is_public = 1`, so EVERY row (including private
///   scripts) is returned — defeating the privacy filter.
/// - **Post-fix** (parameterised bind) the literal string is treated as a
///   value, so it matches no row and nothing leaks.
#[tokio::test]
async fn script_find_all_category_filter_rejects_sql_injection() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    // Seed: two public scripts in different categories + one private script.
    create_script(&repo, "s-pub-util", "Utilities", true, "Pub Util").await;
    create_script(&repo, "s-pub-fin", "Finance", true, "Pub Fin").await;
    create_script(&repo, "s-priv", "Utilities", false, "Private").await;

    // The injection: closes the quote, ORs a tautology, comments out the rest.
    let injection = "zzz' OR 1=1--".to_string();
    let leaked = repo
        .find_all(100, 0, Some(injection), false)
        .await
        .expect("find_all failed");

    assert!(
        leaked.is_empty(),
        "category injection must not bypass the privacy filter; got {} rows: {:?}",
        leaked.len(),
        leaked.iter().map(|s| s.id.as_str()).collect::<Vec<_>>()
    );
    // Belt-and-braces: the private script must never appear.
    assert!(
        !leaked.iter().any(|s| s.id == "s-priv"),
        "private script leaked via category injection"
    );

    // A legitimate category still filters correctly (regression guard for the
    // parameterisation itself — proves the bind matches real values).
    let utils = repo
        .find_all(100, 0, Some("Utilities".to_string()), false)
        .await
        .expect("find_all failed");
    assert_eq!(utils.len(), 1, "only the public Utilities script matches");
    assert_eq!(utils[0].id, "s-pub-util");
}

#[tokio::test]
async fn script_find_all_pagination() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    for i in 1..=5 {
        create_script(&repo, &format!("s-{i}"), "Utilities", true, &format!("T{i}")).await;
    }

    let page = repo.find_all(2, 1, None, false).await.expect("find_all failed");
    assert_eq!(page.len(), 2);
}

#[tokio::test]
async fn script_find_by_slug() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await;
    create_script(&repo, "s-2", "Utilities", true, "B").await;

    let results = repo
        .find_by_slug("slug-s-1")
        .await
        .expect("find_by_slug failed");
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].id, "s-1");

    let empty = repo
        .find_by_slug("nope")
        .await
        .expect("find_by_slug failed");
    assert!(empty.is_empty());
}

#[tokio::test]
async fn script_publish_makes_private_script_public() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", false, "Private").await;
    assert!(!repo.find_by_id("s-1").await.unwrap().unwrap().is_public);

    repo.publish("s-1", "2026-07-11T12:00:00Z")
        .await
        .expect("publish failed");

    let s = repo.find_by_id("s-1").await.unwrap().unwrap();
    assert!(s.is_public);
    assert_eq!(s.updated_at, "2026-07-11T12:00:00Z");
}

#[tokio::test]
async fn script_update_changes_specified_fields() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "Original").await;

    repo.update(
        "s-1",
        Some("Updated Title"),
        Some("Updated description"),
        Some("Finance"),
        Some("new-bundle"),
        Some("2.0.0"),
        Some(9.99),
        Some(false),
        Some(r#"["new"]"#),
        "2026-07-11T12:00:00Z",
    )
    .await
    .expect("update failed");

    let s = repo.find_by_id("s-1").await.unwrap().unwrap();
    assert_eq!(s.title, "Updated Title");
    assert_eq!(s.description, "Updated description");
    assert_eq!(s.category, "Finance");
    assert_eq!(s.bundle, "new-bundle");
    assert_eq!(s.version, "2.0.0");
    assert_eq!(s.price, 9.99);
    assert!(!s.is_public);
    assert_eq!(s.tags.as_deref(), Some(r#"["new"]"#));
    assert_eq!(s.updated_at, "2026-07-11T12:00:00Z");
}

#[tokio::test]
async fn script_update_with_all_none_only_touches_updated_at() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "Original").await;

    repo.update("s-1", None, None, None, None, None, None, None, None, "2026-07-11T12:00:00Z")
        .await
        .expect("update failed");

    let s = repo.find_by_id("s-1").await.unwrap().unwrap();
    assert_eq!(s.title, "Original"); // unchanged
    assert_eq!(s.updated_at, "2026-07-11T12:00:00Z");
}

#[tokio::test]
async fn script_delete_is_soft_delete() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool.clone());

    create_script(&repo, "s-1", "Utilities", true, "A").await;
    repo.delete("s-1", "2026-07-11T12:00:00Z")
        .await
        .expect("delete failed");

    // find_by_id excludes soft-deleted.
    assert!(repo.find_by_id("s-1").await.unwrap().is_none());
    // But the row still exists (raw query).
    let deleted_at: Option<String> =
        sqlx::query_scalar("SELECT deleted_at FROM scripts WHERE id = ?1")
            .bind("s-1")
            .fetch_one(&pool)
            .await
            .expect("raw query failed");
    assert_eq!(deleted_at.as_deref(), Some("2026-07-11T12:00:00Z"));
}

#[tokio::test]
async fn script_update_stats_sets_rating_and_review_count() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await;
    repo.update_stats("s-1", 4.5, 10)
        .await
        .expect("update_stats failed");

    let s = repo.find_by_id("s-1").await.unwrap().unwrap();
    assert_eq!(s.rating, 4.5);
    assert_eq!(s.review_count, 10);
}

#[tokio::test]
async fn script_increment_downloads() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await;

    repo.increment_downloads("s-1").await.expect("increment failed");
    repo.increment_downloads("s-1").await.expect("increment failed");
    repo.increment_downloads("s-1").await.expect("increment failed");

    let s = repo.find_by_id("s-1").await.unwrap().unwrap();
    assert_eq!(s.downloads, 3);
}

#[tokio::test]
async fn script_get_by_category_returns_only_public_matching() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await;
    create_script(&repo, "s-2", "Utilities", false, "B").await; // private — excluded
    create_script(&repo, "s-3", "Finance", true, "C").await; // other category

    let results = repo
        .get_by_category("Utilities", 100)
        .await
        .expect("get_by_category failed");
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].id, "s-1");
}

#[tokio::test]
async fn script_get_trending_orders_by_downloads_then_rating() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    // All public, different download counts.
    create_script(&repo, "s-low", "Utilities", true, "Low").await; // 0 downloads
    create_script(&repo, "s-high", "Utilities", true, "High").await;
    create_script(&repo, "s-mid", "Utilities", true, "Mid").await;

    repo.increment_downloads("s-high").await.unwrap();
    for _ in 0..3 {
        repo.increment_downloads("s-mid").await.unwrap();
    }
    repo.increment_downloads("s-high").await.unwrap(); // s-high = 2, s-mid = 3

    let trending = repo.get_trending(3).await.expect("get_trending failed");
    assert_eq!(trending[0].id, "s-mid"); // 3 downloads
    assert_eq!(trending[1].id, "s-high"); // 2 downloads
    assert_eq!(trending[2].id, "s-low"); // 0 downloads
}

#[tokio::test]
async fn script_get_featured_filters_by_rating_and_downloads() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await;
    create_script(&repo, "s-2", "Utilities", true, "B").await;
    create_script(&repo, "s-3", "Utilities", true, "C").await;

    // Only s-1 meets both thresholds (rating >= 4.0 AND downloads >= 50).
    repo.update_stats("s-1", 4.5, 1).await.unwrap();
    repo.update_stats("s-2", 4.5, 1).await.unwrap();
    repo.update_stats("s-3", 1.0, 1).await.unwrap();
    for _ in 0..55 {
        repo.increment_downloads("s-1").await.unwrap();
    }
    for _ in 0..10 {
        repo.increment_downloads("s-2").await.unwrap(); // too few downloads
    }
    for _ in 0..55 {
        repo.increment_downloads("s-3").await.unwrap(); // too low rating
    }

    let featured = repo
        .get_featured(4.0, 50, 100)
        .await
        .expect("get_featured failed");
    assert_eq!(featured.len(), 1);
    assert_eq!(featured[0].id, "s-1");
}

#[tokio::test]
async fn script_get_compatible_matches_and_includes_null_compatibility() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await; // compatibility: >=1.0
    create_script(&repo, "s-2", "Utilities", true, "B").await; // compatibility: >=1.0

    // A script with NULL compatibility — must be included (backward-compatible).
    repo.create(
        "s-null",
        "slug-s-null",
        None,
        "Null compat",
        "desc",
        "Utilities",
        "bundle",
        None,
        None,
        None,
        "1.0.0",
        0.0,
        true,
        None, // NULL compatibility
        None,
        NOW,
    )
    .await
    .unwrap();

    let results = repo
        .get_compatible("1.0", 100)
        .await
        .expect("get_compatible failed");
    let ids: Vec<&str> = results.iter().map(|s| s.id.as_str()).collect();
    assert!(ids.contains(&"s-1"));
    assert!(ids.contains(&"s-2"));
    assert!(ids.contains(&"s-null")); // NULL compat included
}

#[tokio::test]
async fn script_get_marketplace_stats_aggregates_correctly() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await;
    create_script(&repo, "s-2", "Utilities", true, "B").await;
    create_script(&repo, "s-3", "Utilities", false, "C").await; // private — excluded

    repo.increment_downloads("s-1").await.unwrap();
    repo.increment_downloads("s-1").await.unwrap();
    repo.increment_downloads("s-2").await.unwrap();
    repo.update_stats("s-1", 4.0, 1).await.unwrap();
    repo.update_stats("s-2", 5.0, 1).await.unwrap();

    let (count, total_downloads, avg_rating) = repo
        .get_marketplace_stats()
        .await
        .expect("get_marketplace_stats failed");

    assert_eq!(count, 2); // 2 public
    assert_eq!(total_downloads, 3); // 2 + 1
    assert_eq!(avg_rating, 4.5); // (4.0 + 5.0) / 2
}

#[tokio::test]
async fn script_get_marketplace_stats_empty_returns_zeros() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    let (count, total_downloads, avg_rating) = repo
        .get_marketplace_stats()
        .await
        .expect("get_marketplace_stats failed");

    assert_eq!(count, 0);
    assert_eq!(total_downloads, 0);
    assert_eq!(avg_rating, 0.0);
}

#[tokio::test]
async fn script_search_by_query_matches_title() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "Token Swap").await;
    create_script(&repo, "s-2", "Finance", true, "Price Oracle").await;
    create_script(&repo, "s-3", "Utilities", false, "Token Private").await; // private — excluded

    let request = SearchRequest {
        query: Some("token".to_string()),
        ..Default::default()
    };
    let result = repo.search(&request).await.expect("search failed");

    assert_eq!(result.total, 1);
    assert_eq!(result.scripts.len(), 1);
    assert_eq!(result.scripts[0].id, "s-1");
}

#[tokio::test]
async fn script_search_with_category_filter() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    create_script(&repo, "s-1", "Utilities", true, "A").await;
    create_script(&repo, "s-2", "Finance", true, "B").await;

    let request = SearchRequest {
        category: Some("Finance".to_string()),
        ..Default::default()
    };
    let result = repo.search(&request).await.expect("search failed");
    assert_eq!(result.total, 1);
    assert_eq!(result.scripts[0].id, "s-2");
}

#[tokio::test]
async fn script_search_invalid_limit_returns_bad_request() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    let request = SearchRequest {
        limit: Some(0),
        ..Default::default()
    };
    let err = repo.search(&request).await.expect_err("should reject limit=0");
    assert_eq!(err.0, poem::http::StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn script_search_limit_over_100_returns_bad_request() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    let request = SearchRequest {
        limit: Some(101),
        ..Default::default()
    };
    let err = repo.search(&request).await.expect_err("should reject limit>100");
    assert_eq!(err.0, poem::http::StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn script_search_unsupported_sort_field_returns_bad_request() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    let request = SearchRequest {
        sort_by: Some("bogus".to_string()),
        ..Default::default()
    };
    let err = repo.search(&request).await.expect_err("should reject sort field");
    assert_eq!(err.0, poem::http::StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn script_search_bad_sort_order_returns_bad_request() {
    let pool = setup().await;
    let repo = ScriptRepository::new(pool);

    let request = SearchRequest {
        sort_order: Some("sideways".to_string()),
        ..Default::default()
    };
    let err = repo.search(&request).await.expect_err("should reject order");
    assert_eq!(err.0, poem::http::StatusCode::BAD_REQUEST);
}

// ===========================================================================
// ReviewRepository
// ===========================================================================

/// Creates a script row so the FK from reviews → scripts is satisfiable.
async fn create_script_for_reviews(pool: &SqlitePool) {
    sqlx::query(
        r#"INSERT INTO scripts (id, slug, title, description, category, bundle, version, price, is_public, created_at, updated_at)
           VALUES ('s-reviews', 'slug', 'Title', 'Desc', 'Utilities', 'bundle', '1.0.0', 0.0, 1, '2026-07-11T00:00:00Z', '2026-07-11T00:00:00Z')"#,
    )
    .execute(pool)
    .await
    .expect("failed to insert script for reviews");
}

#[tokio::test]
async fn review_create_and_find_by_script_ordered_desc() {
    let pool = setup().await;
    create_script_for_reviews(&pool).await;
    let repo = ReviewRepository::new(pool);

    repo.create("r-1", "s-reviews", "user-a", 5, Some("Great"), "2026-07-11T01:00:00Z")
        .await
        .expect("create failed");
    repo.create("r-2", "s-reviews", "user-b", 3, Some("OK"), "2026-07-11T02:00:00Z")
        .await
        .expect("create failed");
    repo.create("r-3", "s-reviews", "user-c", 1, None, "2026-07-11T03:00:00Z")
        .await
        .expect("create failed");

    let reviews = repo
        .find_by_script("s-reviews", 100, 0)
        .await
        .expect("find_by_script failed");
    assert_eq!(reviews.len(), 3);
    // DESC by created_at: r-3 (latest) first.
    assert_eq!(reviews[0].id, "r-3");
    assert_eq!(reviews[1].id, "r-2");
    assert_eq!(reviews[2].id, "r-1");
    // Verify a review with no comment.
    assert_eq!(reviews[0].comment, None);
    assert_eq!(reviews[0].rating, 1);
}

#[tokio::test]
async fn review_find_by_script_pagination() {
    let pool = setup().await;
    create_script_for_reviews(&pool).await;
    let repo = ReviewRepository::new(pool);

    for i in 1..=5 {
        repo.create(
            &format!("r-{i}"),
            "s-reviews",
            &format!("user-{i}"),
            4,
            None,
            &format!("2026-07-11T0{i}:00:00Z"),
        )
        .await
        .unwrap();
    }

    // Page 2 with limit=2, offset=2 (DESC order: r-5,r-4,r-3,r-2,r-1).
    let page = repo
        .find_by_script("s-reviews", 2, 2)
        .await
        .expect("find_by_script failed");
    assert_eq!(page.len(), 2);
    assert_eq!(page[0].id, "r-3");
    assert_eq!(page[1].id, "r-2");
}

#[tokio::test]
async fn review_find_by_script_empty_for_no_reviews() {
    let pool = setup().await;
    create_script_for_reviews(&pool).await;
    let repo = ReviewRepository::new(pool);

    let reviews = repo
        .find_by_script("s-reviews", 100, 0)
        .await
        .expect("find_by_script failed");
    assert!(reviews.is_empty());
}

#[tokio::test]
async fn review_count_by_script() {
    let pool = setup().await;
    create_script_for_reviews(&pool).await;
    let repo = ReviewRepository::new(pool);

    repo.create("r-1", "s-reviews", "user-a", 5, None, NOW)
        .await
        .unwrap();
    repo.create("r-2", "s-reviews", "user-b", 4, None, NOW)
        .await
        .unwrap();

    assert_eq!(repo.count_by_script("s-reviews").await.unwrap(), 2);
    assert_eq!(repo.count_by_script("nope").await.unwrap(), 0);
}

#[tokio::test]
async fn review_count_by_script_and_user() {
    // W7-15: the UNIQUE(script_id, user_id) index enforces one review per user
    // per script — so this test seeds one review each for user-a/user-b (the
    // pre-W7-15 second `user-a` insert is now impossible by design).
    let pool = setup().await;
    create_script_for_reviews(&pool).await;
    let repo = ReviewRepository::new(pool);

    repo.create("r-1", "s-reviews", "user-a", 5, None, NOW)
        .await
        .unwrap();
    repo.create("r-3", "s-reviews", "user-b", 3, None, NOW)
        .await
        .unwrap();

    assert_eq!(
        repo.count_by_script_and_user("s-reviews", "user-a")
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        repo.count_by_script_and_user("s-reviews", "user-b")
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        repo.count_by_script_and_user("s-reviews", "user-c")
            .await
            .unwrap(),
        0
    );
}

#[tokio::test]
async fn review_get_average_rating() {
    let pool = setup().await;
    create_script_for_reviews(&pool).await;
    let repo = ReviewRepository::new(pool);

    repo.create("r-1", "s-reviews", "user-a", 5, None, NOW)
        .await
        .unwrap();
    repo.create("r-2", "s-reviews", "user-b", 4, None, NOW)
        .await
        .unwrap();
    repo.create("r-3", "s-reviews", "user-c", 3, None, NOW)
        .await
        .unwrap();

    let avg = repo
        .get_average_rating("s-reviews")
        .await
        .expect("get_average_rating failed")
        .expect("should have a value");
    assert_eq!(avg, 4.0); // (5 + 4 + 3) / 3
}

#[tokio::test]
async fn review_get_average_rating_returns_none_when_no_reviews() {
    let pool = setup().await;
    create_script_for_reviews(&pool).await;
    let repo = ReviewRepository::new(pool);

    let avg = repo
        .get_average_rating("s-reviews")
        .await
        .expect("get_average_rating failed");
    assert!(avg.is_none(), "AVG over zero rows should be NULL");
}
