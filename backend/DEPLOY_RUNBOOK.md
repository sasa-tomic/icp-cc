# Deploy Runbook — ICP Marketplace API

Operational playbook for the production Docker + Cloudflare Tunnel deployment.
Conceptual background lives in [PROD_DEPLOYMENT.md](./PROD_DEPLOYMENT.md);
this file is the **what-to-type** reference.

All commands assume you are on the deploy host, in the repo root (`/code/icp-cc`
or your equivalent), unless a `cd backend` is shown.

## 0. Preconditions checklist

- [ ] Docker daemon running: `docker info` succeeds.
- [ ] Rust toolchain present: `cargo --version`.
- [ ] `backend/data/` exists and is writable by container UID 1000:
      `mkdir -p backend/data && chmod 777 backend/data`.
- [ ] `backend/.env` exists (copied from `.env.tunnel.example`) and contains:
      - `TUNNEL_TOKEN=…` (Cloudflare tunnel token)
      - `ADMIN_TOKEN=<strong random secret>`  ← **must override the default**
      - `WEBAUTHN_RP_ID=icp-mp.kalaj.org`
      - `WEBAUTHN_RP_ORIGIN=https://icp-mp.kalaj.org`
      (the WEBAUTHN_* and ADMIN_TOKEN are compose-interpolated; see the env
      table in PROD_DEPLOYMENT.md.)

## 1. Deploy (full procedure)

```bash
# 1.1 Build the release binary on the host (the image copies it in, does NOT compile).
cargo build --release
#    → produces target/release/icp-marketplace-api

# 1.2 Prepare data dir.
mkdir -p backend/data && chmod 777 backend/data

# 1.3 Build the Docker image.
docker build -f backend/Dockerfile -t icp-marketplace-api:prod .

# 1.4 Validate the resolved compose config (catches env/interpolation mistakes
#     BEFORE touching a running stack). Substitute your real TUNNEL_TOKEN.
cd backend
set -a; . ./.env; set +a
docker compose -f docker-compose.prod.yml config | grep -E 'WEBAUTHN_RP_|ADMIN_TOKEN|PORT|TUNNEL_TOKEN'

# 1.5 Start the stack (image already built, so this just creates containers).
docker compose -f docker-compose.prod.yml up -d
```

Or the one-shot recipe (does 1.1 + 1.2 + 1.5 via the helper script):
```bash
just docker-deploy-prod
```

## 2. Verify health

```bash
cd backend

# 2.1 Container status — api-prod should be "Up … (healthy)".
docker compose -f docker-compose.prod.yml ps

# 2.2 API health via the direct/debug host port (58100 → container 58000).
curl -s http://127.0.0.1:58100/api/v1/health | jq .
#   expect: { "success": true, "environment": "production", "message": "ICP Marketplace API is running", ... }

# 2.3 API health via the public tunnel (end-to-end, what users hit).
curl -s https://icp-mp.kalaj.org/api/v1/health | jq .

# 2.4 Confirm no misconfig banners in the boot log.
docker compose -f docker-compose.prod.yml logs api-prod | grep -iE 'MISCONFIG|change-me-in-production|warn'
#   A PRODUCTION PASSKEY MISCONFIGURATION banner = STOP and fix WEBAUTHN_RP_*.
#   "ADMIN_TOKEN … using default" warn       = STOP and set a strong ADMIN_TOKEN.
```

A passing smoke (no banners, all three curls return `success:true`) means the
deploy is good.

## 3. Check / rotate the WebAuthn RP config

The WebAuthn RP (passkey) config is read from env **once at boot**, so changing
it requires a restart.

**Check current value (without restart):**
```bash
cd backend
docker compose -f docker-compose.prod.yml exec api-prod printenv \
    WEBAUTHN_RP_ID WEBAUTHN_RP_ORIGIN
#   must be: WEBAUTHN_RP_ID=icp-mp.kalaj.org
#            WEBAUTHN_RP_ORIGIN=https://icp-mp.kalaj.org
```

**Rotate / change the hostname** (e.g. moving to a new domain):
```bash
cd backend
# 1. Edit .env: set the new WEBAUTHN_RP_ID / WEBAUTHN_RP_ORIGIN.
# 2. Recreate the api-prod container so it picks up the new env:
docker compose -f docker-compose.prod.yml up -d --force-recreate api-prod
# 3. Re-verify per §2 (especially that NO misconfig banner appears).
```

> ⚠️ Changing the RP ID invalidates all previously registered passkeys (they
> are scoped to the RP ID). This is expected WebAuthn behavior, not a bug.

## 4. Rollback

There is no separate "previous" image tag by default — `image:
icp-marketplace-api:prod` is overwritten on each `docker build`. Two strategies:

