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
