use colored::*;
use std::path::PathBuf;
use anyhow::Result;

/// Get the project root directory by searching up the directory tree for a .git directory.
/// Falls back to the current working directory if no .git directory is found.
pub fn get_project_root() -> Result<PathBuf> {
    // Start from the current working directory
    let current_dir = std::env::current_dir()?;
    let mut current_path = current_dir.as_path();

    // Search up the directory tree for .git
    loop {
        let git_dir = current_path.join(".git");
        if git_dir.exists() && git_dir.is_dir() {
            return Ok(current_path.to_path_buf());
        }

        // Move to parent directory
        match current_path.parent() {
            Some(parent) => current_path = parent,
            None => {
                // No more parent directories, fall back to current working directory
                return Ok(current_dir);
            }
        }
    }
}

pub fn success_message(message: &str) {
    println!("✅ {}", message.bright_green());
}

pub fn info_message(message: &str) {
    println!("ℹ️  {}", message.bright_blue());
}

pub fn error_message(message: &str) {
    println!("❌ {}", message.bright_red());
}

pub fn section_header(title: &str) {
    println!("\n🚀 {}\n", title.bright_cyan().bold());
}

pub fn print_deployment_summary(config: &super::config::AppConfig) {
    println!();
    println!(
        "🎉 {}",
        "ICP Script Marketplace deployment completed successfully!".bright_green()
    );
    println!();
    println!("📊 Your marketplace is now ready with:");
    println!("   • Database: {}", config.database_id);
    println!("   • Scripts Collection: {}", config.scripts_collection_id);
    println!("   • Users Collection: {}", config.users_collection_id);
    println!("   • Reviews Collection: {}", config.reviews_collection_id);
    println!(
        "   • Purchases Collection: {}",
        config.purchases_collection_id
    );
    println!("   • Storage Bucket: {}", config.storage_bucket_id);
    println!("   • Appwrite Site: ICP Script Marketplace (SvelteKit)");
    println!();
    println!("🌐 Site Features:");
    println!("   • Frontend: SvelteKit web application");
    println!("   • API Routes: /api/* endpoints integrated with site");
    println!("   • Automatic deployment via Appwrite Sites");
    println!();
    println!("🔗 Next steps:");
    println!("   1. Visit your Appwrite Site to test the marketplace");
    println!("   2. Configure your Flutter app with the site URL");
    println!("   3. Test API endpoints via the site");
    println!();
    println!(
        "✨ {}",
        "Happy coding with ICP Script Marketplace!".bright_blue()
    );
}