**A. Roll back to the previous code (quick).** Check out the prior git commit
and rebuild:
```bash
cd /code/icp-cc
git log --oneline -10                 # find the last known-good commit
git checkout <good-commit>
cargo build --release
docker build -f backend/Dockerfile -t icp-marketplace-api:prod .
cd backend && docker compose -f docker-compose.prod.yml up -d --force-recreate api-prod
```

**B. Stop the current release (full takedown).** Use this if the deploy is
actively broken and you need to remove it:
```bash
cd backend
docker compose -f docker-compose.prod.yml down      # stops + removes containers
# add -v to also delete the named network; the ./data bind mount (DB) is NOT removed by `down`.
```

To make rollbacks trivial in future, tag images by git SHA before deploying:
```bash
docker build -f backend/Dockerfile -t icp-marketplace-api:$(git rev-parse --short HEAD) .
```

## 5. Backup & restore (SQLite)

```bash
cd backend
# Backup (safe to run while the API is up — SQLite WAL handles concurrent readers):
cp data/marketplace-prod.db data/marketplace-prod.db.$(date +%Y%m%d-%H%M%S).bak

# Restore (stop the API first to avoid write contention):
docker compose -f docker-compose.prod.yml stop api-prod
cp data/marketplace-prod.db.<timestamp>.bak data/marketplace-prod.db
docker compose -f docker-compose.prod.yml start api-prod
```

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Up X seconds (restarting)` / exit code 101, log says `unable to open database file` (SQLite code 14) | Container UID 1000 can't write to the bind-mounted `./data`. | `mkdir -p backend/data && chmod 777 backend/data`; or chown `data/` to the host UID that maps to container UID 1000. |
| Boot log shows `[!!] PRODUCTION PASSKEY MISCONFIGURATION` banner | `WEBAUTHN_RP_ID`/`WEBAUTHN_RP_ORIGIN` resolve to localhost in prod. | Set both in `.env` to the public host (`icp-mp.kalaj.org` / `https://icp-mp.kalaj.org`) and recreate: `docker compose up -d --force-recreate api-prod`. |
| Boot log shows `ADMIN_TOKEN … using default` | `ADMIN_TOKEN` unset or left as `change-me-in-production`. Admin routes are guarded by a publicly-known token. | Generate a strong secret, set `ADMIN_TOKEN=` in `.env`, recreate `api-prod`. |
| `cloudflared` logs `Unauthorized` / tunnel won't connect | `TUNNEL_TOKEN` wrong/expired, or tunnel deleted in CF dashboard. | Re-fetch token from Zero Trust → Networks → Tunnels; update `.env`; `docker compose up -d --force-recreate cloudflared-prod`. |
| `curl https://icp-mp.kalaj.org/...` fails but `curl 127.0.0.1:58100/...` works | Tunnel down or DNS not propagated; the API itself is fine. | Check cloudflared container health + CF dashboard tunnel status; wait for DNS. |
| `curl 127.0.0.1:58100/...` fails but container is `(healthy)` | (Sandbox only) Docker daemon in a nested netns where published ports aren't reachable from the host shell. | Not a prod symptom. Verify via the tunnel URL or `docker exec … curl localhost:58000/api/v1/health`. |
| Health returns `"environment":"development"` | `ENVIRONMENT` not set to production (compose should set it). | Confirm `docker-compose.prod.yml` `ENVIRONMENT: production` and that no `.env` override is shadowing it. |
| `/api/dev/reset-database` returns 403 in prod | Expected — dev-only endpoint is correctly disabled. | Not an error; this is `ENVIRONMENT=production` working as intended. |
| Permission denied binding `[::]:58000` | Another process holds port 58000, or container lacks IPv6. | The app auto-falls-back to `127.0.0.1` on `PermissionDenied`; ensure nothing else listens on 58000. |

## 7. Known operational gaps (follow-ups)

These do **not** block deploy but should be addressed:

1. **ADMIN_TOKEN fallback is too quiet.** `admin_auth.rs` falls back to
   `change-me-in-production` with only a `warn!` when the var is unset — unlike
   the passkey RP check (PR-2), there is no loud boot banner and no prod-only
   hardening. Recommended: add a `warn_if_broken_prod_admin_token` paralleling
   the passkey one (or refuse to start admin routes in prod without it). Until
   then, operators MUST set a strong `ADMIN_TOKEN` in `.env` and watch the log.
2. **No versioned image tagging.** `image: icp-marketplace-api:prod` is
   overwritten each build, so rollback means rebuilding from a prior commit
   (§4A). Tag by git SHA for instant rollback.
3. **Dockerfile pins `--platform=linux/amd64`.** Fine for the current single
   amd64 host; revisit if deploying to arm64.
