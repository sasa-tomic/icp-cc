use crate::models::IdentityProfile;
use sqlx::SqlitePool;

pub struct UpsertIdentityParams<'a> {
    pub id: &'a str,
    pub principal: &'a str,
    pub display_name: &'a str,
    pub username: Option<&'a str>,
    pub contact_email: Option<&'a str>,
    pub contact_telegram: Option<&'a str>,
    pub contact_twitter: Option<&'a str>,
    pub contact_discord: Option<&'a str>,
    pub website_url: Option<&'a str>,
    pub bio: Option<&'a str>,
    pub metadata: Option<&'a str>,
    pub timestamp: &'a str,
}

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

    pub async fn upsert(&self, params: UpsertIdentityParams<'_>) -> Result<(), sqlx::Error> {
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
        .bind(params.id)
        .bind(params.principal)
        .bind(params.display_name)
        .bind(params.username)
        .bind(params.contact_email)
        .bind(params.contact_telegram)
        .bind(params.contact_twitter)
        .bind(params.contact_discord)
        .bind(params.website_url)
        .bind(params.bio)
        .bind(params.metadata)
        .bind(params.timestamp)
        .bind(params.timestamp)
        .execute(&self.pool)
        .await?;
        Ok(())
    }
}
