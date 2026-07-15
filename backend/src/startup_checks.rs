//! Startup-time configuration validation helpers.
//!
//! These functions run once at boot (from `main`) to surface insecure or
//! broken configurations LOUDLY (clear `tracing::error!`/`warn!` + stderr)
//! instead of silently degrading. They do NOT crash the process — the
//! marketplace still boots — but they make misconfiguration impossible to
//! miss in logs.
//!
//! `verify_script_ownership` is a runtime helper used by the script
//! write-path handlers (`update_script`, `delete_script`); it lives here
//! alongside the other request-independent predicates.

use std::{env, sync::Arc};

use poem::{http::StatusCode, Response};

use crate::{models::AppState, responses::error_response};

// ============================================================================
// Environment — the single source of truth for the `ENVIRONMENT` env var
// (W7-014). Previously two readers disagreed: `main.rs`'s warn helpers treated
// unset as "development" (suppressing the insecure-admin-token warning), while
// `is_development()` read the raw var with `unwrap_or_default()` (returning
// false on unset). A prod deploy that forgot to set `ENVIRONMENT` therefore
// shipped the default admin token with NO warning. This enum is read in
// exactly one place and every consumer goes through it.
// ============================================================================

static CURRENT_ENV: std::sync::OnceLock<Environment> = std::sync::OnceLock::new();

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Environment {
    Development,
    Production,
}

impl Environment {
    /// Returns the resolved environment, reading `ENVIRONMENT` exactly once
    /// per process (cached via `OnceLock`, so the unset-warn fires exactly
    /// once even though several handlers + `main` call this).
    ///
    /// Resolution:
    /// - `"development"` / `"dev"` (case-insensitive) → `Development`
    /// - `"production"` / `"prod"` → `Production`
    /// - unset / empty / unrecognised → loud `tracing::warn!` + `Production`
    ///   (fail-closed: a misconfigured or bare deploy must NOT expose the
    ///   destructive dev endpoints (`/api/dev/reset-database`) or suppress the
    ///   startup security warnings. The dev workflows — `just api-dev-up`,
    ///   `dev-setup.sh`, `docker-compose.dev.yml` — all set
    ///   `ENVIRONMENT=development` explicitly, so local dev is unaffected).
    pub fn current() -> Environment {
        *CURRENT_ENV.get_or_init(Environment::read_from_env)
    }

    fn read_from_env() -> Environment {
        match env::var("ENVIRONMENT") {
            Ok(raw) => {
                let normalised = raw.trim().to_ascii_lowercase();
                match normalised.as_str() {
                    "" => Self::warn_unset(),
                    "production" | "prod" => Environment::Production,
                    "development" | "dev" => Environment::Development,
                    _ => {
                        tracing::warn!(
                            value = %raw,
                            "ENVIRONMENT='{raw}' is not recognised (expected 'development' or \
                             'production'); assuming production (fail-closed). Set \
                             ENVIRONMENT=development for local dev."
                        );
                        Environment::Production
                    }
                }
            }
            Err(_) => Self::warn_unset(),
        }
    }

    fn warn_unset() -> Environment {
        tracing::warn!(
            "ENVIRONMENT is not set; assuming production (fail-closed — dev endpoints disabled, \
             startup security checks active). Set ENVIRONMENT=development for local dev."
        );
        Environment::Production
    }

    pub fn is_development(self) -> bool {
        matches!(self, Environment::Development)
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Environment::Development => "development",
            Environment::Production => "production",
        }
    }
}

/// Legacy convenience predicate kept for callers (`admin::reset_database`).
/// Delegates to the typed [`Environment::current`] single source of truth.
pub fn is_development() -> bool {
    Environment::current().is_development()
}

pub fn is_localhost_webauthn_rp(rp_id: &str, rp_origin: &str) -> bool {
    let rp_is_local = matches!(rp_id, "localhost" | "127.0.0.1");
    let origin_is_local_http = rp_origin.starts_with("http://")
        && (rp_origin.contains("localhost") || rp_origin.contains("127.0.0.1"));
    rp_is_local || origin_is_local_http
}

pub fn warn_if_broken_prod_passkey_rp(
    environment: Environment,
    rp_id: &str,
    rp_origin: &str,
) -> bool {
    if environment.is_development() || !is_localhost_webauthn_rp(rp_id, rp_origin) {
        return false;
    }
    let rule = "=".repeat(72);
    let msg = format!(
        "\n{rule}\n\
         [!!] PRODUCTION PASSKEY MISCONFIGURATION — PASSKEYS WILL BE BROKEN [!!]\n\
         {rule}\n\
         WEBAUTHN_RP_ID resolves to a localhost address in a non-development\n\
         environment. Passkeys will be registered/authenticated against\n\
         localhost and silently fail for the public hostname.\n\
         \n\
         Fix: set WEBAUTHN_RP_ID to the public host (e.g. icp-mp.kalaj.org)\n\
         and WEBAUTHN_RP_ORIGIN to its https origin\n\
         (e.g. https://icp-mp.kalaj.org).\n\
         \n\
         ENVIRONMENT       = {env}\n\
         WEBAUTHN_RP_ID    = {rp_id}\n\
         WEBAUTHN_RP_ORIGIN = {rp_origin}\n\
         {rule}",
        env = environment.as_str(),
    );
    eprintln!("{msg}");
    tracing::error!("{msg}");
    true
}

pub fn is_insecure_admin_token(admin_token: &str) -> bool {
    admin_token.is_empty() || admin_token == "change-me-in-production"
}

