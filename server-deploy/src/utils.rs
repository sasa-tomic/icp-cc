use anyhow::Result;
use colored::*;
use std::path::PathBuf;

/// Get project root directory by searching up the directory tree for a .git directory.
/// Falls back to current working directory if no .git directory is found.
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
