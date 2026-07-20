# ICP Marketplace API - Rust + Poem Backend (Phase 1)

A minimal, robust REST API backend built with Rust and Poem framework, replacing the CloudFlare Worker implementation.

## ✨ Features

- **Lightweight & Fast**: Minimal dependencies, clean architecture
- **SQLite**: Simple local development with file-based database
- **Auto-migrations**: Database schema created automatically on startup
- **JSON API**: RESTful endpoints with proper error handling
- **CORS enabled**: Ready for frontend integration

## 🚀 Quick Start

See [QUICKSTART.md](./QUICKSTART.md) for step-by-step setup (2-5 minutes).

**Local Development:**
```bash
cp .env.example .env && cargo run
# API at http://127.0.0.1:58000
```

**Docker Deployment:**
```bash
# Development (local)
just docker-deploy-dev  # http://localhost:58000

# Production (with Cloudflare Tunnel)
cp .env.tunnel.example .env  # Add TUNNEL_TOKEN
just docker-deploy-prod      # https://icp-mp.kalaj.org (+ http://localhost:58000)
```

## 📋 API Endpoints

### Health & Status
- `GET /api/v1/health` - Server health check
- `GET /api/v1/ping` - Simple ping test

### Scripts
- `GET /api/v1/scripts` - List all public scripts
  - Query params: `limit`, `offset`, `category`
- `GET /api/v1/scripts/:id` - Get specific script by ID
- `GET /api/v1/scripts/count` - Get total scripts count

### Statistics
- `GET /api/v1/marketplace-stats` - Get marketplace statistics
  - Returns: `totalScripts`, `totalDownloads`, `averageRating`

### Payments (Phase K — provider-agnostic)
- `POST /api/v1/scripts/:id/purchase` - Signed purchase (Ed25519 over
  canonical `{action:"purchase", id, nonce, ts}`). Dispatches to the
  active provider:
  - `PAYMENT_PROVIDER=stub` (default): returns
    `{success:true, data:{intent:{...status:"completed"...}, purchased:true}}`
    and writes the entitlement row immediately. Use for local dev + tests.
  - `PAYMENT_PROVIDER=icpay`: returns
    `{success:true, data:{intent:{...status:"pending"...}, purchased:false}}`
    — the entitlement is recorded when the ICPay webhook lands.
  - `PAYMENT_PROVIDER=none`: returns `503` with body
    `{"error":"payments_disabled","provider":"none"}` (NOT the canonical
    `{success:false,...}` envelope — the spec is explicit).
- `GET /api/v1/payments/config` - Generic public client config (dispatches
  via `PaymentProvider::client_config()`). Stub/None → 503; ICPay (when
  publishable key set) → `{publishableKey, shortcode, apiUrl}`.
- `POST /api/v1/scripts/:id/download` - Signed authenticated download
  (Ed25519 over `download:{id}:{ts}:{nonce}`). Releases the paid bundle
  only when the caller owns the script OR holds a purchase record.
- `POST /api/v1/scripts/:id/entitlement` - Signed entitlement check.
  Returns `{purchased, owns}` (metadata only — never the bundle).
- Legacy ICPay routes (mounted ONLY when `PAYMENT_PROVIDER=icpay`):
  - `GET /api/v1/payments/icpay/config` - Alias of `/payments/config`.
  - `POST /api/v1/payments/icpay/webhook` - HMAC-verified webhook receiver.

### Development
- `POST /api/dev/reset-database` - Reset database (development only)

## 🧪 Testing

```bash
curl http://127.0.0.1:58000/api/v1/health | jq .
curl http://127.0.0.1:58000/api/v1/marketplace-stats | jq .
```

See [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md) for full testing guide.

## 📁 Project Structure

```
backend/
├── src/
│   └── main.rs          # All application code (clean & minimal)
├── data/
│   └── marketplace-dev.db           # SQLite database file (auto-created)
├── Cargo.toml           # Rust dependencies
├── .env                 # Environment configuration
└── README.md            # This file
```

