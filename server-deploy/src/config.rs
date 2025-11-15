use anyhow::{Context, Result};
use clap::ValueEnum;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub account_id: String,
    pub api_token: String,
    pub worker_name: String,
    pub database_name: String,
    pub database_id: String,
    pub worker_url: String,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            account_id: String::new(),
            api_token: String::new(),
            worker_name: "icp-marketplace-api".to_string(),
            database_name: "icp-marketplace-db".to_string(),
            database_id: String::new(),
            worker_url: String::new(),
        }
    }
}

impl AppConfig {
    pub fn new(account_id: String, api_token: String) -> Self {
        Self {
            account_id,
            api_token,
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
        !self.account_id.is_empty() && !self.api_token.is_empty()
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
    Worker,
    All,
}
