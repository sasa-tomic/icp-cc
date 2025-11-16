use crate::models::{CreateReviewRequest, Review};
use crate::repositories::{ReviewRepository, ScriptRepository};
use chrono::Utc;
use sqlx::SqlitePool;

pub struct ReviewService {
    review_repo: ReviewRepository,
    script_repo: ScriptRepository,
}

impl ReviewService {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            review_repo: ReviewRepository::new(pool.clone()),
            script_repo: ScriptRepository::new(pool),
        }
    }

    pub async fn create_review(
        &self,
        script_id: &str,
        req: CreateReviewRequest,
    ) -> Result<Review, String> {
        // Verify script exists
        let script_count = self
            .script_repo
            .count_by_id(script_id)
            .await
            .map_err(|e| format!("Failed to verify script: {}", e))?;

        if script_count == 0 {
            return Err("Script not found".to_string());
        }

        // Check if user already reviewed
        let existing_count = self
            .review_repo
            .count_by_script_and_user(script_id, &req.user_id)
            .await
            .map_err(|e| format!("Failed to check existing review: {}", e))?;

        if existing_count > 0 {
            return Err("User has already reviewed this script".to_string());
        }

        // Validate rating
        if req.rating < 1 || req.rating > 5 {
            return Err("Rating must be between 1 and 5".to_string());
        }

        // Create review
        let review_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().to_rfc3339();

        self.review_repo
            .create(
                &review_id,
                script_id,
                &req.user_id,
                req.rating,
                req.comment.as_deref(),
                &now,
            )
            .await
            .map_err(|e| format!("Failed to create review: {}", e))?;

        // Update script stats
        let avg_rating = self
            .review_repo
            .get_average_rating(script_id)
            .await
            .map_err(|e| format!("Failed to calculate avg rating: {}", e))?
            .unwrap_or(0.0);

        let review_count = self
            .review_repo
            .count_by_script(script_id)
            .await
            .map_err(|e| format!("Failed to count reviews: {}", e))?;

        self.script_repo
            .update_stats(script_id, avg_rating, review_count)
            .await
            .map_err(|e| format!("Failed to update script stats: {}", e))?;

        Ok(Review {
            id: review_id,
            script_id: script_id.to_string(),
            user_id: req.user_id,
            rating: req.rating,
            comment: req.comment,
            created_at: now.clone(),
            updated_at: now,
        })
    }

    pub async fn get_reviews(
        &self,
        script_id: &str,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Review>, i32), sqlx::Error> {
        let reviews = self
            .review_repo
            .find_by_script(script_id, limit, offset)
            .await?;
        let total = self.review_repo.count_by_script(script_id).await?;
        Ok((reviews, total))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::CreateScriptRequest;
    use crate::services::ScriptService;
    use sqlx::sqlite::SqlitePoolOptions;

    async fn setup_test_db() -> SqlitePool {
        let pool = SqlitePoolOptions::new().connect(":memory:").await.unwrap();
        crate::db::initialize_database(&pool).await;
        pool
    }

    async fn create_test_script(pool: &SqlitePool) -> String {
        let script_service = ScriptService::new(pool.clone());
        let req = CreateScriptRequest {
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
        };
        script_service.create_script(req).await.unwrap().id
    }

    fn create_test_review_request(user_id: &str, rating: i32) -> CreateReviewRequest {
        CreateReviewRequest {
            user_id: user_id.to_string(),
            rating,
            comment: Some("Great script!".to_string()),
        }
    }

    #[tokio::test]
    async fn test_create_review_success() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool.clone());
        let script_id = create_test_script(&pool).await;

        let req = create_test_review_request("user-1", 5);
        let result = service.create_review(&script_id, req).await;

        assert!(result.is_ok());
        let review = result.unwrap();
        assert_eq!(review.script_id, script_id);
        assert_eq!(review.user_id, "user-1");
        assert_eq!(review.rating, 5);
        assert_eq!(review.comment, Some("Great script!".to_string()));
    }

    #[tokio::test]
    async fn test_create_review_validates_rating_too_low() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool.clone());
        let script_id = create_test_script(&pool).await;

        let req = create_test_review_request("user-1", 0);
        let result = service.create_review(&script_id, req).await;

        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Rating must be between 1 and 5");
    }

    #[tokio::test]
    async fn test_create_review_validates_rating_too_high() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool.clone());
        let script_id = create_test_script(&pool).await;

        let req = create_test_review_request("user-1", 6);
        let result = service.create_review(&script_id, req).await;

        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Rating must be between 1 and 5");
    }

    #[tokio::test]
    async fn test_create_review_validates_rating_range() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool.clone());
        let script_id = create_test_script(&pool).await;

        // Test all valid ratings
        for rating in 1..=5 {
            let req = CreateReviewRequest {
                user_id: format!("user-{}", rating),
                rating,
                comment: None,
            };
            let result = service.create_review(&script_id, req).await;
            assert!(result.is_ok(), "Rating {} should be valid", rating);
        }
    }

    #[tokio::test]
    async fn test_create_review_prevents_duplicate_reviews() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool.clone());
        let script_id = create_test_script(&pool).await;

        // Create first review
        let req1 = create_test_review_request("user-1", 5);
        let result1 = service.create_review(&script_id, req1).await;
        assert!(result1.is_ok());

        // Try to create another review from same user
        let req2 = create_test_review_request("user-1", 4);
        let result2 = service.create_review(&script_id, req2).await;

        assert!(result2.is_err());
        assert_eq!(
            result2.unwrap_err(),
            "User has already reviewed this script"
        );
    }

    #[tokio::test]
    async fn test_create_review_fails_for_nonexistent_script() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool);

        let req = create_test_review_request("user-1", 5);
        let result = service.create_review("nonexistent-script-id", req).await;

        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Script not found");
    }

    #[tokio::test]
    async fn test_create_review_updates_script_stats() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool.clone());
        let script_service = ScriptService::new(pool.clone());
        let script_id = create_test_script(&pool).await;

        // Initial state - no reviews
        let script = script_service
            .get_script(&script_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(script.rating, 0.0);
        assert_eq!(script.review_count, 0);

        // Add first review (rating: 5)
        let req1 = create_test_review_request("user-1", 5);
        service.create_review(&script_id, req1).await.unwrap();

        let script = script_service
            .get_script(&script_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(script.rating, 5.0);
        assert_eq!(script.review_count, 1);

        // Add second review (rating: 3)
        let req2 = create_test_review_request("user-2", 3);
        service.create_review(&script_id, req2).await.unwrap();

        let script = script_service
            .get_script(&script_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(script.rating, 4.0); // Average: (5 + 3) / 2 = 4.0
        assert_eq!(script.review_count, 2);

        // Add third review (rating: 4)
        let req3 = create_test_review_request("user-3", 4);
        service.create_review(&script_id, req3).await.unwrap();

        let script = script_service
            .get_script(&script_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(script.rating, 4.0); // Average: (5 + 3 + 4) / 3 = 4.0
        assert_eq!(script.review_count, 3);
    }

    #[tokio::test]
    async fn test_create_review_without_comment() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool.clone());
        let script_id = create_test_script(&pool).await;

        let req = CreateReviewRequest {
            user_id: "user-1".to_string(),
            rating: 4,
            comment: None,
        };
        let result = service.create_review(&script_id, req).await;

        assert!(result.is_ok());
        let review = result.unwrap();
        assert_eq!(review.comment, None);
    }

    #[tokio::test]
    async fn test_get_reviews_pagination() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool.clone());
        let script_id = create_test_script(&pool).await;

        // Create 5 reviews
        for i in 1..=5 {
            let req = create_test_review_request(&format!("user-{}", i), i as i32);
            service.create_review(&script_id, req).await.unwrap();
        }

        // Get first 3 reviews
        let (reviews, total) = service.get_reviews(&script_id, 3, 0).await.unwrap();
        assert_eq!(reviews.len(), 3);
        assert_eq!(total, 5);

        // Get next 3 reviews (should only get 2)
        let (reviews, _) = service.get_reviews(&script_id, 3, 3).await.unwrap();
        assert_eq!(reviews.len(), 2);
    }

    #[tokio::test]
    async fn test_get_reviews_empty() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool.clone());
        let script_id = create_test_script(&pool).await;

        let (reviews, total) = service.get_reviews(&script_id, 10, 0).await.unwrap();
        assert_eq!(reviews.len(), 0);
        assert_eq!(total, 0);
    }

    #[tokio::test]
    async fn test_get_reviews_filters_by_script() {
        let pool = setup_test_db().await;
        let service = ReviewService::new(pool.clone());

        // Create two scripts
        let script_id_1 = create_test_script(&pool).await;
        let script_id_2 = create_test_script(&pool).await;

        // Add reviews to script 1
        let req1 = create_test_review_request("user-1", 5);
        service.create_review(&script_id_1, req1).await.unwrap();

        let req2 = create_test_review_request("user-2", 4);
        service.create_review(&script_id_1, req2).await.unwrap();

        // Add review to script 2
        let req3 = create_test_review_request("user-3", 3);
        service.create_review(&script_id_2, req3).await.unwrap();

        // Get reviews for script 1
        let (reviews, total) = service.get_reviews(&script_id_1, 10, 0).await.unwrap();
        assert_eq!(reviews.len(), 2);
        assert_eq!(total, 2);

        // Get reviews for script 2
        let (reviews, total) = service.get_reviews(&script_id_2, 10, 0).await.unwrap();
        assert_eq!(reviews.len(), 1);
        assert_eq!(total, 1);
    }
}
