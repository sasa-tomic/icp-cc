use anyhow::{anyhow, Result};
use clap::{Parser, Subcommand};
use dialoguer::{Confirm, Input};
use indicatif::{ProgressBar, ProgressStyle};

mod config;
mod utils;

use config::{AppConfig, DeployComponents};
use utils::{error_message, info_message, section_header, success_message};

#[derive(Parser)]
#[command(
    name = "server-deploy",
    about = "Unified CLI for ICP Script Marketplace deployment on Cloudflare Workers",
    version = "2.0.0",
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
    /// Initialize Cloudflare Workers project configuration
    Init {
        /// Cloudflare Account ID
        #[arg(long)]
        account_id: Option<String>,

        /// Cloudflare API Token
        #[arg(long)]
        api_token: Option<String>,
    },
    /// Bootstrap fresh Cloudflare Workers instance with D1 database and deployment
    Bootstrap {
        /// Worker name for bootstrap
        #[arg(long, default_value = "icp-marketplace-api")]
        worker_name: String,

        /// Database name for bootstrap
        #[arg(long, default_value = "icp-marketplace-db")]
        database_name: String,

        /// Skip confirmation prompts
        #[arg(long)]
        yes: bool,
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
            account_id,
            api_token,
        } => handle_init(account_id, api_token, &cli.target).await,
        Commands::Bootstrap {
            worker_name,
            database_name,
            yes,
        } => handle_bootstrap(worker_name, database_name, yes, &cli.target).await,
        Commands::Deploy { components, clean } => {
            handle_deploy(cli.yes, components, cli.dry_run, clean, &cli.target).await
        }
        Commands::Clean => handle_clean(cli.yes, &cli.target).await,
        Commands::Config => handle_config(&cli.target).await,
        Commands::Test => handle_test(&cli.target).await,
    }
}

async fn handle_bootstrap(
    worker_name: String,
    database_name: String,
    yes: bool,
    target: &str,
) -> Result<()> {
    section_header(&format!(
        "Bootstrapping Cloudflare Workers Instance ({})",
        target
    ));

    // Confirm bootstrap operation
    if !yes {
        let confirm = dialoguer::Confirm::new()
            .with_prompt(
                "This will create a new D1 database and deploy Cloudflare Worker. Continue?",
            )
            .default(false)
            .interact()?;

        if !confirm {
            error_message("Bootstrap cancelled");
            return Ok(());
        }
    }

    // Change to cloudflare-api directory
    let repo_root = utils::get_project_root()?;
    let cloudflare_dir = repo_root.join("cloudflare-api");

    if !cloudflare_dir.exists() {
        return Err(anyhow!("cloudflare-api directory not found"));
    }

    // Create D1 database
    info_message(&format!("Creating D1 database: {}", database_name));
    let db_output = std::process::Command::new("wrangler")
        .args(["d1", "create", &database_name])
        .current_dir(&cloudflare_dir)
        .output()
        .map_err(|e| anyhow!("Failed to create D1 database: {}", e))?;

    if !db_output.status.success() {
        return Err(anyhow!(
            "D1 database creation failed: {}",
            String::from_utf8_lossy(&db_output.stderr)
        ));
    }

    // Extract database ID from output
    let db_output_str = String::from_utf8_lossy(&db_output.stdout);
    let db_id = extract_database_id(&db_output_str)?;

    success_message(&format!("D1 database created with ID: {}", db_id));

    // Update wrangler.jsonc with database ID
    update_wrangler_config(&cloudflare_dir, &database_name, &db_id)?;

    // Run database migrations
    info_message("Running database migrations...");
    let migrate_output = std::process::Command::new("wrangler")
        .args([
            "d1",
            "execute",
            &database_name,
            "--file",
            "migrations/0001_initial_schema.sql",
        ])
        .current_dir(&cloudflare_dir)
        .output()
        .map_err(|e| anyhow!("Failed to run migrations: {}", e))?;

    if !migrate_output.status.success() {
        return Err(anyhow!(
            "Database migrations failed: {}",
            String::from_utf8_lossy(&migrate_output.stderr)
        ));
    }

    success_message("Database migrations completed");

    // Deploy Worker
    info_message(&format!("Deploying Cloudflare Worker: {}", worker_name));
    let deploy_output = std::process::Command::new("wrangler")
        .args(["deploy"])
        .current_dir(&cloudflare_dir)
        .output()
        .map_err(|e| anyhow!("Failed to deploy Worker: {}", e))?;

    if !deploy_output.status.success() {
        return Err(anyhow!(
            "Worker deployment failed: {}",
            String::from_utf8_lossy(&deploy_output.stderr)
        ));
    }

    success_message("Cloudflare Worker deployed successfully!");

    // Get worker URL
    let worker_url = get_worker_url(&worker_name)?;

    // Save configuration
    let mut config = AppConfig::load(target)?;
    config.worker_name = worker_name.clone();
    config.database_name = database_name.clone();
    config.database_id = db_id.clone();
    config.worker_url = worker_url.clone();
    config.save(target)?;

    success_message("Cloudflare Workers bootstrap completed successfully!");
    info_message(&format!("Worker: {}", worker_name));
    info_message(&format!("Database: {}", database_name));
    info_message(&format!("Worker URL: {}", worker_url));

    success_message("You can now test API endpoints and update your Flutter app configuration");

    Ok(())
}

