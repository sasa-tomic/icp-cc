use colored::*;

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
    println!("   • Cloud Functions: search_scripts, process_purchase, update_script_stats");
    println!();
    println!("🔗 Next steps:");
    println!("   1. Start API server: cd appwrite-api-server && npm start");
    println!("   2. Configure your Flutter app with API endpoint");
    println!("   3. Test integration");
    println!();
    println!(
        "✨ {}",
        "Happy coding with ICP Script Marketplace!".bright_blue()
    );
}
