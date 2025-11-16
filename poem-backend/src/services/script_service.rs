use crate::models::{CreateScriptRequest, Script, UpdateScriptRequest};
use crate::repositories::ScriptRepository;
use chrono::Utc;
use sqlx::SqlitePool;

pub struct ScriptService {
    repo: ScriptRepository,
}

impl ScriptService {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            repo: ScriptRepository::new(pool),
        }
    }

    pub async fn create_script(&self, req: CreateScriptRequest) -> Result<Script, sqlx::Error> {
        let script_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();
        let version = req.version.as_deref().unwrap_or("1.0.0");
        let price = req.price.unwrap_or(0.0);
        let is_public = resolve_script_visibility(req.is_public);
        let tags_json = req
            .tags
            .map(|tags| serde_json::to_string(&tags).unwrap_or_default());

        self.repo
            .create(
                &script_id,
                &req.title,
                &req.description,
                &req.category,
                &req.lua_source,
                &req.author_name,
                req.author_id.as_deref().unwrap_or(""),
                req.author_principal.as_deref(),
                req.author_public_key.as_deref(),
                req.signature.as_deref(),
                version,
                price,
                is_public,
                req.compatibility.as_deref(),
                tags_json.as_deref(),
                &now,
            )
            .await?;

        self.repo
            .find_by_id(&script_id)
            .await?
            .ok_or_else(|| sqlx::Error::RowNotFound)
    }

    pub async fn update_script(
        &self,
        script_id: &str,
        req: UpdateScriptRequest,
    ) -> Result<Script, sqlx::Error> {
        let now = Utc::now().to_rfc3339();
        let tags_json = req
            .tags
            .map(|tags| serde_json::to_string(&tags).unwrap_or_default());

        self.repo
            .update(
                script_id,
                req.title.as_deref(),
                req.description.as_deref(),
                req.category.as_deref(),
                req.lua_source.as_deref(),
                req.version.as_deref(),
                req.price,
                req.is_public,
                tags_json.as_deref(),
                &now,
            )
            .await?;

        self.repo
            .find_by_id(script_id)
            .await?
            .ok_or_else(|| sqlx::Error::RowNotFound)
    }

    pub async fn delete_script(&self, script_id: &str) -> Result<(), sqlx::Error> {
        self.repo.delete(script_id).await
    }

    pub async fn publish_script(&self, script_id: &str) -> Result<Script, sqlx::Error> {
        let now = Utc::now().to_rfc3339();
        self.repo.publish(script_id, &now).await?;

        self.repo
            .find_by_id(script_id)
            .await?
            .ok_or_else(|| sqlx::Error::RowNotFound)
    }

    pub async fn get_script(&self, script_id: &str) -> Result<Option<Script>, sqlx::Error> {
        self.repo.find_by_id(script_id).await
    }

    pub async fn check_script_exists(&self, script_id: &str) -> Result<bool, sqlx::Error> {
        let count = self.repo.count_by_id(script_id).await?;
        Ok(count > 0)
    }

    pub async fn get_scripts(
        &self,
        limit: i32,
        offset: i32,
        category: Option<String>,
        include_private: bool,
    ) -> Result<(Vec<Script>, i64), sqlx::Error> {
        let scripts = self
            .repo
            .find_all(limit, offset, category, include_private)
            .await?;
        let total = self.repo.count_public().await?;
        Ok((scripts, total))
    }

    pub async fn search_scripts(
        &self,
        request: &crate::models::SearchRequest,
    ) -> Result<crate::models::SearchResultPayload, (poem::http::StatusCode, String)> {
        self.repo.search(request).await
    }

    pub async fn get_scripts_by_category(
        &self,
        category: &str,
        limit: i32,
    ) -> Result<Vec<Script>, sqlx::Error> {
        self.repo.get_by_category(category, limit).await
    }

    pub async fn get_trending(&self, limit: i32) -> Result<Vec<Script>, sqlx::Error> {
        self.repo.get_trending(limit).await
    }

    pub async fn get_featured(
        &self,
        min_rating: f64,
        min_downloads: i32,
        limit: i32,
    ) -> Result<Vec<Script>, sqlx::Error> {
        self.repo
            .get_featured(min_rating, min_downloads, limit)
            .await
    }

    pub async fn get_compatible(
        &self,
        compatibility: &str,
        limit: i32,
    ) -> Result<Vec<Script>, sqlx::Error> {
        self.repo.get_compatible(compatibility, limit).await
    }

    pub async fn get_marketplace_stats(&self) -> Result<(i64, i64, f64), sqlx::Error> {
        self.repo.get_marketplace_stats().await
    }

    pub async fn get_scripts_count(&self) -> Result<i64, sqlx::Error> {
        self.repo.count_public().await
    }

    pub async fn increment_downloads(&self, script_id: &str) -> Result<(), String> {
        self.repo
            .increment_downloads(script_id)
            .await
            .map_err(|e| format!("Failed to increment downloads: {}", e))
    }
}

