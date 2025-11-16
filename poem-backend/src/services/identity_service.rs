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

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::sqlite::SqlitePoolOptions;

    async fn setup_test_db() -> SqlitePool {
        let pool = SqlitePoolOptions::new()
            .connect(":memory:")
            .await
            .unwrap();
        crate::db::initialize_database(&pool).await;
        pool
    }

    fn create_test_profile_request(principal: &str) -> UpsertIdentityProfileRequest {
        UpsertIdentityProfileRequest {
            principal: principal.to_string(),
            display_name: "Test User".to_string(),
            username: Some("testuser".to_string()),
            contact_email: Some("test@example.com".to_string()),
            contact_telegram: Some("@testuser".to_string()),
            contact_twitter: Some("@testuser".to_string()),
            contact_discord: Some("testuser#1234".to_string()),
            website_url: Some("https://example.com".to_string()),
            bio: Some("Test bio".to_string()),
            metadata: Some(serde_json::json!({"key": "value"})),
        }
    }

    #[tokio::test]
    async fn test_upsert_profile_creates_new_profile() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        let req = create_test_profile_request("principal-1");
        let result = service.upsert_profile(req).await;

        assert!(result.is_ok());
        let profile = result.unwrap();
        assert_eq!(profile.principal, "principal-1");
        assert_eq!(profile.display_name, "Test User");
        assert_eq!(profile.username, Some("testuser".to_string()));
        assert_eq!(profile.contact_email, Some("test@example.com".to_string()));
        assert_eq!(profile.contact_telegram, Some("@testuser".to_string()));
        assert_eq!(profile.contact_twitter, Some("@testuser".to_string()));
        assert_eq!(profile.contact_discord, Some("testuser#1234".to_string()));
        assert_eq!(profile.website_url, Some("https://example.com".to_string()));
        assert_eq!(profile.bio, Some("Test bio".to_string()));
    }

    #[tokio::test]
    async fn test_upsert_profile_updates_existing_profile() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        // Create initial profile
        let req1 = create_test_profile_request("principal-1");
        let profile1 = service.upsert_profile(req1).await.unwrap();

        // Update profile with same principal
        let req2 = UpsertIdentityProfileRequest {
            principal: "principal-1".to_string(),
            display_name: "Updated User".to_string(),
            username: Some("updateduser".to_string()),
            contact_email: Some("updated@example.com".to_string()),
            contact_telegram: None,
            contact_twitter: None,
            contact_discord: None,
            website_url: None,
            bio: Some("Updated bio".to_string()),
            metadata: None,
        };
        let profile2 = service.upsert_profile(req2).await.unwrap();

        // Should be same ID (upsert)
        assert_eq!(profile1.principal, profile2.principal);
        // But updated fields
        assert_eq!(profile2.display_name, "Updated User");
        assert_eq!(profile2.username, Some("updateduser".to_string()));
        assert_eq!(profile2.contact_email, Some("updated@example.com".to_string()));
        assert_eq!(profile2.bio, Some("Updated bio".to_string()));
    }

    #[tokio::test]
    async fn test_upsert_profile_validates_email_format() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        let mut req = create_test_profile_request("principal-1");
        req.contact_email = Some("invalid-email".to_string()); // No @ symbol

        let result = service.upsert_profile(req).await;

        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Invalid email format");
    }

    #[tokio::test]
    async fn test_upsert_profile_accepts_valid_emails() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        let valid_emails = vec![
            "user@example.com",
            "test.user@example.co.uk",
            "user+tag@example.com",
        ];

        for (i, email) in valid_emails.iter().enumerate() {
            let mut req = create_test_profile_request(&format!("principal-{}", i));
            req.contact_email = Some(email.to_string());

            let result = service.upsert_profile(req).await;
            assert!(result.is_ok(), "Email {} should be valid", email);
        }
    }

    #[tokio::test]
    async fn test_upsert_profile_accepts_empty_email() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        let mut req = create_test_profile_request("principal-1");
        req.contact_email = Some("".to_string());

        let result = service.upsert_profile(req).await;
        assert!(result.is_ok()); // Empty email is allowed
    }

    #[tokio::test]
    async fn test_upsert_profile_accepts_no_email() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        let mut req = create_test_profile_request("principal-1");
        req.contact_email = None;

        let result = service.upsert_profile(req).await;
        assert!(result.is_ok());

        let profile = result.unwrap();
        assert_eq!(profile.contact_email, None);
    }

    #[tokio::test]
    async fn test_upsert_profile_minimal_fields() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        let req = UpsertIdentityProfileRequest {
            principal: "principal-minimal".to_string(),
            display_name: "Minimal User".to_string(),
            username: None,
            contact_email: None,
            contact_telegram: None,
            contact_twitter: None,
            contact_discord: None,
            website_url: None,
            bio: None,
            metadata: None,
        };

        let result = service.upsert_profile(req).await;
        assert!(result.is_ok());

        let profile = result.unwrap();
        assert_eq!(profile.principal, "principal-minimal");
        assert_eq!(profile.display_name, "Minimal User");
        assert_eq!(profile.username, None);
        assert_eq!(profile.contact_email, None);
    }

    #[tokio::test]
    async fn test_upsert_profile_with_metadata() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        let metadata = serde_json::json!({
            "theme": "dark",
            "notifications": true,
            "preferences": {
                "language": "en",
                "timezone": "UTC"
            }
        });

        let req = UpsertIdentityProfileRequest {
            principal: "principal-1".to_string(),
            display_name: "Test User".to_string(),
            username: None,
            contact_email: None,
            contact_telegram: None,
            contact_twitter: None,
            contact_discord: None,
            website_url: None,
            bio: None,
            metadata: Some(metadata),
        };

        let result = service.upsert_profile(req).await;
        assert!(result.is_ok());

        let profile = result.unwrap();
        assert!(profile.metadata.is_some());
    }

    #[tokio::test]
    async fn test_get_profile_existing() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        // Create a profile first
        let req = create_test_profile_request("principal-1");
        service.upsert_profile(req).await.unwrap();

        // Get the profile
        let result = service.get_profile("principal-1").await;
        assert!(result.is_ok());

        let profile = result.unwrap();
        assert!(profile.is_some());
        assert_eq!(profile.unwrap().principal, "principal-1");
    }

    #[tokio::test]
    async fn test_get_profile_nonexistent() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        let result = service.get_profile("nonexistent-principal").await;
        assert!(result.is_ok());
        assert!(result.unwrap().is_none());
    }

    #[tokio::test]
    async fn test_get_profile_returns_latest_version() {
        let pool = setup_test_db().await;
        let service = IdentityService::new(pool);

        // Create initial profile
        let req1 = create_test_profile_request("principal-1");
        service.upsert_profile(req1).await.unwrap();

        // Update it
        let mut req2 = create_test_profile_request("principal-1");
        req2.display_name = "Updated Name".to_string();
        service.upsert_profile(req2).await.unwrap();

        // Get profile should return updated version
        let profile = service
            .get_profile("principal-1")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(profile.display_name, "Updated Name");
    }
}
