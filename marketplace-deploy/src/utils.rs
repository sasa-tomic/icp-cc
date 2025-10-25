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