fn resolve_script_visibility(is_public: Option<bool>) -> bool {
    is_public.unwrap_or(true)
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

    fn create_test_script_request() -> CreateScriptRequest {
        CreateScriptRequest {
            title: "Test Script".to_string(),
            description: "Test Description".to_string(),
            category: "utility".to_string(),
            lua_source: "print('hello')".to_string(),
            author_name: "Test Author".to_string(),
            author_id: Some("test-author-id".to_string()),
            author_principal: Some("test-principal".to_string()),
            author_public_key: Some("test-public-key".to_string()),
            upload_signature: None,
            signature: Some("test-signature".to_string()),
            timestamp: None,
            version: None,
            price: None,
            is_public: None,
            compatibility: None,
            tags: None,
            action: None,
        }
    }

    #[test]
    fn resolve_visibility_defaults_to_public() {
        assert!(resolve_script_visibility(None));
    }

    #[test]
    fn resolve_visibility_preserves_private_flag() {
        assert!(!resolve_script_visibility(Some(false)));
        assert!(resolve_script_visibility(Some(true)));
    }

    #[tokio::test]
    async fn test_create_script_with_defaults() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);
        let req = create_test_script_request();

        let result = service.create_script(req).await;
        assert!(result.is_ok());

        let script = result.unwrap();
        assert_eq!(script.title, "Test Script");
        assert_eq!(script.version, "1.0.0"); // Default version
        assert_eq!(script.price, 0.0); // Default price
        assert!(script.is_public); // Default visibility is public
        assert_eq!(script.downloads, 0);
        assert_eq!(script.rating, 0.0);
        assert_eq!(script.review_count, 0);
    }

    #[tokio::test]
    async fn test_create_script_with_custom_values() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);
        let mut req = create_test_script_request();
        req.version = Some("2.0.0".to_string());
        req.price = Some(9.99);
        req.is_public = Some(false);
        req.tags = Some(vec!["tag1".to_string(), "tag2".to_string()]);
        req.compatibility = Some("v1.0".to_string());

        let result = service.create_script(req).await;
        assert!(result.is_ok());

        let script = result.unwrap();
        assert_eq!(script.version, "2.0.0");
        assert_eq!(script.price, 9.99);
        assert!(!script.is_public); // Private script
        assert!(script.tags.is_some());
        assert_eq!(script.compatibility, Some("v1.0".to_string()));
    }

    #[tokio::test]
    async fn test_update_script_partial_update() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        // Create script first
        let create_req = create_test_script_request();
        let created = service.create_script(create_req).await.unwrap();

        // Update only title and description
        let update_req = UpdateScriptRequest {
            title: Some("Updated Title".to_string()),
            description: Some("Updated Description".to_string()),
            category: None,
            lua_source: None,
            version: None,
            price: None,
            is_public: None,
            tags: None,
            signature: None,
            timestamp: None,
            script_id: None,
            author_principal: None,
            author_public_key: None,
            action: None,
        };

        let result = service.update_script(&created.id, update_req).await;
        assert!(result.is_ok());

        let updated = result.unwrap();
        assert_eq!(updated.title, "Updated Title");
        assert_eq!(updated.description, "Updated Description");
        assert_eq!(updated.category, "utility"); // Unchanged
        assert_eq!(updated.lua_source, "print('hello')"); // Unchanged
    }

    #[tokio::test]
    async fn test_update_nonexistent_script_fails() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        let update_req = UpdateScriptRequest {
            title: Some("Updated Title".to_string()),
            description: None,
            category: None,
            lua_source: None,
            version: None,
            price: None,
            is_public: None,
            tags: None,
            signature: None,
            timestamp: None,
            script_id: None,
            author_principal: None,
            author_public_key: None,
            action: None,
        };

        let result = service.update_script("nonexistent-id", update_req).await;
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), sqlx::Error::RowNotFound));
    }

    #[tokio::test]
    async fn test_delete_script() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        // Create script first
        let create_req = create_test_script_request();
        let created = service.create_script(create_req).await.unwrap();

        // Delete it
        let result = service.delete_script(&created.id).await;
        assert!(result.is_ok());

        // Verify it's gone
        let get_result = service.get_script(&created.id).await.unwrap();
        assert!(get_result.is_none());
    }

    #[tokio::test]
    async fn test_publish_script_makes_public() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        // Create private script
        let mut create_req = create_test_script_request();
        create_req.is_public = Some(false);
        let created = service.create_script(create_req).await.unwrap();
        assert!(!created.is_public);

        // Publish it
        let result = service.publish_script(&created.id).await;
        assert!(result.is_ok());

        let published = result.unwrap();
        assert!(published.is_public); // Now public
    }

    #[tokio::test]
    async fn test_publish_nonexistent_script_fails() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        let result = service.publish_script("nonexistent-id").await;
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), sqlx::Error::RowNotFound));
    }

    #[tokio::test]
    async fn test_get_script_by_id() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        let create_req = create_test_script_request();
        let created = service.create_script(create_req).await.unwrap();

        let result = service.get_script(&created.id).await;
        assert!(result.is_ok());

        let script = result.unwrap();
        assert!(script.is_some());
        assert_eq!(script.unwrap().id, created.id);
    }

    #[tokio::test]
    async fn test_get_nonexistent_script_returns_none() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        let result = service.get_script("nonexistent-id").await;
        assert!(result.is_ok());
        assert!(result.unwrap().is_none());
    }

    #[tokio::test]
    async fn test_check_script_exists() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        let create_req = create_test_script_request();
        let created = service.create_script(create_req).await.unwrap();

        let exists = service.check_script_exists(&created.id).await.unwrap();
        assert!(exists);

        let not_exists = service.check_script_exists("nonexistent-id").await.unwrap();
        assert!(!not_exists);
    }

    #[tokio::test]
    async fn test_get_scripts_pagination() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        // Create 3 scripts
        for i in 1..=3 {
            let mut req = create_test_script_request();
            req.title = format!("Script {}", i);
            service.create_script(req).await.unwrap();
        }

        // Get first 2
        let (scripts, total) = service.get_scripts(2, 0, None, false).await.unwrap();
        assert_eq!(scripts.len(), 2);
        assert_eq!(total, 3);

        // Get next 2 (should only get 1)
        let (scripts, _) = service.get_scripts(2, 2, None, false).await.unwrap();
        assert_eq!(scripts.len(), 1);
    }

    #[tokio::test]
    async fn test_get_scripts_filters_private() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        // Create 1 public and 1 private script
        let mut req1 = create_test_script_request();
        req1.is_public = Some(true);
        service.create_script(req1).await.unwrap();

        let mut req2 = create_test_script_request();
        req2.is_public = Some(false);
        service.create_script(req2).await.unwrap();

        // Get scripts without including private
        let (scripts, _) = service.get_scripts(10, 0, None, false).await.unwrap();
        assert_eq!(scripts.len(), 1); // Only public script

        // Get scripts including private
        let (scripts, _) = service.get_scripts(10, 0, None, true).await.unwrap();
        assert_eq!(scripts.len(), 2); // Both scripts
    }

    #[tokio::test]
    async fn test_get_scripts_by_category() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        let mut req1 = create_test_script_request();
        req1.category = "utility".to_string();
        service.create_script(req1).await.unwrap();

        let mut req2 = create_test_script_request();
        req2.category = "game".to_string();
        service.create_script(req2).await.unwrap();

        let scripts = service.get_scripts_by_category("utility", 10).await.unwrap();
        assert_eq!(scripts.len(), 1);
        assert_eq!(scripts[0].category, "utility");
    }

    #[tokio::test]
    async fn test_get_scripts_count() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        // Initially 0
        let count = service.get_scripts_count().await.unwrap();
        assert_eq!(count, 0);

        // Create 2 public scripts
        let req1 = create_test_script_request();
        service.create_script(req1).await.unwrap();

        let req2 = create_test_script_request();
        service.create_script(req2).await.unwrap();

        let count = service.get_scripts_count().await.unwrap();
        assert_eq!(count, 2);
    }

    #[tokio::test]
    async fn test_increment_downloads_existing_script() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        let req = create_test_script_request();
        let created = service.create_script(req).await.unwrap();
        assert_eq!(created.downloads, 0); // Initial downloads

        // Increment downloads
        let result = service.increment_downloads(&created.id).await;
        assert!(result.is_ok());

        // Verify downloads increased
        let script = service.get_script(&created.id).await.unwrap().unwrap();
        assert_eq!(script.downloads, 1);

        // Increment again
        service.increment_downloads(&created.id).await.unwrap();
        let script = service.get_script(&created.id).await.unwrap().unwrap();
        assert_eq!(script.downloads, 2);
    }

    #[tokio::test]
    async fn test_increment_downloads_nonexistent_script_succeeds_silently() {
        let pool = setup_test_db().await;
        let service = ScriptService::new(pool);

        // Note: SQLite UPDATE on nonexistent row succeeds (affects 0 rows but doesn't error)
        let result = service.increment_downloads("nonexistent-id").await;
        assert!(result.is_ok());
    }
}
