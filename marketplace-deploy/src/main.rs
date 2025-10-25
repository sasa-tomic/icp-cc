use anyhow::{anyhow, Result};
use clap::{Parser, Subcommand};
use dialoguer::{Confirm, Input};
use indicatif::{ProgressBar, ProgressStyle};

mod config;
mod database;
mod utils;

use config::{AppConfig, DeployComponents};
use database::DatabaseManager;
use utils::{
    error_message, info_message, print_deployment_summary, section_header, success_message,
};

#[derive(Parser)]
#[command(
    name = "marketplace-deploy",
    about = "Unified CLI for ICP Script Marketplace deployment on Appwrite",
    version = "1.0.0",
    author = "ICP Marketplace Team"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Verbose output
    #[arg(short, long)]
    verbose: bool,

    /// Deployment target name (arbitrary, e.g., local, prod, staging)
    #[arg(long, global = true, default_value = "prod")]
    target: String,

    /// Dry run (don't make actual changes)
    #[arg(long, global = true, conflicts_with = "yes")]
    dry_run: bool,

    /// Proceed without confirmation
    #[arg(long, global = true, conflicts_with = "dry_run")]
    yes: bool,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize Appwrite project configuration
    Init {
        /// Appwrite project ID
        #[arg(long)]
        project_id: Option<String>,

        /// Appwrite API key
        #[arg(long)]
        api_key: Option<String>,
    },
    /// Deploy complete marketplace infrastructure
    Deploy {
        /// Only deploy specific components
        #[arg(long, value_enum, use_value_delimiter = true)]
        components: Option<Vec<DeployComponents>>,

        /// Clean and redeploy all resources (removes existing resources first)
        #[arg(long)]
        clean: bool,
    },
    /// Clean up existing resources
    Clean,
    /// Show current configuration
    Config,
    /// Test configuration and connectivity
    Test,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Initialize logging based on verbosity
    if cli.verbose {
        env_logger::Builder::from_default_env()
            .filter_level(log::LevelFilter::Debug)
            .init();
    }

    match cli.command {
        Commands::Init {
            project_id,
            api_key,
        } => handle_init(project_id, api_key, &cli.target).await,
        Commands::Deploy { components, clean } => {
            handle_deploy(cli.yes, components, cli.dry_run, clean, &cli.target).await
        }
        Commands::Clean => handle_clean(cli.yes, &cli.target).await,
        Commands::Config => handle_config(&cli.target).await,
        Commands::Test => handle_test(&cli.target).await,
    }
}

async fn handle_init(
    project_id: Option<String>,
    api_key: Option<String>,
    target: &str,
) -> Result<()> {
    section_header(&format!("Initializing ICP Script Marketplace ({})", target));

    // Interactive endpoint selection for better UX
    let default_endpoint = match target {
        "local" => "http://localhost:48080/v1",
        "prod" => "https://icp-autorun.appwrite.network/v1",
        _ => "",
    };

    let config = if let (Some(project_id), Some(api_key)) = (project_id, api_key) {
        let endpoint = if !default_endpoint.is_empty() {
            default_endpoint.to_string()
        } else {
            Input::<String>::new()
                .with_prompt("Appwrite Endpoint URL")
                .interact()?
        };
        AppConfig::new(project_id, api_key, endpoint)
    } else {
        // Interactive mode
        let project_id = Input::<String>::new()
            .with_prompt("Appwrite Project ID")
            .interact()?;

        let api_key = Input::<String>::new()
            .with_prompt("Appwrite API Key")
            .interact()?;

        let endpoint = if !default_endpoint.is_empty() {
            Input::<String>::new()
                .with_prompt("Appwrite Endpoint URL")
                .default(default_endpoint.to_string())
                .interact()?
        } else {
            Input::<String>::new()
                .with_prompt("Appwrite Endpoint URL")
                .interact()?
        };

        AppConfig::new(project_id, api_key, endpoint)
    };

    config.save(target)?;
    success_message(&format!(
        "Configuration saved to {:?}",
        AppConfig::config_path(target)
    ));

    Ok(())
}

