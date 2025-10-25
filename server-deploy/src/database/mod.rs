use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use reqwest::multipart;

use super::config::{AppConfig, AttributeType, IndexType};
use crate::utils::get_project_root;

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
            // Handle empty responses (common for DELETE operations)
            if response_text.trim().is_empty() || response_text.trim() == "{}" {
                // For empty responses, we need to return a default value or use a special type
                // Since we're expecting type T, we'll create a simple workaround
                serde_json::from_str("{}")
                    .with_context(|| format!("Failed to create default response for empty body"))
            } else {
                serde_json::from_str(&response_text)
                    .with_context(|| format!("Failed to parse response: {}", response_text))
            }
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

        match self
            .make_request::<serde_json::Value>(reqwest::Method::DELETE, &endpoint, None)
            .await
        {
            Ok(_) => {
                println!("✅   Collection deleted: {}", collection_id);
                Ok(())
            }
            Err(e) if e.to_string().contains("not found") || e.to_string().contains("404") => {
                println!("ℹ️   Collection not found, skipping deletion: {}", collection_id);
                Ok(())
            }
            Err(e) => {
                println!("❌   Failed to delete collection {}: {}", collection_id, e);
                Err(e)
            }
        }
    }

    pub async fn delete_storage_bucket(&mut self, bucket_id: &str) -> Result<()> {
        let endpoint = format!("storage/buckets/{}", bucket_id);

        match self
            .make_request::<serde_json::Value>(reqwest::Method::DELETE, &endpoint, None)
            .await
        {
            Ok(_) => {
                println!("✅   Storage bucket deleted: {}", bucket_id);
                Ok(())
            }
            Err(e) if e.to_string().contains("not found") || e.to_string().contains("404") => {
                println!("ℹ️   Storage bucket not found, skipping deletion: {}", bucket_id);
                Ok(())
            }
            Err(e) => {
                println!("❌   Failed to delete storage bucket {}: {}", bucket_id, e);
                Err(e)
            }
        }
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

    // Site management methods
    pub async fn create_site(&mut self) -> Result<()> {
        // First check if site already exists
        let existing_sites: serde_json::Value = self
            .make_request::<serde_json::Value>(reqwest::Method::GET, "sites", None)
            .await?;

        if let Some(sites_array) = existing_sites["sites"].as_array() {
            for site in sites_array {
                if let Some(name) = site["name"].as_str() {
                    if name == "ICP Script Marketplace" || name == "icp-autorun" {
                        println!("ℹ️   Site already exists: {}", name);
                        // Don't return early - continue to deployment step
                        println!("🚀   Proceeding with deployment...");
                        return Ok(());
                    }
                }
            }
        }

        // Create new site if it doesn't exist - with proper parameters for SvelteKit SSR
        let body = serde_json::json!({
            "siteId": "icp-marketplace",
            "name": "ICP Script Marketplace",
            "projectId": self.config.project_id,
            "framework": "sveltekit",
            "adapter": "ssr",
            "buildCommand": "npm run build",
            "installCommand": "npm install",
            "outputDirectory": "./build",
            "buildRuntime": "node-22"
        });

        println!("🔧   Creating site with body: {}", serde_json::to_string_pretty(&body)?);

        match self
            .make_request::<serde_json::Value>(reqwest::Method::POST, "sites", Some(body))
            .await
        {
            Ok(response) => {
                println!("✅   Site created successfully");
                println!("📋   Site response: {}", serde_json::to_string_pretty(&response)?);
                Ok(())
            }
            Err(e) => {
                println!("⚠️   Site creation failed: {}", e);

                // For local development, try alternative approach
                if self.config.endpoint.contains("localhost") {
                    println!("🔧   Trying alternative site creation for local environment...");
                    let local_body = serde_json::json!({
                        "siteId": "icp-marketplace-local",
                        "name": "ICP Script Marketplace Local",
                        "framework": "sveltekit",
                        "adapter": "ssr",
                        "buildCommand": "npm run build",
                        "installCommand": "npm install",
                        "outputDirectory": "./build",
                        "buildRuntime": "node-22",
                        "runtimes": ["node-22"],
                        "teamId": "default"
                    });

                    match self
                        .make_request::<serde_json::Value>(reqwest::Method::POST, "sites", Some(local_body))
                        .await
                    {
                        Ok(response) => {
                            println!("✅   Local site created successfully");
                            println!("📋   Local site response: {}", serde_json::to_string_pretty(&response)?);
                            Ok(())
                        }
                        Err(e2) => {
                            println!("⚠️   Local site creation also failed: {}", e2);
                            println!("ℹ️   This might be due to Appwrite version differences");
                            println!("ℹ️   Try creating the site manually in the Appwrite console");
                            println!("ℹ️   Continuing with deployment - other components will still work");
                            Ok(())
                        }
                    }
                } else {
                    println!("ℹ️   Continuing with existing site setup...");
                    Ok(())
                }
            }
        }
    }

    pub async fn deploy_site(&self) -> Result<()> {
        println!("🔍   Checking for existing sites...");

        // Get site ID first
        let sites: serde_json::Value = self
            .make_request::<serde_json::Value>(reqwest::Method::GET, "sites", None)
            .await?;

        println!("📋   Sites response: {}", serde_json::to_string_pretty(&sites)?);

        let _site_id = match sites["sites"]
            .as_array()
            .and_then(|arr| arr.first())
            .and_then(|site| site["$id"].as_str()) {
                Some(id) => {
                    println!("🚀   Found existing site: {}", id);
                    id
                }
                None => {
                    println!("⚠️   No sites found - site creation may have failed");
                    println!("ℹ️   In local development, sites may need to be created manually");
                    return Ok(());
                }
            };

        // Deploy the site from the appwrite/site directory
        let project_root = get_project_root()?;
        let site_path = project_root.join("appwrite/site");
        if !site_path.exists() {
            return Err(anyhow!("Site directory not found: {:?}", site_path));
        }

        println!("🚀   Building site from: {:?}", site_path);

        // Build the site using npm
        let output = std::process::Command::new("npm")
            .args(["run", "build"])
            .current_dir(&site_path)
            .output()
            .map_err(|e| anyhow!("Failed to build site: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            println!("❌   Site build failed!");
            println!("📋   STDOUT: {}", stdout);
            println!("📋   STDERR: {}", stderr);
            return Err(anyhow!("Site build failed: {}", stderr));
        }

        println!("✅   Site built successfully");

        // Deploy to existing site using Appwrite REST API
        println!("🚀   Deploying to Appwrite Site...");
        self.deploy_site_via_api(&site_path).await?;

        // Show site URL for local development
        if self.config.endpoint.contains("localhost") {
            println!("🌐   Local site will be available at: http://localhost:5173");
        } else {
            println!("🌐   Production site: https://icp-autorun.appwrite.network");
        }

        Ok(())
    }

    pub async fn test_site_access(&self) -> Result<()> {
        let sites: serde_json::Value = self
            .make_request::<serde_json::Value>(reqwest::Method::GET, "sites", None)
            .await?;

        if sites["sites"].as_array().map_or(0, |arr| arr.len()) > 0 {
            Ok(())
        } else {
            Err(anyhow!("No sites found"))
        }
    }

    /// Deploy site using Appwrite REST API with gzip file upload
    pub async fn deploy_site_via_api(&self, site_path: &std::path::Path) -> Result<()> {
        println!("📦   Creating gzip deployment package...");

        // Get existing site
        let sites: serde_json::Value = self
            .make_request::<serde_json::Value>(reqwest::Method::GET, "sites", None)
            .await?;

        let site_id = match sites["sites"]
            .as_array()
            .and_then(|arr| arr.first())
            .and_then(|site| site["$id"].as_str()) {
                Some(id) => id,
                None => {
                    return Err(anyhow!("No site found to deploy to"));
                }
            };

        println!("📋   Using site ID: {}", site_id);

        // Create a tar.gz file using the system tar command for compatibility
        let temp_gz_path = std::env::temp_dir().join("site-source.tar.gz");

        println!("📁   Packaging source files...");
        let temp_gz_path_str = temp_gz_path.to_str()
            .ok_or_else(|| anyhow!("Invalid UTF-8 in temp path"))?;
        let site_path_str = site_path.to_str()
            .ok_or_else(|| anyhow!("Invalid UTF-8 in site path"))?;

        let output = std::process::Command::new("tar")
            .args([
                "-czf", temp_gz_path_str,
                "--exclude=node_modules",
                "--exclude=.git",
                "--exclude=target",
                "-C", site_path_str,
                "."
            ])
            .output()
            .map_err(|e| anyhow!("Failed to create tar.gz file: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow!("Failed to create package: {}", stderr));
        }

        println!("📦   Deployment package created: {:?}", temp_gz_path);

        // Create multipart form data following the Appwrite API documentation exactly
        let form = multipart::Form::new()
            .text("installCommand", "npm install")
            .text("buildCommand", "npm run build")
            .text("outputDirectory", "./build")
            .text("activate", "true");

        // Add the tar.gz file
        let file_bytes = std::fs::read(&temp_gz_path)?;
        let file_part = multipart::Part::bytes(file_bytes)
            .file_name("source.tar.gz")
            .mime_str("application/gzip")?;

        let form = form.part("code", file_part);

        println!("📤   Uploading deployment to Appwrite...");

        // Make the request to the correct endpoint
        let response = self.client
            .post(format!("{}/v1/sites/{}/deployments", self.config.endpoint, site_id))
            .header("X-Appwrite-Project", &self.config.project_id)
            .header("X-Appwrite-Key", &self.config.api_key)
            .header("X-Appwrite-Response-Format", "1.8.0")
            .multipart(form)
            .send()
            .await
            .map_err(|e| anyhow!("Failed to upload deployment: {}", e))?;

        if response.status().is_success() {
            let response_text = response.text().await?;
            println!("✅   Site deployed successfully via REST API!");
            println!("📋   Deployment is now being processed by Appwrite");

            // Try to parse and show more info from the response
            if let Ok(response_json) = serde_json::from_str::<serde_json::Value>(&response_text) {
                if let Some(deployment_id) = response_json.get("$id").and_then(|v| v.as_str()) {
                    println!("🚀   Deployment ID: {}", deployment_id);
                }
            }
        } else {
            let status = response.status();
            let error_text = response.text().await?;

            // Handle the case where the deployment API is not available
            if status.as_u16() == 404 && error_text.contains("Route not found") {
                println!("⚠️   Sites deployment API not available in this Appwrite instance");
                println!("💡   This is common in local development environments");
                println!("🌐   Your site is built and ready for deployment");
                println!("📋   To deploy manually:");
                println!("   1. Visit: {}/console/project-{}/sites/site-{}",
                    self.config.endpoint.replace("/v1", ""),
                    self.config.project_id,
                    site_id
                );
                println!("   2. Use the Appwrite Console to upload your site files");
                println!("   3. Or ensure your site is connected to a Git repository for automatic deployments");
            } else {
                return Err(anyhow!("Deployment failed with status {}: {}", status, error_text));
            }
        }

        // Clean up temporary tar.gz file
        let _ = std::fs::remove_file(temp_gz_path);

        Ok(())
    }

    pub async fn delete_site(&self) -> Result<()> {
        let sites: serde_json::Value = self
            .make_request::<serde_json::Value>(reqwest::Method::GET, "sites", None)
            .await?;

        if let Some(sites_array) = sites["sites"].as_array() {
            for site in sites_array {
                if let Some(site_id) = site["$id"].as_str() {
                    match self
                        .make_request::<serde_json::Value>(
                            reqwest::Method::DELETE,
                            &format!("sites/{}", site_id),
                            None,
                        )
                        .await
                    {
                        Ok(_) => {
                            println!("✅   Site deleted: {}", site_id);
                        }
                        Err(e) => {
                            println!("⚠️   Failed to delete site {}: {}", site_id, e);
                        }
                    }
                }
            }
        }

        Ok(())
    }
}
