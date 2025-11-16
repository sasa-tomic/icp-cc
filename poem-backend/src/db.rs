use sqlx::SqlitePool;
pub 
async fn initialize_database(pool: &SqlitePool) {
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS scripts (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            category TEXT NOT NULL,
            tags TEXT,
            lua_source TEXT NOT NULL,
            author_name TEXT NOT NULL,
            author_id TEXT NOT NULL,
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
            updated_at TEXT NOT NULL
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create scripts table");

    sqlx::query("ALTER TABLE scripts ADD COLUMN tags TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN author_id TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN author_principal TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN author_public_key TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN upload_signature TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN canister_ids TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN icon_url TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN screenshots TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN compatibility TEXT")
        .execute(pool)
        .await
        .ok();

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

    tracing::info!("Database initialized successfully");
}

