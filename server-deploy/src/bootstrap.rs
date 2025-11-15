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

    /// Check if appwrite-cli is available
    pub fn check_appwrite_cli() -> Result<()> {
        let output = Command::new("appwrite")
            .arg("--version")
            .output()
            .context("Failed to execute appwrite-cli. Is it installed?")?;

        if !output.status.success() {
            return Err(anyhow!("appwrite-cli not found or not working"));
        }

        let version = String::from_utf8_lossy(&output.stdout);
        info_message(&format!("Found appwrite-cli: {}", version.trim()));
        Ok(())
    }

    /// Initialize appwrite-cli with the given endpoint
    pub async fn initialize_cli(&self) -> Result<()> {
        info_message("Initializing appwrite-cli...");

        let output = Command::new("appwrite")
            .args(["init", "client", "--endpoint", &self.config.endpoint])
            .output()
            .context("Failed to initialize appwrite-cli")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow!("Failed to initialize appwrite-cli: {}", stderr));
        }

        success_message("appwrite-cli initialized successfully");
        Ok(())
    }

    /// Create a new team
    pub async fn create_team(&self) -> Result<String> {
        info_message(&format!("Creating team: {}", self.bootstrap_config.team_name));

        let output = Command::new("appwrite")
            .args([
                "init", "team",
                "--name", &self.bootstrap_config.team_name,
            ])
            .output()
            .context("Failed to create team")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            
            // Check if team already exists
            if stderr.contains("already exists") || stderr.contains("409") {
                info_message("Team already exists, proceeding...");
                return self.get_existing_team_id().await;
            }
            
            return Err(anyhow!("Failed to create team: {}", stderr));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        success_message("Team created successfully");
        
        // Extract team ID from output
        self.extract_id_from_output(&stdout, "Team")
    }

    /// Get existing team ID
    async fn get_existing_team_id(&self) -> Result<String> {
        let output = Command::new("appwrite")
            .args(["teams", "list"])
            .output()
            .context("Failed to list teams")?;

        if !output.status.success() {
            return Err(anyhow!("Failed to list teams"));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        
        // Parse JSON output to find team ID
        if let Ok(teams_json) = serde_json::from_str::<serde_json::Value>(&stdout) {
            if let Some(teams) = teams_json["teams"].as_array() {
                for team in teams {
                    if let Some(name) = team["name"].as_str() {
                        if name == self.bootstrap_config.team_name {
                            if let Some(id) = team["$id"].as_str() {
                                return Ok(id.to_string());
                            }
                        }
                    }
                }
            }
        }

        Err(anyhow!("Could not find existing team ID"))
    }

    /// Create a new project
    pub async fn create_project(&self, team_id: &str) -> Result<String> {
        info_message(&format!("Creating project: {}", self.bootstrap_config.project_name));

        let output = Command::new("appwrite")
            .args([
                "init", "project",
                "--name", &self.bootstrap_config.project_name,
                "--team-id", team_id,
            ])
            .output()
            .context("Failed to create project")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            
            // Check if project already exists
            if stderr.contains("already exists") || stderr.contains("409") {
                info_message("Project already exists, proceeding...");
                return self.get_existing_project_id().await;
            }
            
            return Err(anyhow!("Failed to create project: {}", stderr));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        success_message("Project created successfully");
        
        // Extract project ID from output
        self.extract_id_from_output(&stdout, "Project")
    }

    /// Get existing project ID
    async fn get_existing_project_id(&self) -> Result<String> {
        let output = Command::new("appwrite")
            .args(["projects", "list"])
            .output()
            .context("Failed to list projects")?;

        if !output.status.success() {
            return Err(anyhow!("Failed to list projects"));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        
        // Parse JSON output to find project ID
        if let Ok(projects_json) = serde_json::from_str::<serde_json::Value>(&stdout) {
            if let Some(projects) = projects_json["projects"].as_array() {
                for project in projects {
                    if let Some(name) = project["name"].as_str() {
                        if name == self.bootstrap_config.project_name {
                            if let Some(id) = project["$id"].as_str() {
                                return Ok(id.to_string());
                            }
                        }
                    }
                }
            }
        }

        Err(anyhow!("Could not find existing project ID"))
    }

    /// Create API key with proper scopes
    pub async fn create_api_key(&self, project_id: &str) -> Result<String> {
        info_message("Creating API key with marketplace scopes...");

        let scopes_str = self.bootstrap_config.api_key_scopes.join(",");
        
        let output = Command::new("appwrite")
            .args([
                "init", "key",
                "--name", "Marketplace API Key",
                "--project-id", project_id,
                "--scopes", &scopes_str,
            ])
            .output()
            .context("Failed to create API key")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow!("Failed to create API key: {}", stderr));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        success_message("API key created successfully");
        
        // Extract API key from output
        self.extract_id_from_output(&stdout, "API Key")
    }

    /// Create site
    pub async fn create_site(&self, project_id: &str) -> Result<String> {
        info_message(&format!("Creating site: {}", self.bootstrap_config.site_name));

        let output = Command::new("appwrite")
            .args([
                "init", "site",
                "--name", &self.bootstrap_config.site_name,
                "--project-id", project_id,
                "--framework", "sveltekit",
                "--adapter", "ssr",
            ])
            .output()
            .context("Failed to create site")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            
            // Check if site already exists
            if stderr.contains("already exists") || stderr.contains("409") {
                info_message("Site already exists, proceeding...");
                return self.get_existing_site_id(project_id).await;
            }
            
            return Err(anyhow!("Failed to create site: {}", stderr));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        success_message("Site created successfully");
        
        // Extract site ID from output
        self.extract_id_from_output(&stdout, "Site")
    }

    /// Get existing site ID
    async fn get_existing_site_id(&self, project_id: &str) -> Result<String> {
        let output = Command::new("appwrite")
            .args(["sites", "list", "--project-id", project_id])
            .output()
            .context("Failed to list sites")?;

        if !output.status.success() {
            return Err(anyhow!("Failed to list sites"));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        
        // Parse JSON output to find site ID
        if let Ok(sites_json) = serde_json::from_str::<serde_json::Value>(&stdout) {
            if let Some(sites) = sites_json["sites"].as_array() {
                for site in sites {
                    if let Some(name) = site["name"].as_str() {
                        if name == self.bootstrap_config.site_name {
                            if let Some(id) = site["$id"].as_str() {
                                return Ok(id.to_string());
                            }
                        }
                    }
                }
            }
        }

        Err(anyhow!("Could not find existing site ID"))
    }

    /// Extract ID from appwrite-cli output
    fn extract_id_from_output(&self, output: &str, resource_type: &str) -> Result<String> {
        // Try to parse as JSON first
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(output) {
            if let Some(id) = json.get("$id").and_then(|v| v.as_str()) {
                return Ok(id.to_string());
            }
        }

        // Fallback to text parsing
        for line in output.lines() {
            if line.contains("ID:") || line.contains("id:") {
                let parts: Vec<&str> = line.split(':').collect();
                if parts.len() >= 2 {
                    let id = parts[1].trim();
                    if !id.is_empty() {
                        return Ok(id.to_string());
                    }
                }
            }
        }

        Err(anyhow!("Could not extract {} ID from output", resource_type))
    }

    /// Complete bootstrap process
    pub async fn bootstrap(&self) -> Result<BootstrapResult> {
        info_message("Starting Appwrite bootstrap process...");

        // Check if appwrite-cli is available
        Self::check_appwrite_cli()?;

        // Initialize CLI
        self.initialize_cli().await?;

        // Wait a moment for initialization to complete
        sleep(Duration::from_secs(2)).await;

        // Create team
        let team_id = self.create_team().await?;
        
        // Wait for team creation to propagate
        sleep(Duration::from_secs(3)).await;

        // Create project
        let project_id = self.create_project(&team_id).await?;
        
        // Wait for project creation to propagate
        sleep(Duration::from_secs(3)).await;

        // Create API key
        let api_key = self.create_api_key(&project_id).await?;
        
        // Wait for API key creation to propagate
        sleep(Duration::from_secs(2)).await;

        // Create site
        let site_id = self.create_site(&project_id).await?;

        success_message("Bootstrap completed successfully!");

        Ok(BootstrapResult {
            team_id,
            project_id,
            api_key,
            site_id,
        })
    }

    /// Update existing config with bootstrap results
    pub fn update_config(&self, result: &BootstrapResult, target: &str) -> Result<()> {
        let mut updated_config = self.config.clone();
        updated_config.project_id = result.project_id.clone();
        updated_config.api_key = result.api_key.clone();

        updated_config.save(target)?;
        success_message(&format!("Configuration updated for target: {}", target));
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub struct BootstrapResult {
    pub team_id: String,
    pub project_id: String,
    pub api_key: String,
    pub site_id: String,
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