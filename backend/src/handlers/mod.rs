//! HTTP request handlers, grouped one module per domain.
//!
//! Mirrors the `services/` + `repositories/` layout: each domain's
//! `#[handler]` functions live in their own file (`health.rs`, `scripts.rs`,
//! …) and are re-exported here for the route table in `main`.

pub mod health;

pub use health::{health_check, ping};
