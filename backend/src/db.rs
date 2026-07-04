use sqlx::SqlitePool;
pub async fn initialize_database(pool: &SqlitePool) {
    // Account Profiles System (username-based accounts with multiple keys)
    // MUST be created before scripts table due to foreign key constraint
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS accounts (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            display_name TEXT NOT NULL,
            contact_email TEXT,
            contact_telegram TEXT,
            contact_twitter TEXT,
            contact_discord TEXT,
            website_url TEXT,
            bio TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create accounts table");

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_accounts_username ON accounts(username)")
        .execute(pool)
        .await
        .expect("Failed to create accounts username index");

    let account_migrations = [
        (
            "display_name",
            "ALTER TABLE accounts ADD COLUMN display_name TEXT NOT NULL DEFAULT ''",
        ),
        (
            "contact_email",
            "ALTER TABLE accounts ADD COLUMN contact_email TEXT",
        ),
        (
            "contact_telegram",
            "ALTER TABLE accounts ADD COLUMN contact_telegram TEXT",
        ),
        (
            "contact_twitter",
            "ALTER TABLE accounts ADD COLUMN contact_twitter TEXT",
        ),
        (
            "contact_discord",
            "ALTER TABLE accounts ADD COLUMN contact_discord TEXT",
        ),
        (
            "website_url",
            "ALTER TABLE accounts ADD COLUMN website_url TEXT",
        ),
        ("bio", "ALTER TABLE accounts ADD COLUMN bio TEXT"),
    ];

    for (column_name, migration_sql) in account_migrations {
        if let Err(e) = sqlx::query(migration_sql).execute(pool).await {
            tracing::debug!(
                "Migration skipped for accounts column '{}' (likely already exists): {}",
                column_name,
                e
            );
        }
    }

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS account_public_keys (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            public_key TEXT UNIQUE NOT NULL,
            ic_principal TEXT UNIQUE NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            added_at TEXT NOT NULL,
            disabled_at TEXT,
            disabled_by_key_id TEXT,
            FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
            FOREIGN KEY (disabled_by_key_id) REFERENCES account_public_keys(id)
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create account_public_keys table");

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_keys_account ON account_public_keys(account_id)")
        .execute(pool)
        .await
        .expect("Failed to create keys account index");

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_keys_principal ON account_public_keys(ic_principal)",
    )
    .execute(pool)
    .await
    .expect("Failed to create keys principal index");

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_keys_active ON account_public_keys(account_id, is_active)",
    )
    .execute(pool)
    .await
    .expect("Failed to create keys active index");

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS signature_audit (
            id TEXT PRIMARY KEY,
            account_id TEXT,
            action TEXT NOT NULL,
            payload TEXT NOT NULL,
            signature TEXT NOT NULL,
            public_key TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            nonce TEXT NOT NULL,
            is_admin_action INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            FOREIGN KEY (account_id) REFERENCES accounts(id)
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create signature_audit table");

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_audit_nonce_time ON signature_audit(nonce, created_at)",
    )
    .execute(pool)
    .await
    .expect("Failed to create audit nonce_time index");

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_audit_account ON signature_audit(account_id)")
        .execute(pool)
        .await
        .expect("Failed to create audit account index");

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_audit_created ON signature_audit(created_at)")
        .execute(pool)
        .await
        .expect("Failed to create audit created index");

    // Scripts table - depends on accounts table for owner_account_id foreign key
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS scripts (
            id TEXT PRIMARY KEY,
            slug TEXT NOT NULL,
            owner_account_id TEXT,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            category TEXT NOT NULL,
            tags TEXT,
            bundle TEXT NOT NULL,
            author_principal TEXT,
            author_public_key TEXT,
            upload_signature TEXT,
            canister_ids TEXT,
            icon_url TEXT,
            screenshots TEXT,
            version TEXT NOT NULL DEFAULT '1.0.0',
            compatibility TEXT,
            price REAL NOT NULL DEFAULT 0.0,
            is_public INTEGER NOT NULL DEFAULT 1,
            downloads INTEGER NOT NULL DEFAULT 0,
            rating REAL NOT NULL DEFAULT 0.0,
            review_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            FOREIGN KEY (owner_account_id) REFERENCES accounts(id)
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create scripts table");

    // Migration: Add columns for backward compatibility with older databases
    // These columns are now in the CREATE TABLE statement above, so failures are expected for new databases
    let migrations = [
        ("tags", "ALTER TABLE scripts ADD COLUMN tags TEXT"),
        (
            "author_principal",
            "ALTER TABLE scripts ADD COLUMN author_principal TEXT",
        ),
        (
            "author_public_key",
            "ALTER TABLE scripts ADD COLUMN author_public_key TEXT",
        ),
        (
            "upload_signature",
            "ALTER TABLE scripts ADD COLUMN upload_signature TEXT",
        ),
        (
            "canister_ids",
            "ALTER TABLE scripts ADD COLUMN canister_ids TEXT",
        ),
        ("icon_url", "ALTER TABLE scripts ADD COLUMN icon_url TEXT"),
        (
            "screenshots",
            "ALTER TABLE scripts ADD COLUMN screenshots TEXT",
        ),
        (
            "compatibility",
            "ALTER TABLE scripts ADD COLUMN compatibility TEXT",
        ),
        (
            "slug",
            "ALTER TABLE scripts ADD COLUMN slug TEXT NOT NULL DEFAULT ''",
        ),
        (
            "owner_account_id",
            "ALTER TABLE scripts ADD COLUMN owner_account_id TEXT",
        ),
        (
            "deleted_at",
            "ALTER TABLE scripts ADD COLUMN deleted_at TEXT",
        ),
    ];

    for (column_name, migration_sql) in migrations {
        if let Err(e) = sqlx::query(migration_sql).execute(pool).await {
            tracing::debug!(
                "Migration skipped for column '{}' (likely already exists): {}",
                column_name,
                e
            );
        }
    }

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_scripts_slug ON scripts(slug)")
        .execute(pool)
        .await
        .expect("Failed to create scripts slug index");

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_scripts_owner_account_id ON scripts(owner_account_id)",
    )
    .execute(pool)
    .await
    .expect("Failed to create scripts owner_account_id index");

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS reviews (
            id TEXT PRIMARY KEY,
            script_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
            comment TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create reviews table");

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_reviews_script_id ON reviews(script_id)")
        .execute(pool)
        .await
        .expect("Failed to create reviews index");

    // Keypair Profiles System (separate from account profiles)
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS keypair_profiles (
            id TEXT PRIMARY KEY,
            principal TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            username TEXT,
            contact_email TEXT,
            contact_telegram TEXT,
            contact_twitter TEXT,
            contact_discord TEXT,
            website_url TEXT,
            bio TEXT,
            metadata TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create keypair_profiles table");

    sqlx::query(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_keypair_profiles_principal ON keypair_profiles(principal)",
    )
    .execute(pool)
    .await
    .expect("Failed to create keypair_profiles index");

    // Passkeys table for WebAuthn credentials
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS passkeys (
            id TEXT PRIMARY KEY,
            user_principal TEXT NOT NULL,
            credential_id BLOB NOT NULL UNIQUE,
            public_key BLOB NOT NULL,
            counter INTEGER NOT NULL DEFAULT 0,
            device_name TEXT,
            device_type TEXT,
            created_at TEXT NOT NULL,
            last_used_at TEXT,
            FOREIGN KEY (user_principal) REFERENCES keypair_profiles(principal) ON DELETE CASCADE
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create passkeys table");

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_passkeys_user_principal ON passkeys(user_principal)",
    )
    .execute(pool)
    .await
    .expect("Failed to create passkeys user_principal index");

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_passkeys_credential_id ON passkeys(credential_id)")
        .execute(pool)
        .await
        .expect("Failed to create passkeys credential_id index");

    // -----------------------------------------------------------------------
    // Legacy-column migration: rename `user_principal` → `account_id` on
    // `recovery_codes` / `user_vaults` for pre-A-4 dev DBs.
    //
    // This MUST run BEFORE the `CREATE TABLE` / `CREATE INDEX` statements
    // below that reference `account_id`: on a stale dev DB both tables already
    // exist (so `CREATE TABLE IF NOT EXISTS` is a no-op) but still carry the
    // old `user_principal` column, and the subsequent
    // `CREATE INDEX ... (account_id)` would panic with "no such column:
    // account_id" before the rename ever ran — exactly the A-4 W4 follow-up
    // bug this block fixes.
    //
    // Idempotency is enforced structurally, NOT by silencing errors: we probe
    // `pragma_table_info(<table>)` and only issue `RENAME COLUMN` when a
    // `user_principal` column is actually present. A fresh DB (table absent →
    // pragma returns no rows) and an already-migrated DB (column is
    // `account_id`) both result in a clearly-logged skip. Any other failure
    // is fatal (see `rename_legacy_user_principal_column`).
    // -----------------------------------------------------------------------
    rename_legacy_user_principal_column(pool, "recovery_codes").await;
    rename_legacy_user_principal_column(pool, "user_vaults").await;

    // Recovery codes table for vault password recovery.
    //
    // The owning account identifier is `account_id` (a keypair principal — see
    // the FK target). A previous scaffold of this table used the column name
    // `user_principal`; every query in `passkey_repository.rs` already used
    // `account_id`, so the prior DDL was unconditionally broken at runtime
    // (`no such column: account_id`). The schema is corrected here, and the
    // `rename_legacy_user_principal_column` migration above upgrades any
    // pre-existing dev DB in place (respects "never delete tables").
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS recovery_codes (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            code_hash TEXT NOT NULL,
            used INTEGER NOT NULL DEFAULT 0,
            used_at TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (account_id) REFERENCES keypair_profiles(principal) ON DELETE CASCADE
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create recovery_codes table");

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_recovery_codes_account_id ON recovery_codes(account_id)",
    )
    .execute(pool)
    .await
    .expect("Failed to create recovery_codes account_id index");

    // Opaque encrypted vault blob storage.
    //
    // As of A-4 W4 the backend performs NO vault cryptography: the client
    // derives the Argon2id key + AES-256-GCM ciphertext locally and POSTs the
    // resulting opaque blob (ciphertext + salt + nonce); the server stores and
    // returns those bytes verbatim. `account_id` is the keypair principal that
    // owns the vault.
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS user_vaults (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL UNIQUE,
            encrypted_data BLOB NOT NULL,
            salt BLOB NOT NULL,
            nonce BLOB NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (account_id) REFERENCES keypair_profiles(principal) ON DELETE CASCADE
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create user_vaults table");

    sqlx::query(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_user_vaults_account_id ON user_vaults(account_id)",
    )
    .execute(pool)
    .await
    .expect("Failed to create user_vaults account_id index");

    // Drop legacy indexes named after the old column so the renamed `*_account_id`
    // indexes above become the source of truth. `DROP INDEX IF EXISTS` is a
    // genuine no-op when the index is already gone — no error to swallow.
    sqlx::query("DROP INDEX IF EXISTS idx_recovery_codes_user_principal")
        .execute(pool)
        .await
        .expect("Failed to drop legacy recovery_codes user_principal index");
    sqlx::query("DROP INDEX IF EXISTS idx_user_vaults_principal")
        .execute(pool)
        .await
        .expect("Failed to drop legacy user_vaults principal index");
}

/// Idempotently rename the legacy `user_principal` column to `account_id` on
/// the given table, but only when `pragma_table_info` confirms the legacy
/// column is actually present.
///
/// This exists for pre-existing dev DBs created before A-4 W4 renamed the
/// owning-account column on `recovery_codes` / `user_vaults`. It MUST be
/// called before any `CREATE INDEX ... (account_id)` statement that references
/// the renamed column.
///
/// Nothing is silenced: when there is nothing to rename (fresh DB where the
/// table is absent → `pragma_table_info` returns no rows; or an
/// already-migrated DB where the column is `account_id`), we skip with an
/// explicit debug log. `pragma_table_info` failing is fatal — it is expected
/// to return an empty rowset for absent tables, so any error is genuinely
/// unexpected. A rename that fails after the column was confirmed present is
/// also fatal.
async fn rename_legacy_user_principal_column(pool: &SqlitePool, table: &str) {
    let column_names: Vec<String> = match sqlx::query_scalar(
        "SELECT name FROM pragma_table_info(?)",
    )
    .bind(table)
    .fetch_all(pool)
    .await
    {
        Ok(names) => names,
        Err(e) => panic!(
            "Legacy-column probe: pragma_table_info('{}') failed unexpectedly \
             (it should return an empty rowset for absent tables): {}",
            table, e
        ),
    };

    if !column_names.iter().any(|name| name == "user_principal") {
        tracing::debug!(
            "Legacy-column rename: no 'user_principal' column on '{}' \
             (fresh DB or already migrated); skipping",
            table
        );
        return;
    }

    let rename_sql = format!(
        "ALTER TABLE {} RENAME COLUMN user_principal TO account_id",
        table
    );
    match sqlx::query(&rename_sql).execute(pool).await {
        Ok(_) => tracing::info!(
            "Legacy-column rename: migrated '{}' column 'user_principal' → 'account_id'",
            table
        ),
        Err(e) => panic!(
            "Legacy-column rename on '{}' failed despite 'user_principal' being present \
             in pragma_table_info: {}",
            table, e
        ),
    }
}
