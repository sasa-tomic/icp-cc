use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum FavoritesError {
    #[error("io error: {0}")]
    Io(String),
    #[error("json error: {0}")]
    Json(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FavoriteEntry {
    pub canister_id: String,
    pub method: String,
    pub label: Option<String>,
}

fn config_path() -> PathBuf {
    // Try multiple fallback paths for better cross-platform compatibility
    if let Some(dir) = dirs::config_dir() {
        let path = dir.join("icp-cc").join("favorites.json");
        // Try to ensure parent directory exists and is writable
        if let Some(parent) = path.parent() {
            if parent.exists() || std::fs::create_dir_all(parent).is_ok() {
                return path;
            }
        }
    }

    // Fallback to home directory
    if let Some(home) = dirs::home_dir() {
        let path = home.join(".icp-cc").join("favorites.json");
        if let Some(parent) = path.parent() {
            if parent.exists() || std::fs::create_dir_all(parent).is_ok() {
                return path;
            }
        }
    }

    // Fallback to current directory
    PathBuf::from(".icp-cc-favorites.json")
}

fn ensure_parent(path: &Path) -> Result<(), FavoritesError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| FavoritesError::Io(e.to_string()))?;
    }
    Ok(())
}

pub fn load() -> Result<Vec<FavoriteEntry>, FavoritesError> {
    let path = config_path();
    if !path.exists() {
        return Ok(Vec::new());
    }
    let data = fs::read(&path).map_err(|e| FavoritesError::Io(e.to_string()))?;
    let entries: Vec<FavoriteEntry> =
        serde_json::from_slice(&data).map_err(|e| FavoritesError::Json(e.to_string()))?;
    Ok(entries)
}

pub fn save(entries: &[FavoriteEntry]) -> Result<(), FavoritesError> {
    let path = config_path();
    ensure_parent(&path)?;
    let json =
        serde_json::to_vec_pretty(entries).map_err(|e| FavoritesError::Json(e.to_string()))?;
    fs::write(&path, json).map_err(|e| FavoritesError::Io(e.to_string()))
}

pub fn add(entry: FavoriteEntry) -> Result<(), FavoritesError> {
    let mut entries = load()?;
    if !entries
        .iter()
        .any(|e| e.canister_id == entry.canister_id && e.method == entry.method)
    {
        entries.push(entry);
    }
    save(&entries)
}

pub fn remove(canister_id: &str, method: &str) -> Result<(), FavoritesError> {
    let mut entries = load()?;
    entries.retain(|e| !(e.canister_id == canister_id && e.method == method));
    save(&entries)
}

pub fn list() -> Result<Vec<FavoriteEntry>, FavoritesError> {
    load()
}
