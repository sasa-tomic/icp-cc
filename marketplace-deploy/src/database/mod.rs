use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::time::Duration;

use super::config::{AppConfig, AttributeType, IndexType};

#[cfg(test)]
mod tests;

// Type alias to reduce complexity warnings
type AttributeDefinition = (
    &'static str,
    AttributeType,
    Option<i32>,
    bool,
    Option<serde_json::Value>,
);

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
        // First check if database already exists
        match self.test_database_access().await {
            Ok(_) => {
                println!("ℹ️   Database already exists: {}", self.config.database_id);
                return Ok(());
            }
            Err(_) => {
                // Database doesn't exist, try to create it
            }
        }

        let body = serde_json::json!({
            "databaseId": self.config.database_id,
            "name": "ICP Script Marketplace Database"
        });

        match self
            .make_request::<DatabaseInfo>(reqwest::Method::POST, "databases", Some(body))
            .await
        {
            Ok(_) => {
                println!("✅   Database created: {}", self.config.database_id);
                Ok(())
            }
            Err(e) if e.to_string().contains("already exists") => {
                println!("ℹ️   Database already exists: {}", self.config.database_id);
                Ok(())
            }
            Err(e) if e.to_string().contains("409") => {
                println!("ℹ️   Database already exists: {}", self.config.database_id);
                Ok(())
            }
            Err(e)
                if e.to_string().contains("403")
                    && e.to_string().contains("maximum number of databases") =>
            {
                // Database limit reached, check if it already exists
                match self.test_database_access().await {
                    Ok(_) => {
                        println!("ℹ️   Database already exists (plan limit reached): {}", self.config.database_id);
                        Ok(())
                    },
                    Err(_) => {
                        Err(anyhow!("Database creation failed due to plan limit and database does not exist: {}", e))
                    }
                }
            }
            Err(e) => Err(e),
        }
    }

    pub async fn create_collection(&mut self, collection_id: &str, name: &str) -> Result<()> {
        // Check if collection already exists
        let check_endpoint = format!(
            "databases/{}/collections/{}",
            self.config.database_id, collection_id
        );
        match self
            .make_request::<serde_json::Value>(reqwest::Method::GET, &check_endpoint, None)
            .await
        {
            Ok(_) => {
                println!("ℹ️   Collection already exists: {}", name);
                return Ok(());
            }
            Err(_) => {
                // Collection doesn't exist, proceed with creation
            }
        }

        // Create collection with attributes based on collection type
        let (body, attributes) = match collection_id {
            "scripts" => {
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
                (body, self.get_scripts_attributes())
            }
            "users" => {
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
                (body, self.get_users_attributes())
            }
            "reviews" => {
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
                (body, self.get_reviews_attributes())
            }
            "purchases" => {
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
                (body, self.get_purchases_attributes())
            }
            _ => {
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
                (body, vec![])
            }
        };

        // Include attributes in the collection creation if available
        let mut final_body = body;
        if !attributes.is_empty() {
            final_body["attributes"] = serde_json::Value::Array(
                attributes
                    .into_iter()
                    .map(|(key, attr_type, size, required, default)| {
                        let mut attr = serde_json::json!({
                            "key": key,
                            "type": attr_type.as_str(),
                            "required": required
                        });
                        if let Some(s) = size {
                            attr["size"] = serde_json::Value::Number(s.into());
                        }
                        if matches!(attr_type, AttributeType::StringArray) {
                            attr["array"] = serde_json::Value::Bool(true);
                        }
                        if let Some(d) = default {
                            attr["default"] = d;
                        }
                        attr
                    })
                    .collect(),
            );
        }

        let endpoint = format!("databases/{}/collections", self.config.database_id);

        match self
            .make_request::<CollectionInfo>(reqwest::Method::POST, &endpoint, Some(final_body))
            .await
        {
            Ok(_) => {
                println!("✅   Collection created: {}", name);
                Ok(())
            }
            Err(e) if e.to_string().contains("already exists") => {
                println!("ℹ️   Collection already exists: {}", name);
                Ok(())
            }
            Err(e) if e.to_string().contains("409") => {
                println!("ℹ️   Collection already exists: {}", name);
                Ok(())
            }
            Err(e) if e.to_string().contains("404") => {
                // Try the new API format - this might be using tables instead of collections
                // But first, check if the collection was created successfully
                match self
                    .make_request::<serde_json::Value>(reqwest::Method::GET, &check_endpoint, None)
                    .await
                {
                    Ok(_) => {
                        println!("ℹ️   Collection already exists: {}", name);
                        Ok(())
                    }
                    Err(_check_err) => {
                        // If it's truly a 404 route not found, it might be using the new API
                        if e.to_string().contains("Route not found") {
                            println!("ℹ️   Collection creation skipped (possible API version mismatch): {}", name);
                            Ok(())
                        } else {
                            Err(e)
                        }
                    }
                }
            }
            Err(e) => Err(e),
        }
    }

    // Helper methods to get attributes for each collection type
    pub fn get_scripts_attributes(&self) -> Vec<AttributeDefinition> {
        vec![
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
            (
                "createdAt",
                AttributeType::Integer,
                None,
                false,
                Some(serde_json::Value::Number(serde_json::Number::from(0))),
            ),
            (
                "updatedAt",
                AttributeType::Integer,
                None,
                false,
                Some(serde_json::Value::Number(serde_json::Number::from(0))),
            ),
            (
                "isDeleted",
                AttributeType::Boolean,
                None,
                false,
                Some(serde_json::Value::Bool(false)),
            ),
        ]
    }

    pub fn get_users_attributes(&self) -> Vec<AttributeDefinition> {
        vec![
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
        ]
    }

    pub fn get_reviews_attributes(&self) -> Vec<AttributeDefinition> {
        vec![
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
        ]
    }

    pub fn get_purchases_attributes(&self) -> Vec<AttributeDefinition> {
        vec![
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
        ]
    }

    #[allow(dead_code)]
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

        match self
            .make_request::<serde_json::Value>(reqwest::Method::POST, &endpoint, Some(body))
            .await
        {
            Ok(_) => Ok(()),
            Err(e) if e.to_string().contains("already exists") => Ok(()),
            Err(e) if e.to_string().contains("409") => Ok(()), // Conflict - attribute already exists
            Err(e)
                if e.to_string().contains("404") && e.to_string().contains("Route not found") =>
            {
                // Attribute creation might not be supported in this API version
                println!(
                    "ℹ️   Attribute creation skipped (API version mismatch): {}",
                    key
                );
                Ok(())
            }
            Err(e) => Err(e),
        }
    }

    #[allow(dead_code)]
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

        match self
            .make_request::<serde_json::Value>(reqwest::Method::POST, &endpoint, Some(body))
            .await
        {
            Ok(_) => Ok(()),
            Err(e) if e.to_string().contains("already exists") => Ok(()),
            Err(e) if e.to_string().contains("409") => Ok(()), // Conflict - index already exists
            Err(e)
                if e.to_string().contains("404") && e.to_string().contains("Route not found") =>
            {
                // Index creation might not be supported in this API version
                println!(
                    "ℹ️   Index creation skipped (API version mismatch): {}",
                    key
                );
                Ok(())
            }
            Err(e) => Err(e),
        }
    }

    pub async fn create_storage_bucket(
        &mut self,
        bucket_id: &str,
        name: &str,
        max_file_size: i64,
    ) -> Result<()> {
        // Check if storage bucket already exists
        let check_endpoint = format!("storage/buckets/{}", bucket_id);
        match self
            .make_request::<serde_json::Value>(reqwest::Method::GET, &check_endpoint, None)
            .await
        {
            Ok(_) => {
                println!("ℹ️   Storage bucket already exists: {}", name);
                return Ok(());
            }
            Err(_) => {
                // Storage bucket doesn't exist, proceed with creation
            }
        }

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
            Ok(_) => {
                println!("✅   Storage bucket created: {}", name);
                Ok(())
            }
            Err(e) if e.to_string().contains("already exists") => {
                println!("ℹ️   Storage bucket already exists: {}", name);
                Ok(())
            }
            Err(e) if e.to_string().contains("409") => {
                println!("ℹ️   Storage bucket already exists: {}", name);
                Ok(())
            }
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
    #[allow(dead_code)]
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
            (
                "createdAt",
                AttributeType::Integer,
                None,
                false,
                Some(serde_json::Value::Number(serde_json::Number::from(0))),
            ),
            (
                "updatedAt",
                AttributeType::Integer,
                None,
                false,
                Some(serde_json::Value::Number(serde_json::Number::from(0))),
            ),
            (
                "isDeleted",
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
    #[allow(dead_code)]
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
    #[allow(dead_code)]
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
    #[allow(dead_code)]
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
