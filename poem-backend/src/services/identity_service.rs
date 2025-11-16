use crate::models::{IdentityProfile, UpsertIdentityProfileRequest};
use crate::repositories::IdentityRepository;
use chrono::Utc;
use sqlx::SqlitePool;

pub struct IdentityService {
    repo: IdentityRepository,
}

impl IdentityService {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            repo: IdentityRepository::new(pool),
        }
    }

    pub async fn upsert_profile(
        &self,
        req: UpsertIdentityProfileRequest,
    ) -> Result<IdentityProfile, String> {
        // Validate email if provided
        if let Some(ref email) = req.contact_email {
            if !email.is_empty() && !email.contains('@') {
                return Err("Invalid email format".to_string());
            }
        }

        let profile_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();
        let metadata = req.metadata.map(|v| v.to_string());

        self.repo
            .upsert(
                &profile_id,
                &req.principal,
                &req.display_name,
                req.username.as_deref(),
                req.contact_email.as_deref(),
                req.contact_telegram.as_deref(),
                req.contact_twitter.as_deref(),
                req.contact_discord.as_deref(),
                req.website_url.as_deref(),
                req.bio.as_deref(),
                metadata.as_deref(),
                &now,
            )
            .await
            .map_err(|e| format!("Failed to upsert profile: {}", e))?;

        self.get_profile(&req.principal)
            .await?
            .ok_or_else(|| "Failed to retrieve created profile".to_string())
    }

    pub async fn get_profile(&self, principal: &str) -> Result<Option<IdentityProfile>, String> {
        self.repo
            .find_by_principal(principal)
            .await
            .map_err(|e| format!("Failed to fetch profile: {}", e))
    }
}
