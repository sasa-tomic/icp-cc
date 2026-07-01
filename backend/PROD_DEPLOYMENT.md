# Production Deployment (Docker + Cloudflare Tunnel)

How the **ICP Marketplace API** is deployed to production. This document covers
the *what* and *why*; for a copy-paste operational checklist (deploy, verify,
rollback, troubleshoot) see **[DEPLOY_RUNBOOK.md](./DEPLOY_RUNBOOK.md)**.

> **Runtime note (post TypeScript/QuickJS migration).** The backend is a
> Rust/poem HTTP API. It **stores and serves TypeScript script bundles** (the
> `bundle` field on scripts) — it does **not** host or execute a second
> scripting runtime. QuickJS execution happens client-side in the Flutter app
> via FFI. There is no Lua anywhere in the stack. Any older doc implying a
> second server-side runtime is obsolete.

## Architecture

```
Internet ──► Cloudflare Network ──► Cloudflare Tunnel (cloudflared container)
                                        │ reaches over the bridge network
                                        ▼
                            icp-mp.kalaj.org ──► api-prod:58000
```

- **api-prod** — the Rust API (image `icp-marketplace-api:prod`), listens on
  container port `58000`.
- **cloudflared-prod** — Cloudflare Tunnel connector. Terminates public TLS on
  `https://icp-mp.kalaj.org` and forwards to `api-prod:58000` over the
  `api-network-prod` bridge. No host firewall ports are opened for public
  traffic.

**Port mapping reconciliation.** `docker-compose.prod.yml` publishes
`58100:58000` (host:container). The host port **58100** exists **only for
direct/debug access** from the server itself (e.g. `curl
http://127.0.0.1:58100/api/v1/health`). Public traffic does **not** use 58100 —
it flows `https://icp-mp.kalaj.org` → tunnel → `api-prod:58000` (container
internal). This is intentional and correct.

**WebAuthn RP origin.** `WEBAUTHN_RP_ORIGIN` must be the **user-facing origin**
`https://icp-mp.kalaj.org` — scheme + host, **no port**. It must NOT include
the internal `:58100`; the WebAuthn RP ID/origin is what the user's browser
sees, not the container's listen port.

## Prerequisites

1. Docker Engine + Docker Compose v2 (`docker compose version` works).
2. `cargo` (Rust toolchain) on the deploy host — the release binary is built
   **on the host first**, then copied into the image (see Dockerfile). The
   image does not build from source.
3. A Cloudflare account with control over the `kalaj.org` zone.
4. (Recommended) `just` — the deploy recipes in the root `justfile` wrap the
   raw commands below.

## Environment variables

`docker-compose.prod.yml` wires production defaults via `${VAR:-default}`
interpolation, so the stack starts with safe prod values even from an empty
environment. Override any of them in `backend/.env` (gitignored). The full
ground-truth set the **code** reads:

| Variable | Prod default | Required in prod? | Purpose |
|----------|--------------|-------------------|---------|
| `ENVIRONMENT` | `production` | yes (compose sets it) | Marks a prod run. Only `development` enables destructive dev endpoints (`/api/dev/reset-database`). |
| `PORT` | `58000` | yes (compose sets it) | Container listen port. |
| `DATABASE_URL` | `sqlite:///data/marketplace-prod.db?mode=rwc` | yes (compose sets it) | SQLite path, persisted via the `./data` bind mount. |
| `RUST_LOG` | `info` | no | `tracing` filter. |
| `WEBAUTHN_RP_ID` | `icp-mp.kalaj.org` | **yes** | WebAuthn RP ID = public hostname. Passkeys are scoped to it. |
| `WEBAUTHN_RP_ORIGIN` | `https://icp-mp.kalaj.org` | **yes** | WebAuthn RP origin (scheme + host, no port). Must be `https://` in prod. |
| `ADMIN_TOKEN` | `change-me-in-production` | **yes — OVERRIDE** | Bearer token for `/api/v1/admin/*`. **Generate a long random secret** and set it in `.env`. See *Known operational gaps* below. |
| `TUNNEL_TOKEN` | _(none)_ | **yes** for the tunnel | Cloudflare tunnel token. Put in `.env` (from `.env.tunnel.example`). |