fn extract_database_id(output: &str) -> Result<String> {
    // Look for database ID in wrangler output
    // Format: "Database {database_id} created successfully"
    for line in output.lines() {
        if line.contains("Database") && line.contains("created") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            for (i, part) in parts.iter().enumerate() {
                if *part == "Database" && i + 1 < parts.len() {
                    return Ok(parts[i + 1].to_string());
                }
            }
        }
    }
    Err(anyhow!(
        "Could not extract database ID from wrangler output"
    ))
}

fn update_wrangler_config(
    cloudflare_dir: &std::path::Path,
    database_name: &str,
    database_id: &str,
) -> Result<()> {
    let config_path = cloudflare_dir.join("wrangler.jsonc");
    let config_content = std::fs::read_to_string(&config_path)?;

    // Update database configuration
    let updated_content = config_content
        .replace(
            "\"database_name\": \"icp-marketplace-db\"",
            &format!("\"database_name\": \"{}\"", database_name),
        )
        .replace(
            "\"database_id\": \"local\"",
            &format!("\"database_id\": \"{}\"", database_id),
        );

    std::fs::write(&config_path, updated_content)?;
    success_message("Updated wrangler.jsonc with database configuration");

    Ok(())
}

fn get_worker_url(worker_name: &str) -> Result<String> {
    // For now, return a default URL pattern
    // In a real implementation, you might extract this from wrangler output
    Ok(format!("https://{}.workers.dev", worker_name))
}

