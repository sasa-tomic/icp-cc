use sqlx::SqlitePool;
pub async fn initialize_database(pool: &SqlitePool) {
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
            lua_source TEXT NOT NULL,
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
        ("author_id", "ALTER TABLE scripts ADD COLUMN author_id TEXT"),
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
        CREATE TABLE IF NOT EXISTS identity_profiles (
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
    .expect("Failed to create identity_profiles table");

    sqlx::query(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_identity_profiles_principal ON identity_profiles(principal)",
    )
    .execute(pool)
    .await
    .expect("Failed to create identity_profiles index");

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
            FOREIGN KEY (user_principal) REFERENCES identity_profiles(principal) ON DELETE CASCADE
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

    // Recovery codes table for vault password recovery
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS recovery_codes (
            id TEXT PRIMARY KEY,
            user_principal TEXT NOT NULL,
            code_hash TEXT NOT NULL,
            used INTEGER NOT NULL DEFAULT 0,
            used_at TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (user_principal) REFERENCES identity_profiles(principal) ON DELETE CASCADE
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create recovery_codes table");

    sqlx::query(
        "CREATE INDEX IF NOT EXISTS idx_recovery_codes_user_principal ON recovery_codes(user_principal)",
    )
    .execute(pool)
    .await
    .expect("Failed to create recovery_codes user_principal index");

    // Encrypted vault storage for user credentials
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS user_vaults (
            id TEXT PRIMARY KEY,
            user_principal TEXT NOT NULL UNIQUE,
            encrypted_data BLOB NOT NULL,
            salt BLOB NOT NULL,
            nonce BLOB NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (user_principal) REFERENCES identity_profiles(principal) ON DELETE CASCADE
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create user_vaults table");

    sqlx::query(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_user_vaults_principal ON user_vaults(user_principal)",
    )
    .execute(pool)
    .await
    .expect("Failed to create user_vaults principal index");

    // Account Profiles System (username-based accounts with multiple keys)
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

    tracing::info!("Database initialized successfully");
}