## ⚙️ Configuration

See [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md) for environment variables.

### Payment provider (Phase K)

The `PAYMENT_PROVIDER` env var selects which payment provider the backend
uses for `POST /api/v1/scripts/:id/purchase`. Default: `stub`.

| Value      | Behaviour                                                                                                  |
|------------|------------------------------------------------------------------------------------------------------------|
| `stub`     | Dev / test provider. Auto-grants entitlement immediately (HTTP 200, `purchased:true`). Deterministic; no network. Recommended for local dev + CI. |
| `icpay`    | Production ICPay provider. Returns a Pending intent; the entitlement is recorded when the ICPay webhook lands. Requires `ICPAY_PUBLISHABLE_KEY` (+ `ICPAY_WEBHOOK_SECRET` for the webhook). The legacy `/payments/icpay/*` routes mount only in this mode. |
| `none`     | Fail-closed. Purchase attempts return HTTP 503 `{"error":"payments_disabled","provider":"none"}`. Use during incidents / when payments must be disabled. |
| `<other>`  | Unrecognised values fail closed to `none` with a loud `tracing::error!` at boot.                            |

Switching providers is a config-only change — no code modifications needed.
The `purchases` schema is provider-agnostic; the `icpay_intent_id` column
is reused for ALL providers' intent ids (legacy name; never migrated).

## 🔄 Phase 2 - PostgreSQL Support

To add PostgreSQL support in the future:

1. Add `postgres` feature to sqlx in Cargo.toml
2. Update database connection logic to support both SQLite and Postgres
3. Change `?N` parameter syntax to `$N` for Postgres compatibility
4. Set `DATABASE_URL=postgresql://...` in production

## 📊 Database Schema

### Scripts Table
```sql
CREATE TABLE scripts (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    bundle TEXT NOT NULL,
    author_name TEXT NOT NULL,
    is_public INTEGER DEFAULT 1,
    rating REAL DEFAULT 0.0,
    downloads INTEGER DEFAULT 0,
    review_count INTEGER DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

## 🎯 Benefits Over CloudFlare Worker

- ✅ **No port conflicts** - runs on any free port
- ✅ **Simple local testing** - just `cargo run`
- ✅ **Better debugging** - standard Rust tooling
- ✅ **Faster iteration** - no deployment needed for testing
- ✅ **Type safety** - compile-time guarantees
- ✅ **Clean separation** - easy to test and maintain

## 📝 Example Response

```json
{
  "success": true,
  "data": {
    "scripts": [],
    "total": 0,
    "hasMore": false
  }
}
```

## 🐛 Troubleshooting

See [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md#troubleshooting) for common issues and solutions.

## 📦 Dependencies

- **poem** - Modern, fast web framework
- **tokio** - Async runtime
- **sqlx** - SQL toolkit with compile-time checked queries
- **serde** - Serialization/deserialization
- **chrono** - Date/time handling

## 🚀 Deployment

**DRY Docker Compose Setup:**
- `docker-compose.yml` - Base config (shared)
- `docker-compose.dev.yml` - Dev overrides (local port, dev DB, debug)
- `docker-compose.prod.yml` - Prod overrides (adds CF Tunnel)

**Commands:**
```bash
just docker-{deploy,logs,status,rebuild,down}-{dev,prod}
```

Both environments can run simultaneously. See [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md) for details.

## 🚢 Next Steps

1. Add POST endpoints for creating scripts
2. Implement signature verification for writes
3. Add reviews functionality
4. Implement search with filters

## ⚠️ Known Limitations

- Script IDs are currently random UUIDs. They must be replaced with user-provided globally unique slugs (or deterministic hashes) so marketplace links remain stable and shareable. Track this in `TODO.md`.
5. Add rate limiting

---

Built with ❤️ using Rust 🦀
