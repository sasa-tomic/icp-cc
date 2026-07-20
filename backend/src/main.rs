use icp_marketplace_api::{
    cleanup, cors, db, handlers, middleware,
    models::*,
    repositories::PurchaseRepository,
    services::{
        resolve_provider_from_env, AccountService, PasskeyService, ReviewService, ScriptService,
    },
    startup_checks::{
        warn_if_broken_prod_passkey_rp, warn_if_insecure_prod_admin_token, Environment,
    },
};
use poem::{delete, get, listener::TcpListener, post, EndpointExt, Route, Server};
use sqlx::sqlite::SqlitePool;
use std::{env, io::ErrorKind, net::TcpListener as StdTcpListener, sync::Arc, time::Duration};
use tokio_util::sync::CancellationToken;

/// Wait for a process shutdown signal (ctrl-c and, on Unix, SIGTERM) and then
/// cancel `shutdown`. Falls back to ctrl-c only if the SIGTERM handler cannot
/// be installed. Never returns before a signal arrives.
async fn shutdown_on_signal(shutdown: CancellationToken) {
    let ctrl_c = async {
        if tokio::signal::ctrl_c().await.is_err() {
            tracing::warn!("Failed to install ctrl-c handler");
        }
    };

    #[cfg(unix)]
    {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut sig) => {
                tokio::select! {
                    _ = ctrl_c => {}
                    _ = sig.recv() => {}
                }
            }
            Err(e) => {
                tracing::warn!(
                    "Failed to install SIGTERM handler ({}); falling back to ctrl-c only",
                    e
                );
                ctrl_c.await;
            }
        }
    }

    #[cfg(not(unix))]
    {
        ctrl_c.await;
    }

    tracing::info!("Shutdown signal received; initiating graceful shutdown");
    shutdown.cancel();
}

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    // Initialize tracing with clean, parseable format
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .with_target(false) // Don't show target module
        .with_thread_ids(false) // Don't show thread IDs
        .with_line_number(false) // Don't show line numbers
        .compact() // Use compact format for cleaner output
        .init();

    // Load environment variables
    dotenv::dotenv().ok();

    // Database setup
    let database_url = env::var("DATABASE_URL")
        .unwrap_or_else(|_| "sqlite:./data/marketplace-dev.db?mode=rwc".to_string());

    // Ensure data directory exists
    if let Some(db_path) = database_url.strip_prefix("sqlite:") {
        let path = db_path.split('?').next().unwrap_or(db_path);
        if let Some(parent) = std::path::Path::new(path).parent() {
            std::fs::create_dir_all(parent).expect("Failed to create database directory");
        }
    }

    tracing::info!("Connecting to database: {}", database_url);

    let pool = SqlitePool::connect(&database_url)
        .await
        .expect("Failed to connect to database");

    tracing::info!("Initializing database schema...");
    db::initialize_database(&pool).await;
    tracing::info!("Database schema initialized successfully");

    // Clone pool for background cleanup job before moving it to state
    let cleanup_pool = pool.clone();

    // WebAuthn configuration
    let rp_id = env::var("WEBAUTHN_RP_ID").unwrap_or_else(|_| "localhost".to_string());
    let rp_origin =
        env::var("WEBAUTHN_RP_ORIGIN").unwrap_or_else(|_| "http://localhost:58000".to_string());

    // W7-014: resolve ENVIRONMENT exactly once via the typed single source of
    // truth (`Environment::current` caches + emits the unset-warn once). Both
    // startup security checks consume the same resolved value, so they can
    // never disagree about whether dev-warnings should be suppressed.
    let environment = Environment::current();
    warn_if_broken_prod_passkey_rp(environment, &rp_id, &rp_origin);

    let admin_token =
        env::var("ADMIN_TOKEN").unwrap_or_else(|_| "change-me-in-production".to_string());
    warn_if_insecure_prod_admin_token(environment, &admin_token);

    // Phase K — provider-agnostic payment integration. The provider is
    // selected once at boot from `PAYMENT_PROVIDER` (default "stub";
    // accepted: stub | icpay | none). Unrecognised values fail closed to
    // `none` with a loud `tracing::error!`. The marketplace still boots and
    // browses regardless — only purchase endpoints 5xx/503 when invoked
    // against a `none` provider (or an unconfigured icpay one).
    let resolved_provider = resolve_provider_from_env(pool.clone());
    let provider_name = resolved_provider.name();
    tracing::info!(provider = provider_name, "Payment provider resolved");
    // Conditional ICPay handle for the webhook + legacy config routes (only
    // present when provider=icpay).
    let icpay_provider = resolved_provider.icpay();
    let payment_provider: std::sync::Arc<dyn icp_marketplace_api::services::PaymentProvider> =
        resolved_provider.provider();

    // R-3b WU-1: log the IC gateway host the CORS byte-relay proxy forwards
    // to. Defaults to mainnet (the shared `icp_core::DEFAULT_IC_GATEWAY` const,
    // single source across core + backend); unset just means "use the default"
    // — the marketplace still boots and browses either way. Surfaced at boot so
    // a misconfigured/overridden host is visible in logs.
    let ic_gateway_host =
        env::var("IC_GATEWAY_HOST").unwrap_or_else(|_| icp_core::DEFAULT_IC_GATEWAY.to_string());
    tracing::info!(
        "IC CORS proxy forwarding to IC_GATEWAY_HOST={} (route /api/v1/ic/*)",
        ic_gateway_host
    );

    let passkey_service = PasskeyService::new(pool.clone(), &rp_id, &rp_origin)
        .expect("Failed to create PasskeyService");

    let purchase_repo = PurchaseRepository::new(pool.clone());

    // W7-14: throttle the open `POST /recovery/verify` brute-force oracle —
    // 5 failed codes per (account_id, IP) in 15 minutes → 429. The codes are
    // Argon2id-hashed (each guess is expensive); this adds the per-caller cap.
    let recovery_rate_limiter = std::sync::Arc::new(
        icp_marketplace_api::rate_limit::SlidingWindowRateLimiter::new(5, 15 * 60),
    );

    let state = Arc::new(AppState {
        account_service: AccountService::new(pool.clone()),
        script_service: ScriptService::new(pool.clone()),
        review_service: ReviewService::new(pool.clone()),
        passkey_service,
        purchase_repo,
        payment_provider,
        icpay_provider,
        recovery_rate_limiter,
        pool,
    });

    // ========================================================================
    // Route map — every public API route wired below, grouped by resource.
    // Keep this in sync with the `.at(...)` chain. (Admin routes wear AdminAuth.)
    // ------------------------------------------------------------------------
    // Health & misc
    //   GET    /api/v1/health                         -> health_check
    //   GET    /api/v1/ping                           -> ping
    //   GET    /api/v1/marketplace-stats              -> get_marketplace_stats
    //   POST   /api/dev/reset-database                -> reset_database (dev only)
    // Scripts
    //   GET    /api/v1/scripts                        -> get_scripts
    //   POST   /api/v1/scripts                        -> create_script
    //   GET    /api/v1/scripts/count                  -> get_scripts_count
    //   POST   /api/v1/scripts/search                 -> search_scripts
    //   GET    /api/v1/scripts/trending               -> get_trending_scripts
    //   GET    /api/v1/scripts/featured               -> get_featured_scripts
    //   GET    /api/v1/scripts/compatible             -> get_compatible_scripts
    //   GET    /api/v1/scripts/category/:category     -> get_scripts_by_category
    //   GET    /api/v1/scripts/categories             -> get_script_categories (BEFORE /:id)
    //   GET    /api/v1/scripts/:id                    -> get_script
    //   PUT    /api/v1/scripts/:id                    -> update_script
    //   DELETE /api/v1/scripts/:id                    -> delete_script
    //   POST   /api/v1/scripts/:id/publish            -> publish_script
    //   GET    /api/v1/scripts/:id/preview            -> get_script_preview
    //   GET    /api/v1/scripts/:id/reviews            -> get_reviews
    //   POST   /api/v1/scripts/:id/reviews            -> create_review
    //   POST   /api/v1/scripts/:id/download           -> download_script (signed; entitlement gate)
    //   POST   /api/v1/scripts/:id/entitlement        -> entitlement_check (signed; CTA metadata only)
    // Accounts
    //   POST   /api/v1/accounts                       -> register_account
    //   GET    /api/v1/accounts/:username             -> get_account
    //   PATCH  /api/v1/accounts/:username             -> update_account
    //   GET    /api/v1/accounts/by-public-key/:pubkey -> get_account_by_public_key
    //   POST   /api/v1/accounts/:username/keys        -> add_account_key
    //   DELETE /api/v1/accounts/:username/keys/:key_id-> remove_account_key
    // Passkeys
    // Passkeys (register/delete signature-gated; W7-13)
    //   POST   /api/v1/passkey/register/start         -> passkey_register_start (signed)
    //   POST   /api/v1/passkey/register/finish        -> passkey_register_finish
    //   POST   /api/v1/passkey/authenticate/start     -> passkey_authenticate_start
    //   POST   /api/v1/passkey/authenticate/finish    -> passkey_authenticate_finish
    //   GET    /api/v1/passkey/list/:account_id       -> passkey_list
    //   DELETE /api/v1/passkey/:passkey_id            -> passkey_delete (signed)
    // Vault (signature-gated; W7-12)
    //   POST   /api/v1/vault          -> vault_create
    //   POST   /api/v1/vault/get      -> vault_get
    //   PUT    /api/v1/vault          -> vault_update
    // Recovery codes (generate signature-gated; verify open + rate-limited; W7-14)
    //   POST   /api/v1/recovery/generate              -> recovery_generate (signed)
    //   POST   /api/v1/recovery/verify                -> recovery_verify (rate-limited)
    //   GET    /api/v1/recovery/status/:account_id    -> recovery_status
    // Admin (AdminAuth middleware)
    //   POST   /api/v1/admin/accounts/:username/keys/:key_id/disable -> admin_disable_key
    //   POST   /api/v1/admin/accounts/:username/recovery-key         -> admin_add_recovery_key
    // Payments (provider-agnostic, Phase K)
    //   GET  /api/v1/payments/config            -> payment_config
    //                                                (stub/none: 503; icpay: pk+shortcode)
    //   POST /api/v1/scripts/:id/purchase       -> purchase_script (signed; provider dispatch)
    //                                                stub → 200 {purchased:true} (auto-grants)
    //                                                icpay → 200 {purchased:false, intent}
    //                                                none  → 503 {"error":"payments_disabled"}
    //   ICPay-only routes — mounted ONLY when PAYMENT_PROVIDER=icpay:
    //     GET  /api/v1/payments/icpay/config     -> payment_config_legacy (alias of /payments/config)
    //     POST /api/v1/payments/icpay/webhook    -> icpay_webhook (unauthenticated; HMAC-verified)
    // IC byte-relay CORS proxy (R-3b WU-1)
    //   GET|POST /api/v1/ic/*<rest>                 -> ic_proxy (forwards to ${IC_GATEWAY_HOST})
    // ========================================================================
    // Build app
    let mut app = Route::new()
        .at("/api/v1/health", get(handlers::health_check))
        .at("/api/v1/ping", get(handlers::ping))
        .at(
            "/api/v1/scripts",
            get(handlers::get_scripts).post(handlers::create_script),
        )
        .at("/api/v1/scripts/count", get(handlers::get_scripts_count))
        .at("/api/v1/scripts/search", post(handlers::search_scripts))
        .at(
            "/api/v1/scripts/trending",
            get(handlers::get_trending_scripts),
        )
        .at(
            "/api/v1/scripts/featured",
            get(handlers::get_featured_scripts),
        )
        .at(
            "/api/v1/scripts/compatible",
            get(handlers::get_compatible_scripts),
        )
        .at(
            "/api/v1/scripts/category/:category",
            get(handlers::get_scripts_by_category),
        )
        .at(
            "/api/v1/scripts/categories",
            get(handlers::get_script_categories),
        )
        .at(
            "/api/v1/scripts/:id",
            get(handlers::get_script)
                .put(handlers::update_script)
                .delete(handlers::delete_script),
        )
        .at(
            "/api/v1/scripts/:id/publish",
            post(handlers::publish_script),
        )
        .at(
            "/api/v1/scripts/:id/preview",
            get(handlers::get_script_preview),
        )
        .at(
            "/api/v1/scripts/:id/reviews",
            get(handlers::get_reviews).post(handlers::create_review),
        )
        .at(
            "/api/v1/scripts/:id/download",
            post(handlers::download_script),
        )
        .at(
            "/api/v1/scripts/:id/entitlement",
            post(handlers::entitlement_check),
        )
        // Phase K: provider-agnostic purchase endpoint. Dispatches via
        // state.payment_provider (stub auto-grants; icpay returns Pending
        // + checkout; none → 503 {"error":"payments_disabled"}).
        .at(
            "/api/v1/scripts/:id/purchase",
            post(handlers::purchase_script),
        )
        // Account Profiles endpoints
        .at("/api/v1/accounts", post(handlers::register_account))
        .at(
            "/api/v1/accounts/:username",
            get(handlers::get_account).patch(handlers::update_account),
        )
        .at(
            "/api/v1/accounts/by-public-key/:public_key",
            get(handlers::get_account_by_public_key),
        )
        .at(
            "/api/v1/accounts/:username/keys",
            post(handlers::add_account_key),
        )
        .at(
            "/api/v1/accounts/:username/keys/:key_id",
            delete(handlers::remove_account_key),
        )
        // Passkey Authentication endpoints
        .at(
            "/api/v1/passkey/register/start",
            post(handlers::passkey_register_start),
        )
        .at(
            "/api/v1/passkey/register/finish",
            post(handlers::passkey_register_finish),
        )
        .at(
            "/api/v1/passkey/authenticate/start",
            post(handlers::passkey_authenticate_start),
        )
        .at(
            "/api/v1/passkey/authenticate/finish",
            post(handlers::passkey_authenticate_finish),
        )
        .at(
            "/api/v1/passkey/list/:account_id",
            get(handlers::passkey_list),
        )
        .at(
            "/api/v1/passkey/:passkey_id",
            delete(handlers::passkey_delete),
        )
        // Vault endpoints (signature-gated; W7-12)
        .at(
            "/api/v1/vault",
            post(handlers::vault_create).put(handlers::vault_update),
        )
        .at("/api/v1/vault/get", post(handlers::vault_get))
        // Recovery code endpoints
        .at(
            "/api/v1/recovery/generate",
            post(handlers::recovery_generate),
        )
        .at("/api/v1/recovery/verify", post(handlers::recovery_verify))
        .at(
            "/api/v1/recovery/status/:account_id",
            get(handlers::recovery_status),
        )
        // Admin Account endpoints (require admin authentication)
        .at(
            "/api/v1/admin/accounts/:username/keys/:key_id/disable",
            post(handlers::admin_disable_key).with(middleware::AdminAuth),
        )
        .at(
            "/api/v1/admin/accounts/:username/recovery-key",
            post(handlers::admin_add_recovery_key).with(middleware::AdminAuth),
        )
        // Provider-agnostic payment endpoints.
        .at("/api/v1/payments/config", get(handlers::payment_config))
        .at(
            "/api/v1/marketplace-stats",
            get(handlers::get_marketplace_stats),
        )
        .at("/api/dev/reset-database", post(handlers::reset_database))
        // R-3b WU-1: IC byte-relay CORS proxy. A protocol-blind catch-all that
        // forwards /api/v1/ic/*<rest> to ${IC_GATEWAY_HOST} (default ic0.app)
        // so the browser-side agent-js can reach IC boundary nodes (browsers
        // cannot call ic0.app directly — no CORS headers). Supports GET (status
        // / candid registry) + POST (query/call/read_state). The global
        // CORS middleware below adds CORS headers; the proxy never sees a key.
        .at(
            "/api/v1/ic/*rest",
            get(handlers::ic_proxy::ic_proxy).post(handlers::ic_proxy::ic_proxy),
        );

    // ICPay-specific routes — mount ONLY when PAYMENT_PROVIDER=icpay. The
    // legacy config route is an alias of the generic /payments/config (same
    // response shape); the webhook is ICPay-specific (HMAC verification
    // over the raw body, idempotent entitlement insert). Both 503 LOUDLY
    // when invoked while the typed icpay handle is somehow absent (route
    // should be unmounted in that case — defence in depth).
    if provider_name == "icpay" {
        app = app
            .at(
                "/api/v1/payments/icpay/config",
                get(handlers::payment_config_legacy),
            )
            .at(
                "/api/v1/payments/icpay/webhook",
                post(handlers::icpay_webhook),
            );
    }

    let app = app.with(cors::build_cors()).data(state);

    // Start server
    let port = env::var("PORT").unwrap_or_else(|_| "58000".to_string());
    let addr = format!("[::]:{}", port);

    tracing::info!("Starting server on http://{}", addr);

    // Bind once to get the actual address (important for port 0 -> random port)
    let (std_listener, bind_addr) = match StdTcpListener::bind(&addr) {
        Ok(listener) => (listener, addr.clone()),
        Err(error) if error.kind() == ErrorKind::PermissionDenied => {
            let ipv4_addr = format!("127.0.0.1:{}", port);

            tracing::warn!(
                "IPv6 bind to {} denied ({}), falling back to {}",
                addr,
                error,
                ipv4_addr
            );

            (
                StdTcpListener::bind(&ipv4_addr).expect("Failed to bind to IPv4 fallback address"),
                ipv4_addr,
            )
        }
        Err(error) => {
            panic!("Failed to bind to address {}: {}", addr, error);
        }
    };

    let free_port = std_listener
        .local_addr()
        .expect("Failed to get local address")
        .port();

    // Construct the final bind address using the actual port
    let final_bind_addr = if bind_addr.starts_with("[::]") {
        format!("[::]:{}", free_port)
    } else {
        format!("0.0.0.0:{}", free_port)
    };

    // Log the actual listening address for external tools to parse
    tracing::info!("listening on addr=socket://{}", final_bind_addr);

    // Graceful shutdown: one token drives both the background cleanup job and
    // the HTTP server, triggered by ctrl-c or SIGTERM.
    let shutdown = CancellationToken::new();
    tokio::spawn(shutdown_on_signal(shutdown.clone()));

    // Start background cleanup job for signature audit
    cleanup::start_audit_cleanup_job(cleanup_pool, shutdown.clone());

    // Close the std listener since we just needed it for the address
    drop(std_listener);

    // Now bind with Poem's listener
    let listener = TcpListener::bind(final_bind_addr);

    // Run until a shutdown signal arrives; when it does, drain in-flight
    // connections (hard limit 30s) then return. With no signal this runs
    // forever, identical to the previous behavior.
    Server::new(listener)
        .run_with_graceful_shutdown(app, shutdown.cancelled(), Some(Duration::from_secs(30)))
        .await
}