### The two loud misconfiguration warnings on boot

The API prints banners to **stderr and the log** and refuses to stay quiet when
prod-critical config is wrong:

1. **Passkey RP (PR-2).** If `ENVIRONMENT != development` and
   `WEBAUTHN_RP_ID`/`WEBAUTHN_RP_ORIGIN` resolve to a localhost address, on
   boot you get:
   ```
   ========================================================================
   [!!] PRODUCTION PASSKEY MISCONFIGURATION — PASSKEYS WILL BE BROKEN [!!]
   ========================================================================
   ```
   Passkeys would be registered against localhost and silently fail for the
   public hostname. **Never ignore this** — set both `WEBAUTHN_RP_*` vars to
   the public host.

2. **Admin token.** `admin_auth.rs` currently falls back to the hardcoded
   `change-me-in-production` when `ADMIN_TOKEN` is unset, logging only a single
   `warn!`. This is **not** loud enough and is tracked as an operational gap
   (see DEPLOY_RUNBOOK.md). Until it is tightened, treat the presence of the
   default value as a misconfiguration you must fix before exposing the
   service: set a strong `ADMIN_TOKEN` in `.env`.

## Deploy procedure (summary)

The full numbered procedure — including verification and rollback — lives in
[DEPLOY_RUNBOOK.md](./DEPLOY_RUNBOOK.md). The short version:

```bash
# 0. From the repo root, on the deploy host:
cargo build --release                                # builds target/release/icp-marketplace-api
cd backend
mkdir -p data && chmod 777 data                      # SQLite persistence + container write access

# 1. Provide env (tunnel token + any overrides). .env is gitignored.
cp .env.tunnel.example .env                          # then edit: set TUNNEL_TOKEN, ADMIN_TOKEN, etc.

# 2. Validate the resolved config (optional but recommended):
TUNNEL_TOKEN=… docker compose -f docker-compose.prod.yml config | less

# 3. Build the image and start the stack:
docker compose -f docker-compose.prod.yml up -d --build

# 4. Verify health:
docker compose -f docker-compose.prod.yml ps         # api-prod shows (healthy)
curl -s http://127.0.0.1:58100/api/v1/health         # direct/debug port
curl -s https://icp-mp.kalaj.org/api/v1/health       # via tunnel
```

The `just docker-deploy-prod` recipe automates steps 0+1+3 (it runs
`cargo build --release` then `backend/scripts/start-tunnel.sh`, which checks
for `.env`, prepares `data/`, and runs `compose up -d --build`).

## Cloudflare Tunnel one-time setup

Only needed when creating a new tunnel (not on every deploy):

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) →
   **Networks → Connectors → Cloudflare Tunnels → Create a tunnel**.
2. Choose **Cloudflared**, name it `icp-marketplace`, save.
3. **Public Hostname** tab → add:
   - Subdomain `icp-mp`, Domain `kalaj.org`
   - Service type `HTTP`, URL `api-prod:58000` (the container service+port)
4. Select the **Docker** install option and copy the token (the long string
   after `--token`). Put it in `backend/.env` as `TUNNEL_TOKEN=…`.

`.env` (created from `.env.tunnel.example`) is gitignored — never commit it.

## Data persistence

- The SQLite DB lives at `backend/data/marketplace-prod.db` on the host,
  bind-mounted to `/data` in the container.
- Created automatically on first boot. Back it up by copying the `data/`
  directory (see DEPLOY_RUNBOOK.md → Backup).
- The container runs as non-root UID 1000 (`appuser`); ensure `data/` is
  writable by that UID (`chmod 777 data` is the simplest fix).

## Related documentation

- [DEPLOY_RUNBOOK.md](./DEPLOY_RUNBOOK.md) — operational runbook (deploy,
  verify, rollback, troubleshoot, backup).
- [README.md](./README.md) — API endpoints.
- [QUICKSTART.md](./QUICKSTART.md) — local dev quick start.
