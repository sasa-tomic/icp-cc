use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::time::Duration;
use tokio::fs;

use super::config::AppConfig;

pub struct FunctionManager {
    client: reqwest::Client,
    config: AppConfig,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FunctionInfo {
    #[serde(rename = "$id")]
    pub id: String,
    pub name: String,
    pub runtime: String,
    pub enabled: bool,
    #[serde(default)]
    pub status: Option<String>,
}

impl FunctionManager {
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
            Err(anyhow::anyhow!(
                "HTTP {} - {}: {}",
                status.as_u16(),
                status.canonical_reason().unwrap_or("Unknown"),
                response_text
            ))
        }
    }

    pub async fn function_exists(&self, function_id: &str) -> Result<bool> {
        let endpoint = format!("functions/{}", function_id);
        println!("🔍 Checking if function exists: {}", function_id);
        match self
            .make_request::<serde_json::Value>(reqwest::Method::GET, &endpoint, None)
            .await
        {
            Ok(_) => {
                println!("✅ Function exists: {}", function_id);
                Ok(true)
            },
            Err(e) if e.to_string().to_lowercase().contains("not found") => {
                println!("❌ Function does not exist: {}", function_id);
                Ok(false)
            },
            Err(e) => {
                println!("❌ Error checking function {}: {}", function_id, e);
                Err(e)
            },
        }
    }

    pub async fn create_function(
        &self,
        function_id: &str,
        name: &str,
        runtime: &str,
        events: Option<Vec<String>>,
    ) -> Result<()> {
        let body = serde_json::json!({
            "functionId": function_id,
            "name": name,
            "runtime": runtime,
            "execute": ["any"],
            "events": events.unwrap_or_else(|| vec![])
        });

        match self
            .make_request::<FunctionInfo>(reqwest::Method::POST, "functions", Some(body))
            .await
        {
            Ok(_) => Ok(()),
            Err(e) if e.to_string().contains("already exists") => Ok(()),
            Err(e) => Err(e),
        }
    }

    #[allow(dead_code)]
    pub async fn test_function(&self, function_id: &str, test_data: &str) -> Result<()> {
        let body = serde_json::json!({
            "data": test_data
        });

        let endpoint = format!("functions/{}/executions", function_id);
        self.make_request::<serde_json::Value>(reqwest::Method::POST, &endpoint, Some(body))
            .await
            .map(|_| ())
    }

    pub async fn deploy_all_functions(&self) -> Result<()> {
        let functions = vec![
            ("search_scripts", "Search Scripts", "node-18.0", None),
            ("process_purchase", "Process Purchase", "node-18.0", None),
            (
                "update_script_stats",
                "Update Script Stats",
                "node-18.0",
                Some(vec!["databases.marketplace_db.collections.scripts.documents.*.create".to_string()]),
            ),
        ];

        for (func_id, name, runtime, events) in functions {
            if !self.function_exists(func_id).await? {
                println!("Creating function: {}", name);
                self.create_function(func_id, name, runtime, events).await?;
                self.deploy_function_code(func_id).await?;
                println!("✅ Created and deployed function: {}", name);
            } else {
                println!("ℹ️ Function already exists: {}", name);
                // Always try to deploy code to existing functions
                // This will replace any existing code or deploy code if missing
                println!("🔄 Deploying/Updating function code...");
                self.deploy_function_code(func_id).await?;
                println!("✅ Function code deployed: {}", name);
            }
        }

        Ok(())
    }

    async fn deploy_function_code(&self, function_id: &str) -> Result<()> {
        let function_path = Path::new("appwrite/functions").join(function_id);

        // Check if function directory exists
        if !function_path.exists() {
            return Err(anyhow::anyhow!(
                "Function directory not found: {}",
                function_path.display()
            ));
        }

        // Create a tar.gz archive of the function
        let archive_path = format!("/tmp/{}.tar.gz", function_id);
        self.create_function_archive(&function_path, &archive_path).await?;

        // Read the archive bytes
        let archive_bytes = fs::read(&archive_path).await
            .with_context(|| format!("Failed to read archive: {}", archive_path))?;

        // Use the correct endpoint for function deployment
        let endpoint = format!("functions/{}/deployments", function_id);
        println!("📤 Deploying code using endpoint: {}", endpoint);

        let form = reqwest::multipart::Form::new()
            .part("code", reqwest::multipart::Part::bytes(archive_bytes.clone())
                .file_name(format!("{}.tar.gz", function_id))
                .mime_str("application/gzip")?)
            .part("activate", reqwest::multipart::Part::text("true"))
            .part("entrypoint", reqwest::multipart::Part::text("src/main.js"))
            .part("commands", reqwest::multipart::Part::text("npm install"));

        let url = format!("{}/{}", self.config.endpoint, endpoint);
        let response = self.client
            .post(&url)
            .header("X-Appwrite-Project", &self.config.project_id)
            .header("X-Appwrite-Key", &self.config.api_key)
            .header("X-Appwrite-Response-Format", "1.8.0")
            .multipart(form)
            .send()
            .await?;

        let status = response.status();
        let response_text = response.text().await?;

        // Clean up temporary archive
        let _ = fs::remove_file(&archive_path).await;

        if status.is_success() {
            println!("✅ Code deployed successfully using endpoint: {}", endpoint);
            return Ok(());
        } else {
            Err(anyhow!("Function deployment failed: {} - {}", status.as_u16(), response_text))
        }
    }

    async fn create_function_archive(&self, function_path: &Path, output_path: &str) -> Result<()> {
        use std::process::Command;

        let output = Command::new("tar")
            .args([
                "-czf", output_path,
                "-C", function_path.parent().unwrap().to_str().unwrap(),
                function_path.file_name().unwrap().to_str().unwrap()
            ])
            .output()
            .context("Failed to create function archive with tar")?;

        if !output.status.success() {
            return Err(anyhow::anyhow!(
                "tar command failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        Ok(())
    }

    async fn test_function_execution(&self, function_id: &str) -> Result<()> {
        // Simple test to see if function has code deployed
        let endpoint = format!("functions/{}/executions", function_id);
        let test_data = serde_json::json!({"test": "code_check"});

        match self
            .make_request::<serde_json::Value>(
                reqwest::Method::POST,
                &endpoint,
                Some(test_data),
            )
            .await
        {
            Ok(_) => Ok(()),
            Err(e) if e.to_string().contains("not found") || e.to_string().contains("404") => {
                Err(anyhow!("Function code not deployed"))
            },
            Err(e) => Err(e),
        }
    }

    pub async fn delete_function(&self, function_id: &str) -> Result<()> {
        let endpoint = format!("functions/{}", function_id);
        self.make_request::<serde_json::Value>(reqwest::Method::DELETE, &endpoint, None)
            .await
            .map(|_| ())
    }

    pub async fn clean_all_functions(&self) -> Result<()> {
        let functions = vec!["search_scripts", "process_purchase", "update_script_stats"];

        for function_id in functions {
            if self.function_exists(function_id).await? {
                println!("Deleting function: {}", function_id);
                self.delete_function(function_id).await?;
                println!("✅ Deleted function: {}", function_id);
            } else {
                println!("ℹ️ Function does not exist: {}", function_id);
            }
        }

        Ok(())
    }
}