async fn handle_init(
    account_id: Option<String>,
    api_token: Option<String>,
    target: &str,
) -> Result<()> {
    section_header(&format!("Initializing ICP Script Marketplace ({})", target));

    let config = if let (Some(account_id), Some(api_token)) = (account_id, api_token) {
        AppConfig::new(account_id, api_token)
    } else {
        // Interactive mode
        let account_id = Input::<String>::new()
            .with_prompt("Cloudflare Account ID")
            .interact()?;

        let api_token = Input::<String>::new()
            .with_prompt("Cloudflare API Token")
            .interact()?;

        AppConfig::new(account_id, api_token)
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
    _clean: bool,
    target: &str,
) -> Result<()> {
    // Load configuration for target
    let config = AppConfig::load(target)?;
    if dry_run {
        section_header("DRY RUN - Deployment Preview");
    } else {
        section_header("Deploying ICP Script Marketplace to Cloudflare Workers");
    }

    if !config.is_complete() {
        error_message("Configuration incomplete. Run 'server-deploy init' first.");
        return Err(anyhow!("Configuration incomplete"));
    }

    // Confirm deployment
    if !dry_run && !yes {
        let confirm = Confirm::new()
            .with_prompt(
                "This will deploy marketplace infrastructure to Cloudflare Workers. Continue?",
            )
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

    // Change to cloudflare-api directory
    let repo_root = utils::get_project_root()?;
    let cloudflare_dir = repo_root.join("cloudflare-api");

    if !cloudflare_dir.exists() {
        return Err(anyhow!("cloudflare-api directory not found"));
    }

    // Deploy Worker
    if deploy_all || components.contains(&DeployComponents::Worker) {
        if dry_run {
            pb.set_message("DRY RUN: Would deploy Cloudflare Worker");
        } else {
            pb.set_message("Deploying Cloudflare Worker...");
            let deploy_output = std::process::Command::new("wrangler")
                .args(["deploy"])
                .current_dir(&cloudflare_dir)
                .output()
                .map_err(|e| anyhow!("Failed to deploy Worker: {}", e))?;

            if !deploy_output.status.success() {
                return Err(anyhow!(
                    "Worker deployment failed: {}",
                    String::from_utf8_lossy(&deploy_output.stderr)
                ));
            }
        }
        pb.tick();
        info_message(&format!("Worker: {}", config.worker_name));
    }

    // Deploy database migrations if needed
    if deploy_all || components.contains(&DeployComponents::Database) {
        if dry_run {
            pb.set_message("DRY RUN: Would run database migrations");
        } else {
            pb.set_message("Running database migrations...");
            let migrate_output = std::process::Command::new("wrangler")
                .args([
                    "d1",
                    "execute",
                    &config.database_name,
                    "--file",
                    "migrations/0001_initial_schema.sql",
                ])
                .current_dir(&cloudflare_dir)
                .output()
                .map_err(|e| anyhow!("Failed to run migrations: {}", e))?;

            if !migrate_output.status.success() {
                return Err(anyhow!(
                    "Database migrations failed: {}",
                    String::from_utf8_lossy(&migrate_output.stderr)
                ));
            }
        }
        pb.tick();
        info_message(&format!("Database: {}", config.database_name));
    }

    pb.finish_with_message("Cloudflare Workers deployment completed!");

    if !dry_run {
        success_message(&format!(
            "Worker deployed successfully: {}",
            config.worker_name
        ));
        info_message(&format!("Database: {}", config.database_name));
        if !config.worker_url.is_empty() {
            info_message(&format!("Worker URL: {}", config.worker_url));
        }
    }

    Ok(())
}

async fn handle_clean(yes: bool, target: &str) -> Result<()> {
    section_header("Cleaning up Cloudflare Workers resources");

    if !yes {
        let confirm = Confirm::new()
            .with_prompt("This will delete Cloudflare Worker and D1 database. Are you sure?")
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

    // Change to cloudflare-api directory
    let repo_root = utils::get_project_root()?;
    let cloudflare_dir = repo_root.join("cloudflare-api");

    if !cloudflare_dir.exists() {
        return Err(anyhow!("cloudflare-api directory not found"));
    }

    info_message("Deleting D1 database...");
    let delete_db_output = std::process::Command::new("wrangler")
        .args(["d1", "delete", &config.database_name, "--yes"])
        .current_dir(&cloudflare_dir)
        .output()
        .map_err(|e| anyhow!("Failed to delete D1 database: {}", e))?;

    if !delete_db_output.status.success() {
        error_message(&format!(
            "D1 database deletion warning: {}",
            String::from_utf8_lossy(&delete_db_output.stderr)
        ));
    } else {
        success_message("D1 database deleted successfully");
    }

    info_message("Deleting Cloudflare Worker...");
    let delete_worker_output = std::process::Command::new("wrangler")
        .args(["delete", &config.worker_name, "--yes"])
        .current_dir(&cloudflare_dir)
        .output()
        .map_err(|e| anyhow!("Failed to delete Worker: {}", e))?;

    if !delete_worker_output.status.success() {
        error_message(&format!(
            "Worker deletion warning: {}",
            String::from_utf8_lossy(&delete_worker_output.stderr)
        ));
    } else {
        success_message("Cloudflare Worker deleted successfully");
    }

    success_message("Cloudflare Workers cleanup completed");

    Ok(())
}

async fn handle_config(target: &str) -> Result<()> {
    section_header(&format!("Current Configuration ({})", target));

    let config = AppConfig::load(target)?;

    println!("Account ID: {}", config.account_id);
    println!("Worker Name: {}", config.worker_name);
    println!("Database Name: {}", config.database_name);
    println!("Database ID: {}", config.database_id);
    println!("Worker URL: {}", config.worker_url);
    println!("Config File: {:?}", AppConfig::config_path(target));

    if config.api_token.is_empty() {
        error_message("API Token not configured");
    } else {
        let masked_token = format!(
            "{}...",
            &config.api_token[..config.api_token.len().saturating_sub(3).min(40)]
        );
        println!("API Token: {}", masked_token);
    }

    Ok(())
}

async fn handle_test(target: &str) -> Result<()> {
    let is_production = target == "prod";
    let env_name = if is_production { "Production" } else { "Local" };

    section_header(&format!(
        "🚀 Running Cloudflare Workers smoke test - {} environment",
        env_name
    ));

    let config = AppConfig::load(target)?;
    if !config.is_complete() {
        error_message("Configuration incomplete. Run 'server-deploy init' first.");
        return Err(anyhow!("Configuration incomplete"));
    }

    // Display environment info
    println!();
    info_message(&format!("📍 Worker Name: {}", config.worker_name));
    info_message(&format!("🗄️ Database: {}", config.database_name));
    if !config.worker_url.is_empty() {
        info_message(&format!("🌐 Worker URL: {}", config.worker_url));
    }
    if is_production {
        info_message("⚠️  Running against production environment - be careful!");
    }
    println!();

    let mut tests_passed = 0;
    let mut tests_failed = 0;

    // Test Worker URL
    let worker_url = if !config.worker_url.is_empty() {
        config.worker_url.clone()
    } else if is_production {
        format!("https://{}.workers.dev", config.worker_name)
    } else {
        "http://localhost:8787".to_string()
    };

    // Test basic connectivity
    info_message("📡 Testing Worker connectivity...");
    match test_worker_connectivity(&worker_url).await {
        Ok(_) => {
            success_message("Worker connectivity: OK");
            tests_passed += 1;
        }
        Err(e) => {
            error_message(&format!("Worker connectivity: {}", e));
            tests_failed += 1;
        }
    }

    // Test API endpoints
    info_message("🔗 Testing API endpoints...");
    match test_cloudflare_api_endpoints(&worker_url).await {
        Ok(_) => {
            success_message("API endpoints: OK");
            tests_passed += 1;
        }
        Err(e) => {
            error_message(&format!("API endpoints: {}", e));
            tests_failed += 1;
        }
    }

    // Test database access through API
    info_message("🗄️ Testing database access through API...");
    match test_database_via_api(&worker_url).await {
        Ok(_) => {
            success_message("Database access: OK");
            tests_passed += 1;
        }
        Err(e) => {
            error_message(&format!("Database access: {}", e));
            tests_failed += 1;
        }
    }

    // Summary
    println!();
    section_header("📊 Test Results Summary");
    if tests_failed == 0 {
        success_message(&format!("✅ All {} tests passed!", tests_passed));
        success_message(&format!(
            "🎉 {} Cloudflare Workers API is working correctly!",
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
        error_message("🔧 Check failed tests above for troubleshooting");
        return Err(anyhow!("Some tests failed"));
    }

    Ok(())
}

async fn test_worker_connectivity(worker_url: &str) -> Result<()> {
    let client = reqwest::Client::new();

    let response = client
        .get(format!("{}/health", worker_url))
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;

    if response.status().is_success() {
        Ok(())
    } else {
        Err(anyhow!(
            "Worker connectivity test failed: {}",
            response.status()
        ))
    }
}

async fn test_cloudflare_api_endpoints(worker_url: &str) -> Result<()> {
    let client = reqwest::Client::new();

    // Test marketplace stats endpoint
    let stats_response = client
        .get(format!("{}/api/marketplace-stats", worker_url))
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;

    if stats_response.status().is_success() {
        success_message("  Marketplace stats endpoint working");
    } else {
        return Err(anyhow!(
            "Marketplace stats endpoint failed: {}",
            stats_response.status()
        ));
    }

    // Test scripts search endpoint
    let search_response = client
        .post(format!("{}/api/scripts/search", worker_url))
        .header("Content-Type", "application/json")
        .body(r#"{"query": "test", "limit": 5}"#)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;

    if search_response.status().is_success() {
        success_message("  Scripts search endpoint working");
    } else {
        return Err(anyhow!(
            "Scripts search endpoint failed: {}",
            search_response.status()
        ));
    }

    Ok(())
}

async fn test_database_via_api(worker_url: &str) -> Result<()> {
    let client = reqwest::Client::new();

    // Test database access by getting scripts list
    let scripts_response = client
        .get(format!("{}/api/scripts?limit=1", worker_url))
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await?;

    if scripts_response.status().is_success() {
        success_message("  Database access through API working");
    } else {
        return Err(anyhow!(
            "Database access test failed: {}",
            scripts_response.status()
        ));
    }

    Ok(())
}
