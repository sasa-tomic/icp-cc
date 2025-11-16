use crate::models::IdentityProfile;
use sqlx::SqlitePool;

pub struct IdentityRepository {
    pool: SqlitePool,
}

impl IdentityRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn find_by_principal(
        &self,
        principal: &str,
    ) -> Result<Option<IdentityProfile>, sqlx::Error> {
        sqlx::query_as::<_, IdentityProfile>(
            "SELECT id, principal, display_name, username, contact_email, contact_telegram,
                    contact_twitter, contact_discord, website_url, bio, metadata, created_at, updated_at
             FROM identity_profiles WHERE principal = ?1"
        )
        .bind(principal)
        .fetch_optional(&self.pool)
        .await
    }

    pub async fn upsert(
        &self,
        id: &str,
        principal: &str,
        display_name: &str,
        username: Option<&str>,
        contact_email: Option<&str>,
        contact_telegram: Option<&str>,
        contact_twitter: Option<&str>,
        contact_discord: Option<&str>,
        website_url: Option<&str>,
        bio: Option<&str>,
        metadata: Option<&str>,
        timestamp: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO identity_profiles (
                id, principal, display_name, username, contact_email, contact_telegram,
                contact_twitter, contact_discord, website_url, bio, metadata, created_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
            ON CONFLICT(principal) DO UPDATE SET
                display_name = excluded.display_name,
                username = excluded.username,
                contact_email = excluded.contact_email,
                contact_telegram = excluded.contact_telegram,
                contact_twitter = excluded.contact_twitter,
                contact_discord = excluded.contact_discord,
                website_url = excluded.website_url,
                bio = excluded.bio,
                metadata = excluded.metadata,
                updated_at = excluded.updated_at
            "#,
        )
        .bind(id)
        .bind(principal)
        .bind(display_name)
        .bind(username)
        .bind(contact_email)
        .bind(contact_telegram)
        .bind(contact_twitter)
        .bind(contact_discord)
        .bind(website_url)
        .bind(bio)
        .bind(metadata)
        .bind(timestamp)
        .bind(timestamp)
        .execute(&self.pool)
        .await?;
        Ok(())
    }
}
