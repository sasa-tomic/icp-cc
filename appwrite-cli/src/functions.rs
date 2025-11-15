use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::time::Duration;

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
    pub status: String,
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
        match self
            .make_request::<serde_json::Value>(reqwest::Method::GET, &endpoint, None)
            .await
        {
            Ok(_) => Ok(true),
            Err(e) if e.to_string().contains("not found") => Ok(false),
            Err(e) => Err(e),
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
            "events": events.unwrap_or_else(|| vec!["[]".to_string()])
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
                Some(vec!["databases.*.documents.create".to_string()]),
            ),
        ];

        for (func_id, name, runtime, events) in functions {
            if !self.function_exists(func_id).await? {
                println!("Creating function: {}", name);
                self.create_function(func_id, name, runtime, events).await?;

                // Test function creation
                self.test_function(func_id, r#"{"test": "deployment"}"#)
                    .await?;
                println!("✅ Created function: {}", name);
            } else {
                println!("ℹ️ Function already exists: {}", name);
            }
        }

        Ok(())
    }
}