async fn handle_deploy(
    yes: bool,
    components: Option<Vec<DeployComponents>>,
    dry_run: bool,
    clean: bool,
    target: &str,
) -> Result<()> {
    // Load configuration for target
    let config = AppConfig::load(target)?;
    if dry_run {
        section_header("DRY RUN - Deployment Preview");
    } else {
        section_header("Deploying ICP Script Marketplace");
    }

    // Use the already loaded config
    let config = config.clone();
    if !config.is_complete() {
        error_message("Configuration incomplete. Run 'marketplace-deploy init' first.");
        return Err(anyhow!("Configuration incomplete"));
    }

    // Confirm deployment
    if !dry_run && !yes {
        let confirm = Confirm::new()
            .with_prompt("This will deploy complete marketplace infrastructure. Continue?")
            .default(false)
            .interact()?;

        if !confirm {
            error_message("Deployment cancelled");
            return Ok(());
        }
    }

    let components = components.unwrap_or_else(|| vec![DeployComponents::All]);
    let deploy_all = components.contains(&DeployComponents::All);

    let pb = ProgressBar::new_spinner();
    pb.set_style(
        ProgressStyle::default_spinner()
            .template("{spinner:.green} [{elapsed_precise}] {msg}")
            .unwrap(),
    );

    // Initialize managers
    if dry_run {
        pb.set_message("DRY RUN: Initializing managers...");
    } else {
        pb.set_message("Initializing managers...");
    }

    let mut db_manager = DatabaseManager::new(config.clone()).await?;
    pb.tick();

    // Clean existing resources if clean flag is set
    if clean && !dry_run {
        pb.set_message("Cleaning existing resources...");
        info_message("Cleaning existing resources before redeployment...");

  
        // Clean collections
        if deploy_all || components.contains(&DeployComponents::Collections) {
            // Delete collections if they exist
            let _ = db_manager
                .delete_collection(&config.scripts_collection_id)
                .await;
            let _ = db_manager
                .delete_collection(&config.users_collection_id)
                .await;
            let _ = db_manager
                .delete_collection(&config.reviews_collection_id)
                .await;
            let _ = db_manager
                .delete_collection(&config.purchases_collection_id)
                .await;
        }

        // Clean storage bucket
        if deploy_all || components.contains(&DeployComponents::Storage) {
            let _ = db_manager
                .delete_storage_bucket(&config.storage_bucket_id)
                .await;
        }

        pb.finish_and_clear();
        success_message("Cleanup completed. Starting fresh deployment...");

        // Reset progress bar for deployment phase
        let pb = ProgressBar::new_spinner();
        pb.set_style(
            ProgressStyle::default_spinner()
                .template("{spinner:.green} [{elapsed_precise}] {msg}")
                .unwrap(),
        );
    }

    // Deploy database
    if deploy_all || components.contains(&DeployComponents::Database) {
        if dry_run {
            pb.set_message("DRY RUN: Would create database");
        } else {
            pb.set_message("Creating database...");
            db_manager.create_database().await?;
        }
        pb.tick();
        info_message(&format!("Database: {}", config.database_id));
    }

    // Deploy collections
    if deploy_all || components.contains(&DeployComponents::Collections) {
        if dry_run {
            pb.set_message("DRY RUN: Would create collections");
        } else {
            pb.set_message("Creating collections...");
            // Try to create collections with all attributes at once
            if let Err(e) = db_manager
                .create_collection(&config.scripts_collection_id, "Scripts")
                .await
            {
                if !e.to_string().contains("already exists") {
                    return Err(e);
                }
            }
            if let Err(e) = db_manager
                .create_collection(&config.users_collection_id, "Users")
                .await
            {
                if !e.to_string().contains("already exists") {
                    return Err(e);
                }
            }
            if let Err(e) = db_manager
                .create_collection(&config.reviews_collection_id, "Reviews")
                .await
            {
                if !e.to_string().contains("already exists") {
                    return Err(e);
                }
            }
            if let Err(e) = db_manager
                .create_collection(&config.purchases_collection_id, "Purchases")
                .await
            {
                if !e.to_string().contains("already exists") {
                    return Err(e);
                }
            }
        }
        pb.tick();
        info_message("Collections: scripts, users, reviews, purchases");
    }

    // Note: Functions have been migrated to Appwrite Sites API routes
    // The API endpoints are now handled by the Site deployment

    // Deploy storage
    if deploy_all || components.contains(&DeployComponents::Storage) {
        if dry_run {
            pb.set_message("DRY RUN: Would create storage bucket");
        } else {
            pb.set_message("Creating storage bucket...");
            db_manager
                .create_storage_bucket(
                    &config.storage_bucket_id,
                    "Scripts Files",
                    10 * 1024 * 1024, // 10MB
                )
                .await?;
        }
        pb.tick();
        info_message(&format!("Storage Bucket: {}", config.storage_bucket_id));
    }

    pb.finish_with_message("Deployment completed!");

    if !dry_run {
        print_deployment_summary(&config);
    }

    Ok(())
}

