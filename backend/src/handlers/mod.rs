//! HTTP request handlers, grouped one module per domain.
//!
//! Mirrors the `services/` + `repositories/` layout: each domain's
//! `#[handler]` functions live in their own file (`health.rs`, `scripts.rs`,
//! …) and are re-exported here for the route table in `main`.

pub mod accounts;
pub mod admin;
pub mod health;
pub mod passkey;
pub mod recovery;
pub mod reviews;
pub mod vault;

pub use accounts::{
    add_account_key, get_account, get_account_by_public_key, register_account, remove_account_key,
    update_account,
};
pub use admin::{admin_add_recovery_key, admin_disable_key, reset_database};
pub use health::{health_check, ping};
pub use passkey::{
    passkey_authenticate_finish, passkey_authenticate_start, passkey_delete, passkey_list,
    passkey_register_finish, passkey_register_start,
};
pub use recovery::{recovery_generate, recovery_status, recovery_verify};
pub use reviews::{create_review, get_reviews};
pub use vault::{vault_create, vault_get, vault_update};