pub fn warn_if_insecure_prod_admin_token(
    environment: Environment,
    admin_token: &str,
) -> bool {
    if environment.is_development() || !is_insecure_admin_token(admin_token) {
        return false;
    }
    let rule = "=".repeat(72);
    let msg = format!(
        "\n{rule}\n\
         [!!] PRODUCTION ADMIN TOKEN MISCONFIGURATION — ADMIN ROUTES ARE EXPOSED [!!]\n\
         {rule}\n\
         ADMIN_TOKEN is unset or still the public default value\n\
         (\"change-me-in-production\") in a non-development environment. The\n\
         admin routes (/api/v1/admin/*) are guarded by a publicly-known token\n\
         and are effectively unprotected.\n\
         \n\
         Fix: set ADMIN_TOKEN to a strong, secret, operator-chosen value\n\
         before deploying.\n\
         \n\
         ENVIRONMENT = {env}\n\
         ADMIN_TOKEN = {admin_token}\n\
         {rule}",
        env = environment.as_str(),
    );
    eprintln!("{msg}");
    tracing::error!("{msg}");
    true
}

/// Logs a clear `tracing::warn!` when any ICPay env var is missing. Does NOT
/// crash — the marketplace must still boot and browse when ICPay is
/// unconfigured. The individual payment endpoints (webhook / config) surface
/// the misconfig loudly (500 / 503) at call time.
pub fn warn_if_icpay_unconfigured() {
    let publishable = env::var("ICPAY_PUBLISHABLE_KEY")
        .ok()
        .filter(|v| !v.is_empty());
    let secret = env::var("ICPAY_SECRET_KEY").ok().filter(|v| !v.is_empty());
    let webhook = env::var("ICPAY_WEBHOOK_SECRET")
        .ok()
        .filter(|v| !v.is_empty());

    if publishable.is_some() && secret.is_some() && webhook.is_some() {
        return;
    }

    let missing: Vec<&str> = [
        ("ICPAY_PUBLISHABLE_KEY", publishable.is_some()),
        ("ICPAY_SECRET_KEY", secret.is_some()),
        ("ICPAY_WEBHOOK_SECRET", webhook.is_some()),
    ]
    .into_iter()
    .filter(|(_, set)| !set)
    .map(|(name, _)| name)
    .collect();

    tracing::warn!(
        "ICPay env vars not set — payments disabled (missing: {}). \
         Marketplace browsing still works; payment endpoints will 5xx/503 \
         when invoked. Set real values before the live PoC.",
        missing.join(", ")
    );
}

/// Verifies that the authenticated user owns the script
pub async fn verify_script_ownership(
    state: &Arc<AppState>,
    script_id: &str,
    public_key: &Option<String>,
) -> Result<(), Response> {
    // Get script to check ownership
    let script = match state.script_service.get_script(script_id).await {
        Ok(Some(script)) => script,
        Ok(None) => {
            tracing::warn!("Script ownership check failed: {} not found", script_id);
            return Err(error_response(StatusCode::NOT_FOUND, "Script not found"));
        }
        Err(e) => {
            tracing::error!("Failed to get script for ownership check: {}", e);
            return Err(error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to verify ownership",
            ));
        }
    };

    // Get authenticated user's account ID from public key
    let user_account_id = if let Some(ref pk) = public_key {
        match state
            .script_service
            .account_repo
            .find_public_key_by_value(pk)
            .await
        {
            Ok(Some(account_key)) => Some(account_key.account_id),
            Ok(None) => None,
            Err(e) => {
                tracing::error!("Failed to lookup account for ownership check: {}", e);
                return Err(error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Failed to verify ownership",
                ));
            }
        }
    } else {
        None
    };

    // Verify ownership
    if script.owner_account_id != user_account_id {
        tracing::warn!(
            "Ownership check failed: script owned by {:?}, user is {:?}",
            script.owner_account_id,
            user_account_id
        );
        return Err(error_response(
            StatusCode::FORBIDDEN,
            "Only the script owner can perform this operation",
        ));
    }

    Ok(())
}

#[cfg(test)]
mod webauthn_rp_tests {
    use super::*;

    #[test]
    fn localhost_rp_id_is_detected() {
        assert!(is_localhost_webauthn_rp(
            "localhost",
            "https://icp-mp.kalaj.org"
        ));
        assert!(is_localhost_webauthn_rp(
            "127.0.0.1",
            "https://icp-mp.kalaj.org"
        ));
    }

    #[test]
    fn http_localhost_origin_is_detected() {
        assert!(is_localhost_webauthn_rp(
            "icp-mp.kalaj.org",
            "http://localhost:58000"
        ));
        assert!(is_localhost_webauthn_rp(
            "icp-mp.kalaj.org",
            "http://127.0.0.1:58000"
        ));
    }

    #[test]
    fn public_host_is_not_detected() {
        assert!(!is_localhost_webauthn_rp(
            "icp-mp.kalaj.org",
            "https://icp-mp.kalaj.org"
        ));
    }

    #[test]
    fn warning_fires_for_production_localhost_only() {
        use crate::startup_checks::Environment;
        assert!(warn_if_broken_prod_passkey_rp(
            Environment::Production,
            "localhost",
            "http://localhost:58000"
        ));
        assert!(!warn_if_broken_prod_passkey_rp(
            Environment::Development,
            "localhost",
            "http://localhost:58000"
        ));
        assert!(!warn_if_broken_prod_passkey_rp(
            Environment::Production,
            "icp-mp.kalaj.org",
            "https://icp-mp.kalaj.org"
        ));
    }
}
