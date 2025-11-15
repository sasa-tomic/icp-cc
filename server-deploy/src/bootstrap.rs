use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::process::Command;
use std::time::Duration;
use tokio::time::sleep;

use super::config::AppConfig;
use crate::utils::{info_message, success_message};

#[derive(Debug, Serialize, Deserialize)]
pub struct BootstrapConfig {
    pub team_name: String,
    pub project_name: String,
    pub site_name: String,
    pub api_key_scopes: Vec<String>,
}

impl Default for BootstrapConfig {
    fn default() -> Self {
        Self {
            team_name: "ICP Marketplace Team".to_string(),
            project_name: "ICP Script Marketplace".to_string(),
            site_name: "icp-marketplace".to_string(),
            api_key_scopes: vec![
                "users.read".to_string(),
                "users.write".to_string(),
                "teams.read".to_string(),
                "teams.write".to_string(),
                "databases.read".to_string(),
                "databases.write".to_string(),
                "collections.read".to_string(),
                "collections.write".to_string(),
                "attributes.read".to_string(),
                "attributes.write".to_string(),
                "indexes.read".to_string(),
                "indexes.write".to_string(),
                "documents.read".to_string(),
                "documents.write".to_string(),
                "buckets.read".to_string(),
                "buckets.write".to_string(),
                "files.read".to_string(),
                "files.write".to_string(),
                "functions.read".to_string(),
                "functions.write".to_string(),
                "executions.read".to_string(),
                "executions.write".to_string(),
                "sites.read".to_string(),
                "sites.write".to_string(),
            ],
        }
    }
}

pub struct BootstrapManager {
    config: AppConfig,
    bootstrap_config: BootstrapConfig,
}

impl BootstrapManager {
    pub fn new(config: AppConfig, bootstrap_config: Option<BootstrapConfig>) -> Self {
        Self {
            config,
            bootstrap_config: bootstrap_config.unwrap_or_default(),
        }
    }

    /// Complete bootstrap process
    pub async fn bootstrap(&self) -> Result<BootstrapResult> {
        info_message("Bootstrap process is deprecated - using Cloudflare Workers instead");
        
        Err(anyhow!("Appwrite bootstrap is deprecated. Please use Cloudflare Workers deployment instead."))
    }

#[derive(Debug, Clone)]
pub struct BootstrapResult {
    pub message: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bootstrap_config_default() {
        let config = BootstrapConfig::default();
        assert_eq!(config.team_name, "ICP Marketplace Team");
        assert_eq!(config.project_name, "ICP Script Marketplace");
        assert_eq!(config.site_name, "icp-marketplace");
        assert!(!config.api_key_scopes.is_empty());
    }

    #[test]
    fn test_bootstrap_deprecated() {
        let manager = BootstrapManager::new(
            AppConfig::new("test".to_string(), "test".to_string(), "test".to_string()),
            None,
        );
        
        // This test verifies that bootstrap returns an error since it's deprecated
        let rt = tokio::runtime::Runtime::new().unwrap();
        let result = rt.block_on(manager.bootstrap());
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("deprecated"));
    }
}

    #[test]
    fn test_extract_id_from_json() {
        let manager = BootstrapManager::new(
            AppConfig::new("test".to_string(), "test".to_string(), "test".to_string()),
            None,
        );
        
        let json_output = r#"{"$id":"test123","name":"Test Resource"}"#;
        let result = manager.extract_id_from_output(json_output, "Test");
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "test123");
    }

    #[test]
    fn test_extract_id_from_text() {
        let manager = BootstrapManager::new(
            AppConfig::new("test".to_string(), "test".to_string(), "test".to_string()),
            None,
        );
        
        let text_output = "Resource created successfully\nID: test456\nOther info";
        let result = manager.extract_id_from_output(text_output, "Test");
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "test456");
    }
}