use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::time::Duration;

use super::config::{AppConfig, AttributeType, IndexType};

pub struct DatabaseManager {
    client: reqwest::Client,
    config: AppConfig,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DatabaseInfo {
    #[serde(rename = "$id")]
    pub id: String,
    pub name: String,
    #[serde(rename = "$createdAt")]
    pub created_at: String,
    #[serde(rename = "$updatedAt")]
    pub updated_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CollectionInfo {
    #[serde(rename = "$id")]
    pub id: String,
    pub name: String,
    #[serde(rename = "databaseId")]
    pub database_id: String,
    #[serde(rename = "$createdAt")]
    pub created_at: String,
    #[serde(rename = "$updatedAt")]
    pub updated_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct BucketInfo {
    #[serde(rename = "$id")]
    pub id: String,
    pub name: String,
    #[serde(rename = "$createdAt")]
    pub created_at: String,
    #[serde(rename = "$updatedAt")]
    pub updated_at: String,
}

impl DatabaseManager {
    pub async fn new(config: AppConfig) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .context("Failed to create HTTP client")?;

        Ok(Self { client, config })
    }

    async fn make_request<T: serde::de::DeserializeOwned>(
        &self,
        method: reqwest::Method,
        endpoint: &str,
        body: Option<serde_json::Value>,
    ) -> Result<T> {
        let url = format!("{}/{}", self.config.endpoint, endpoint);
        let mut request = self.client.request(method, &url);

        request = request
            .header("X-Appwrite-Project", &self.config.project_id)
            .header("X-Appwrite-Key", &self.config.api_key)
            .header("Content-Type", "application/json");

        if let Some(body) = body {
            request = request.json(&body);
        }

        let response = request.send().await?;

        let status = response.status();
        let response_text = response.text().await?;

        if status.is_success() {
            serde_json::from_str(&response_text)
                .with_context(|| format!("Failed to parse response: {}", response_text))
        } else {
            Err(anyhow!(
                "HTTP {} - {}: {}",
                status.as_u16(),
                status.canonical_reason().unwrap_or("Unknown"),
                response_text
            ))
        }
    }

    pub async fn test_database_access(&self) -> Result<()> {
        self.make_request::<serde_json::Value>(
            reqwest::Method::GET,
            &format!("databases/{}", self.config.database_id),
            None,
        )
        .await
        .map(|_| ())
    }

    pub async fn test_collection_access(&self) -> Result<()> {
        self.make_request::<serde_json::Value>(
            reqwest::Method::GET,
            &format!(
                "databases/{}/collections/{}",
                self.config.database_id, self.config.scripts_collection_id
            ),
            None,
        )
        .await
        .map(|_| ())
    }

    pub async fn create_database(&mut self) -> Result<()> {
        let body = serde_json::json!({
            "databaseId": self.config.database_id,
            "name": "ICP Script Marketplace Database"
        });

        match self
            .make_request::<DatabaseInfo>(reqwest::Method::POST, "databases", Some(body))
            .await
        {
            Ok(_) => Ok(()),
            Err(e) if e.to_string().contains("already exists") => Ok(()),
            Err(e) => Err(e),
        }
    }

    pub async fn create_collection(&mut self, collection_id: &str, name: &str) -> Result<()> {
        let body = serde_json::json!({
            "collectionId": collection_id,
            "name": name,
            "permissions": [
                "create(\"any\")",
                "read(\"any\")",
                "update(\"any\")",
                "delete(\"any\")"
            ],
            "documentSecurity": true
        });

        let endpoint = format!("databases/{}/collections", self.config.database_id);

        match self
            .make_request::<CollectionInfo>(reqwest::Method::POST, &endpoint, Some(body))
            .await
        {
            Ok(_) => Ok(()),
            Err(e) if e.to_string().contains("already exists") => Ok(()),
            Err(e) => Err(e),
        }
    }

    pub async fn create_attribute(
        &mut self,
        collection_id: &str,
        key: &str,
        attr_type: AttributeType,
        size: Option<i32>,
        required: bool,
        default: Option<serde_json::Value>,
    ) -> Result<()> {
        let body = serde_json::json!({
            "key": key,
            "type": attr_type.as_str(),
            "size": size,
            "required": required,
            "default": default,
            "array": matches!(attr_type, AttributeType::StringArray)
        });

        let endpoint = format!(
            "databases/{}/collections/{}/attributes",
            self.config.database_id, collection_id
        );

        self.make_request::<serde_json::Value>(reqwest::Method::POST, &endpoint, Some(body))
            .await
            .map(|_| ())
    }

    pub async fn create_index(
        &mut self,
        collection_id: &str,
        key: &str,
        index_type: IndexType,
        unique: bool,
    ) -> Result<()> {
        let body = serde_json::json!({
            "key": key,
            "type": index_type.as_str(),
            "caseSensitive": false,
            "unique": unique
        });

        let endpoint = format!(
            "databases/{}/collections/{}/indexes",
            self.config.database_id, collection_id
        );

        self.make_request::<serde_json::Value>(reqwest::Method::POST, &endpoint, Some(body))
            .await
            .map(|_| ())
    }

    pub async fn create_storage_bucket(
        &mut self,
        bucket_id: &str,
        name: &str,
        max_file_size: i64,
    ) -> Result<()> {
        let body = serde_json::json!({
            "bucketId": bucket_id,
            "name": name,
            "fileSecurity": false,
            "maximumFileSize": max_file_size
        });

        match self
            .make_request::<BucketInfo>(reqwest::Method::POST, "storage/buckets", Some(body))
            .await
        {
            Ok(_) => Ok(()),
            Err(e) if e.to_string().contains("already exists") => Ok(()),
            Err(e) => Err(e),
        }
    }

    pub async fn delete_collection(&mut self, collection_id: &str) -> Result<()> {
        let endpoint = format!(
            "databases/{}/collections/{}",
            self.config.database_id, collection_id
        );

        self.make_request::<serde_json::Value>(reqwest::Method::DELETE, &endpoint, None)
            .await
            .map(|_| ())
    }

    pub async fn delete_storage_bucket(&mut self, bucket_id: &str) -> Result<()> {
        let endpoint = format!("storage/buckets/{}", bucket_id);

        self.make_request::<serde_json::Value>(reqwest::Method::DELETE, &endpoint, None)
            .await
            .map(|_| ())
    }

    // Script collection setup
    pub async fn setup_scripts_collection(&mut self) -> Result<()> {
        let scripts_collection_id = self.config.scripts_collection_id.clone();
        self.create_collection(&scripts_collection_id, "Scripts")
            .await?;

        // Attributes for scripts collection
        let script_attributes = vec![
            (
                "title",
                AttributeType::String,
                Some(256),
                true,
                None::<serde_json::Value>,
            ),
            (
                "description",
                AttributeType::String,
                Some(2000),
                true,
                None::<serde_json::Value>,
            ),
            (
                "category",
                AttributeType::String,
                Some(100),
                true,
                None::<serde_json::Value>,
            ),
            (
                "tags",
                AttributeType::StringArray,
                Some(500),
                false,
                None::<serde_json::Value>,
            ),
            (
                "authorId",
                AttributeType::String,
                Some(128),
                true,
                None::<serde_json::Value>,
            ),
            (
                "authorName",
                AttributeType::String,
                Some(256),
                true,
                None::<serde_json::Value>,
            ),
            (
                "price",
                AttributeType::Float,
                None,
                false,
                Some(serde_json::Value::Number(
                    serde_json::Number::from_f64(0.0).unwrap(),
                )),
            ),
            (
                "downloads",
                AttributeType::Integer,
                None,
                false,
                Some(serde_json::Value::Number(serde_json::Number::from(0))),
            ),
            (
                "rating",
                AttributeType::Float,
                None,
                false,
                Some(serde_json::Value::Number(
                    serde_json::Number::from_f64(0.0).unwrap(),
                )),
            ),
            (
                "reviewCount",
                AttributeType::Integer,
                None,
                false,
                Some(serde_json::Value::Number(serde_json::Number::from(0))),
            ),
            (
                "luaSource",
                AttributeType::String,
                Some(100000),
                true,
                None::<serde_json::Value>,
            ),
            (
                "iconUrl",
                AttributeType::String,
                Some(2048),
                false,
                None::<serde_json::Value>,
            ),
            (
                "screenshots",
                AttributeType::StringArray,
                Some(5000),
                false,
                None::<serde_json::Value>,
            ),
            (
                "canisterIds",
                AttributeType::StringArray,
                Some(1000),
                false,
                None::<serde_json::Value>,
            ),
            (
                "compatibility",
                AttributeType::String,
                Some(500),
                false,
                None::<serde_json::Value>,
            ),
            (
                "version",
                AttributeType::String,
                Some(50),
                false,
                None::<serde_json::Value>,
            ),
            (
                "isPublic",
                AttributeType::Boolean,
                None,
                false,
                Some(serde_json::Value::Bool(true)),
            ),
            (
                "isApproved",
                AttributeType::Boolean,
                None,
                false,
                Some(serde_json::Value::Bool(false)),
            ),
        ];

        for (key, attr_type, size, required, default) in script_attributes {
            self.create_attribute(
                &scripts_collection_id,
                key,
                attr_type,
                size,
                required,
                default,
            )
            .await?;
        }

        // Indexes for scripts collection
        let script_indexes = vec![
            ("title", IndexType::Key, false),
            ("category", IndexType::Key, false),
            ("title,description,tags", IndexType::Fulltext, false),
            ("rating", IndexType::Key, false),
            ("downloads", IndexType::Key, false),
            ("createdAt", IndexType::Key, false),
        ];

        for (key, index_type, unique) in script_indexes {
            self.create_index(&scripts_collection_id, key, index_type, unique)
                .await?;
        }

        Ok(())
    }

    // Users collection setup
    pub async fn setup_users_collection(&mut self) -> Result<()> {
        let users_collection_id = self.config.users_collection_id.clone();
        self.create_collection(&users_collection_id, "Users")
            .await?;

        let user_attributes = vec![
            (
                "userId",
                AttributeType::String,
                Some(128),
                true,
                None::<serde_json::Value>,
            ),
            (
                "username",
                AttributeType::String,
                Some(100),
                true,
                None::<serde_json::Value>,
            ),
            (
                "displayName",
                AttributeType::String,
                Some(256),
                true,
                None::<serde_json::Value>,
            ),
            (
                "bio",
                AttributeType::String,
                Some(1000),
                false,
                None::<serde_json::Value>,
            ),
            (
                "avatar",
                AttributeType::String,
                Some(2048),
                false,
                None::<serde_json::Value>,
            ),
            (
                "website",
                AttributeType::String,
                Some(512),
                false,
                None::<serde_json::Value>,
            ),
            (
                "socialLinks",
                AttributeType::StringArray,
                Some(1000),
                false,
                None::<serde_json::Value>,
            ),
            (
                "scriptsPublished",
                AttributeType::Integer,
                None,
                false,
                Some(serde_json::Value::Number(serde_json::Number::from(0))),
            ),
            (
                "totalDownloads",
                AttributeType::Integer,
                None,
                false,
                Some(serde_json::Value::Number(serde_json::Number::from(0))),
            ),
            (
                "averageRating",
                AttributeType::Float,
                None,
                false,
                Some(serde_json::Value::Number(
                    serde_json::Number::from_f64(0.0).unwrap(),
                )),
            ),
            (
                "isVerifiedDeveloper",
                AttributeType::Boolean,
                None,
                false,
                Some(serde_json::Value::Bool(false)),
            ),
            (
                "favorites",
                AttributeType::StringArray,
                Some(10000),
                false,
                None::<serde_json::Value>,
            ),
        ];

        for (key, attr_type, size, required, default) in user_attributes {
            self.create_attribute(
                &users_collection_id,
                key,
                attr_type,
                size,
                required,
                default,
            )
            .await?;
        }

        // Indexes for users collection
        self.create_index(&users_collection_id, "userId", IndexType::Unique, true)
            .await?;
        self.create_index(&users_collection_id, "username", IndexType::Unique, true)
            .await?;

        Ok(())
    }

    // Reviews collection setup
    pub async fn setup_reviews_collection(&mut self) -> Result<()> {
        let reviews_collection_id = self.config.reviews_collection_id.clone();
        self.create_collection(&reviews_collection_id, "Reviews")
            .await?;

        let review_attributes = vec![
            (
                "userId",
                AttributeType::String,
                Some(128),
                true,
                None::<serde_json::Value>,
            ),
            (
                "scriptId",
                AttributeType::String,
                Some(128),
                true,
                None::<serde_json::Value>,
            ),
            (
                "rating",
                AttributeType::Integer,
                None,
                true,
                None::<serde_json::Value>,
            ),
            (
                "comment",
                AttributeType::String,
                Some(2000),
                false,
                None::<serde_json::Value>,
            ),
            (
                "isVerifiedPurchase",
                AttributeType::Boolean,
                None,
                false,
                Some(serde_json::Value::Bool(false)),
            ),
            (
                "status",
                AttributeType::String,
                Some(50),
                false,
                Some(serde_json::Value::String("approved".to_string())),
            ),
        ];

        for (key, attr_type, size, required, default) in review_attributes {
            self.create_attribute(
                &reviews_collection_id,
                key,
                attr_type,
                size,
                required,
                default,
            )
            .await?;
        }

        // Unique index on userId + scriptId
        self.create_index(
            &reviews_collection_id,
            "userId,scriptId",
            IndexType::Unique,
            true,
        )
        .await?;

        Ok(())
    }

    // Purchases collection setup
    pub async fn setup_purchases_collection(&mut self) -> Result<()> {
        let purchases_collection_id = self.config.purchases_collection_id.clone();
        self.create_collection(&purchases_collection_id, "Purchases")
            .await?;

        let purchase_attributes = vec![
            (
                "userId",
                AttributeType::String,
                Some(128),
                true,
                None::<serde_json::Value>,
            ),
            (
                "scriptId",
                AttributeType::String,
                Some(128),
                true,
                None::<serde_json::Value>,
            ),
            (
                "transactionId",
                AttributeType::String,
                Some(256),
                true,
                None::<serde_json::Value>,
            ),
            (
                "price",
                AttributeType::Float,
                None,
                true,
                None::<serde_json::Value>,
            ),
            (
                "currency",
                AttributeType::String,
                Some(10),
                false,
                Some(serde_json::Value::String("USD".to_string())),
            ),
            (
                "status",
                AttributeType::String,
                Some(50),
                false,
                Some(serde_json::Value::String("pending".to_string())),
            ),
            (
                "paymentMethod",
                AttributeType::String,
                Some(50),
                true,
                None::<serde_json::Value>,
            ),
        ];

        for (key, attr_type, size, required, default) in purchase_attributes {
            self.create_attribute(
                &purchases_collection_id,
                key,
                attr_type,
                size,
                required,
                default,
            )
            .await?;
        }

        Ok(())
    }
}
