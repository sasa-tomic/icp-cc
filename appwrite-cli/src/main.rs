use anyhow::{anyhow, Result};
use clap::{Parser, Subcommand};
use dialoguer::{Confirm, Input};
use indicatif::{ProgressBar, ProgressStyle};

mod config;
mod database;
mod functions;
mod utils;

use config::{AppConfig, DeployComponents};
use database::DatabaseManager;
use functions::FunctionManager;
use utils::{
    error_message, info_message, print_deployment_summary, section_header, success_message,
};

#[derive(Parser)]
#[command(
    name = "appwrite-cli",
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

    /// Deployment target (local or prod)
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
    let endpoint = if target == "local" {
        "http://localhost:48080/v1"
    } else {
        "https://fra.cloud.appwrite.io/v1"
    };

    section_header(&format!("Initializing ICP Script Marketplace ({})", target));

    let config = if let (Some(project_id), Some(api_key)) = (project_id, api_key) {
        AppConfig::new(project_id, api_key, endpoint.to_string())
    } else {
        // Interactive mode
        let project_id = Input::<String>::new()
            .with_prompt("Appwrite Project ID")
            .default("68f7fc8b00255b20ed42".to_string())
            .interact()?;

        let api_key = Input::<String>::new()
            .with_prompt("Appwrite API Key")
            .interact()?;

        AppConfig::new(project_id, api_key, endpoint.to_string())
    };

    config.save()?;
    success_message(&format!(
        "Configuration saved to {:?}",
        AppConfig::config_path()
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
    // Update configuration to use the correct endpoint based on target
    let mut config = AppConfig::load()?;

    if target == "local" && !config.endpoint.contains("localhost") {
        config.endpoint = "http://localhost:48080/v1".to_string();
        config.save()?;
    } else if target == "prod" && config.endpoint.contains("localhost") {
        config.endpoint = "https://fra.cloud.appwrite.io/v1".to_string();
        config.save()?;
    }
    if dry_run {
        section_header("DRY RUN - Deployment Preview");
    } else {
        section_header("Deploying ICP Script Marketplace");
    }

    // Load configuration
    let config = AppConfig::load()?;
    if !config.is_complete() {
        error_message("Configuration incomplete. Run 'appwrite-cli init' first.");
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
    let func_manager = FunctionManager::new(config.clone()).await?;
    pb.tick();

    // Clean existing resources if clean flag is set
    if clean && !dry_run {
        pb.set_message("Cleaning existing resources...");
        info_message("Cleaning existing resources before redeployment...");

        // Clean functions first
        if deploy_all || components.contains(&DeployComponents::Functions) {
            func_manager.clean_all_functions().await?;
        }

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

    // Deploy functions
    if deploy_all || components.contains(&DeployComponents::Functions) {
        if dry_run {
            pb.set_message("DRY RUN: Would deploy cloud functions");
        } else {
            pb.set_message("Deploying cloud functions...");
            func_manager.deploy_all_functions().await?;
        }
        pb.tick();
        info_message("Cloud Functions: search_scripts, process_purchase, update_script_stats");
    }

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

    let config = AppConfig::load()?;
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

    let config = AppConfig::load()?;

    println!("Project ID: {}", config.project_id);
    println!("Endpoint: {}", config.endpoint);
    println!("Database ID: {}", config.database_id);
    println!("Scripts Collection: {}", config.scripts_collection_id);
    println!("Users Collection: {}", config.users_collection_id);
    println!("Reviews Collection: {}", config.reviews_collection_id);
    println!("Purchases Collection: {}", config.purchases_collection_id);
    println!("Storage Bucket: {}", config.storage_bucket_id);
    println!("Config File: {:?}", AppConfig::config_path());

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
    section_header("Testing configuration and connectivity");

    let config = AppConfig::load()?;
    if !config.is_complete() {
        error_message("Configuration incomplete. Run 'appwrite-cli init' first.");
        return Err(anyhow!("Configuration incomplete"));
    }

    let pb = ProgressBar::new_spinner();
    pb.set_style(
        ProgressStyle::default_spinner()
            .template("{spinner:.green} [{elapsed_precise}] {msg}")
            .unwrap(),
    );

    // Test database connectivity
    pb.set_message("Testing database connectivity...");
    let db_manager = DatabaseManager::new(config.clone()).await?;
    match db_manager.test_database_access().await {
        Ok(_) => success_message("Database connectivity: OK"),
        Err(e) => error_message(&format!("Database connectivity: {}", e)),
    }

    // Test collection access
    pb.set_message("Testing collection access...");
    match db_manager.test_collection_access().await {
        Ok(_) => success_message("Collection access: OK"),
        Err(e) => error_message(&format!("Collection access: {}", e)),
    }

    pb.finish_with_message("Testing completed");

    Ok(())
}
