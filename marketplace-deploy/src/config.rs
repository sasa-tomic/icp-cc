use anyhow::{Context, Result};
use clap::ValueEnum;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub endpoint: String,
    pub project_id: String,
    pub api_key: String,
    pub database_id: String,
    pub scripts_collection_id: String,
    pub users_collection_id: String,
    pub purchases_collection_id: String,
    pub reviews_collection_id: String,
    pub storage_bucket_id: String,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            endpoint: String::new(),
            project_id: String::new(),
            api_key: String::new(),
            database_id: "marketplace_db".to_string(),
            scripts_collection_id: "scripts".to_string(),
            users_collection_id: "users".to_string(),
            purchases_collection_id: "purchases".to_string(),
            reviews_collection_id: "reviews".to_string(),
            storage_bucket_id: "scripts_files".to_string(),
        }
    }
}

impl AppConfig {
    pub fn new(project_id: String, api_key: String, endpoint: String) -> Self {
        Self {
            endpoint,
            project_id,
            api_key,
            ..Default::default()
        }
    }

    pub fn config_path(target: &str) -> PathBuf {
        dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("icp-marketplace")
            .join(format!("{}.json", target))
    }

    pub fn load(target: &str) -> Result<Self> {
        let config_path = Self::config_path(target);

        if !config_path.exists() {
            return Ok(Self::default());
        }

        let content = fs::read_to_string(&config_path)
            .with_context(|| format!("Failed to read config file: {:?}", config_path))?;

        let config: Self =
            serde_json::from_str(&content).with_context(|| "Failed to parse config file")?;

        Ok(config)
    }

    pub fn save(&self, target: &str) -> Result<()> {
        let config_path = Self::config_path(target);

        // Create directory if it doesn't exist
        if let Some(parent) = config_path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("Failed to create config directory: {:?}", parent))?;
        }

        let content =
            serde_json::to_string_pretty(self).with_context(|| "Failed to serialize config")?;

        fs::write(&config_path, content)
            .with_context(|| format!("Failed to write config file: {:?}", config_path))?;

        Ok(())
    }

    pub fn is_complete(&self) -> bool {
        !self.project_id.is_empty() && !self.api_key.is_empty() && !self.endpoint.is_empty()
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AttributeType {
    String,
    Integer,
    Float,
    Boolean,
    StringArray,
}

impl AttributeType {
    pub fn as_str(&self) -> &'static str {
        match self {
            AttributeType::String => "string",
            AttributeType::Integer => "integer",
            AttributeType::Float => "float",
            AttributeType::Boolean => "boolean",
            AttributeType::StringArray => "string",
        }
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone, Copy)]
pub enum IndexType {
    Key,
    Unique,
    Fulltext,
}

#[allow(dead_code)]
impl IndexType {
    pub fn as_str(&self) -> &'static str {
        match self {
            IndexType::Key => "key",
            IndexType::Unique => "unique",
            IndexType::Fulltext => "fulltext",
        }
    }
}

#[derive(Debug, Clone, ValueEnum, PartialEq)]
pub enum DeployComponents {
    Database,
    Collections,
    Sites,
    Storage,
    All,
}