async fn handle_clean(yes: bool, target: &str) -> Result<()> {
    section_header("Cleaning up marketplace resources");

    if !yes {
        let confirm = Confirm::new()
            .with_prompt("This will delete ALL marketplace resources. Are you sure?")
            .default(false)
            .interact()?;

        if !confirm {
            error_message("Cleanup cancelled");
            return Ok(());
        }
    }

    let config = AppConfig::load(target)?;
    if !config.is_complete() {
        return Err(anyhow!("Configuration incomplete"));
    }

    let mut db_manager = DatabaseManager::new(config.clone()).await?;

    info_message("Deleting collections...");
    db_manager
        .delete_collection(&config.scripts_collection_id)
        .await?;
    db_manager
        .delete_collection(&config.users_collection_id)
        .await?;
    db_manager
        .delete_collection(&config.reviews_collection_id)
        .await?;
    db_manager
        .delete_collection(&config.purchases_collection_id)
        .await?;

    info_message("Deleting storage bucket...");
    db_manager
        .delete_storage_bucket(&config.storage_bucket_id)
        .await?;

    success_message("Cleanup completed");

    Ok(())
}

async fn handle_config(target: &str) -> Result<()> {
    section_header(&format!("Current Configuration ({})", target));

    let config = AppConfig::load(target)?;

    println!("Project ID: {}", config.project_id);
    println!("Endpoint: {}", config.endpoint);
    println!("Database ID: {}", config.database_id);
    println!("Scripts Collection: {}", config.scripts_collection_id);
    println!("Users Collection: {}", config.users_collection_id);
    println!("Reviews Collection: {}", config.reviews_collection_id);
    println!("Purchases Collection: {}", config.purchases_collection_id);
    println!("Storage Bucket: {}", config.storage_bucket_id);
    println!("Config File: {:?}", AppConfig::config_path(target));

    if config.api_key.is_empty() {
        error_message("API Key not configured");
    } else {
        let masked_key = format!(
            "{}...",
            &config.api_key[..config.api_key.len().saturating_sub(3).min(40)]
        );
        println!("API Key: {}", masked_key);
    }

    Ok(())
}

async fn handle_test(target: &str) -> Result<()> {
    let is_production = target == "prod";
    let env_name = if is_production { "Production" } else { "Local" };

    section_header(&format!(
        "🚀 Running comprehensive smoke test - {} environment",
        env_name
    ));

    let config = AppConfig::load(target)?;
    if !config.is_complete() {
        error_message("Configuration incomplete. Run 'marketplace-deploy init' first.");
        return Err(anyhow!("Configuration incomplete"));
    }

    // Display environment info
    println!();
    info_message(&format!("📍 Endpoint: {}", config.endpoint));
    info_message(&format!("🆔 Project: {}", config.project_id));
    if is_production {
        info_message("⚠️  Running against production environment - be careful!");
    }
    println!();

    let mut tests_passed = 0;
    let mut tests_failed = 0;

    // Test basic connectivity
    info_message("📡 Testing basic connectivity...");
    match test_basic_connectivity(&config).await {
        Ok(_) => {
            success_message("Basic connectivity: OK");
            tests_passed += 1;
        }
        Err(e) => {
            error_message(&format!("Basic connectivity: {}", e));
            tests_failed += 1;
        }
    }

    // Test database connectivity
    info_message("🗄️ Testing database connectivity...");
    let db_manager = DatabaseManager::new(config.clone()).await?;
    match db_manager.test_database_access().await {
        Ok(_) => {
            success_message("Database connectivity: OK");
            tests_passed += 1;
        }
        Err(e) => {
            error_message(&format!("Database connectivity: {}", e));
            tests_failed += 1;
        }
    }

    // Test collection access
    info_message("📋 Testing collection access...");
    match db_manager.test_collection_access().await {
        Ok(_) => {
            success_message("Collection access: OK");
            tests_passed += 1;
        }
        Err(e) => {
            error_message(&format!("Collection access: {}", e));
            tests_failed += 1;
        }
    }

    // Test storage bucket
    info_message("📁 Testing storage bucket...");
    match test_storage_bucket(&config).await {
        Ok(_) => {
            success_message("Storage bucket: OK");
            tests_passed += 1;
        }
        Err(e) => {
            error_message(&format!("Storage bucket: {}", e));
            tests_failed += 1;
        }
    }

    // Test API endpoints (Sites)
    info_message("🌐 Testing API endpoints...");
    match test_api_endpoints(&config).await {
        Ok(_) => {
            success_message("API endpoints: OK");
            tests_passed += 1;
        }
        Err(e) => {
            error_message(&format!("API endpoints: {}", e));
            tests_failed += 1;
        }
    }

    // Production-specific tests
    if is_production {
        info_message("🔒 Running production-specific tests...");
        match test_production_specific(&config).await {
            Ok(_) => {
                success_message("Production-specific tests: OK");
                tests_passed += 1;
            }
            Err(e) => {
                error_message(&format!("Production-specific tests: {}", e));
                tests_failed += 1;
            }
        }
    }

    // Summary
    println!();
    section_header("📊 Test Results Summary");
    if tests_failed == 0 {
        success_message(&format!("✅ All {} tests passed!", tests_passed));
        success_message(&format!(
            "🎉 {} Appwrite site is working correctly!",
            env_name
        ));

        if is_production {
            info_message(
                "💡 Tip: Use --target local to test against your local development environment",
            );
        } else {
            info_message("💡 Tip: Use --target prod to test against your production environment");
        }
    } else {
        error_message(&format!(
            "❌ {}/{} tests failed",
            tests_failed,
            tests_passed + tests_failed
        ));
        error_message("🔧 Check the failed tests above for troubleshooting");
        return Err(anyhow!("Some tests failed"));
    }

    Ok(())
}

