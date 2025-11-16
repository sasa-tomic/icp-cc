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
}

fn resolve_script_visibility(is_public: Option<bool>) -> bool {
    is_public.unwrap_or(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_visibility_defaults_to_public() {
        assert!(resolve_script_visibility(None));
    }

    #[test]
    fn resolve_visibility_preserves_private_flag() {
        assert!(!resolve_script_visibility(Some(false)));
        assert!(resolve_script_visibility(Some(true)));
    }
}
