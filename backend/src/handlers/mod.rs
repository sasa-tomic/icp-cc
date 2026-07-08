//! HTTP request handlers, grouped one module per domain.
//!
//! Mirrors the `services/` + `repositories/` layout: each domain's
//! `#[handler]` functions live in their own file (`health.rs`, `scripts.rs`,
//! …) and are re-exported here for the route table in `main`.

pub mod health;
pub mod recovery;
pub mod reviews;
pub mod vault;

pub use health::{health_check, ping};
pub use recovery::{recovery_generate, recovery_status, recovery_verify};
pub use reviews::{create_review, get_reviews};
pub use vault::{vault_create, vault_get, vault_update};