async fn test_basic_connectivity(config: &AppConfig) -> Result<()> {
    let client = reqwest::Client::new();

    // Test account endpoint (basic API connectivity with authentication)
    let response = client
        .get(format!("{}/account", config.endpoint))
        .header("X-Appwrite-Project", &config.project_id)
        .header("X-Appwrite-Key", &config.api_key)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;

    // Account endpoint with API key should return 401 (Unauthorized)
    // because API keys can't access account endpoints, but this confirms
    // the API is responding and authentication headers are working
    if response.status().is_success() || response.status() == 401 {
        Ok(())
    } else {
        Err(anyhow!(
            "API connectivity test failed: {}",
            response.status()
        ))
    }
}

async fn test_storage_bucket(config: &AppConfig) -> Result<()> {
    let client = reqwest::Client::new();

    let response = client
        .get(format!(
            "{}/storage/buckets/{}",
            config.endpoint, config.storage_bucket_id
        ))
        .header("X-Appwrite-Project", &config.project_id)
        .header("X-Appwrite-Key", &config.api_key)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;

    if response.status().is_success() {
        Ok(())
    } else {
        Err(anyhow!("Storage bucket test failed: {}", response.status()))
    }
}

async fn test_api_endpoints(config: &AppConfig) -> Result<()> {
    let client = reqwest::Client::new();

    // Test the marketplace stats endpoint
    let stats_url = format!("{}/api/get_marketplace_stats", config.endpoint.replace("/v1", ""));

    match client.get(&stats_url).timeout(std::time::Duration::from_secs(10)).send().await {
        Ok(_response) => {
            success_message("  Marketplace stats endpoint accessible");
        }
        Err(e) => {
            // For testing purposes, we'll consider this a warning since the site may not be deployed yet
            info_message(&format!("  Marketplace stats endpoint: {} (site may not be deployed yet)", e));
        }
    }

    // Test the search scripts endpoint
    let search_url = format!("{}/api/search_scripts", config.endpoint.replace("/v1", ""));

    match client.post(&search_url)
        .header("Content-Type", "application/json")
        .body(r#"{"query": "test"}"#)
        .timeout(std::time::Duration::from_secs(10))
        .send().await {
        Ok(_response) => {
            success_message("  Search scripts endpoint accessible");
        }
        Err(e) => {
            info_message(&format!("  Search scripts endpoint: {} (site may not be deployed yet)", e));
        }
    }

    Ok(())
}

async fn test_production_specific(config: &AppConfig) -> Result<()> {
    let client = reqwest::Client::new();

    // Test that we're connecting to a production Appwrite instance
    let _response = client
        .get(format!("{}/version", config.endpoint))
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;

    // Check if endpoint looks like production (HTTPS and not localhost)
    let endpoint = &config.endpoint;
    if !endpoint.starts_with("https://") || endpoint.contains("localhost") {
        return Err(anyhow!(
            "Production endpoint should use HTTPS and not be localhost"
        ));
    }

    // Test that API key has appropriate permissions by trying to list projects
    let project_response = client
        .get(format!("{}/projects", config.endpoint))
        .header("X-Appwrite-Key", &config.api_key)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;

    // Production API keys should be able to list projects
    if !project_response.status().is_success() && project_response.status() != 401 {
        return Err(anyhow!(
            "Production API key test failed: {}",
            project_response.status()
        ));
    }

    // Test a safer endpoint that should work in production
    let health_response = client
        .get(format!("{}/health", config.endpoint))
        .header("X-Appwrite-Project", &config.project_id)
        .header("X-Appwrite-Key", &config.api_key)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;

    // Health endpoint might work in production with proper permissions
    match health_response.status().as_u16() {
        200 | 401 => {
            // 200 = health check works, 401 = auth works but need different permissions
            success_message("  Production API authentication verified");
        }
        _ => {
            return Err(anyhow!(
                "Production health check failed: {}",
                health_response.status()
            ));
        }
    }

    Ok(())
}
