# Wave 7 — Security, Functional & Visual Sweep

- **Status:** 🔧 IN PROGRESS (2026-07-14)
- **Date:** 2026-07-14
- **Scope:** Whole app — backend security (the headline), frontend functional/visual, test coverage.
- **Method:** empirically grounded (every claim cited to `file:line` or a live
  `curl`/browser observation), PoC-first / TDD (RED → GREEN), one commit per unit.
  Orchestrated via subagent swarms (4 discovery planners → plan review → serialized
  implementers → verifiers).
- **Predecessors (DONE, not reopened):**
  - `2026-07-10-wave6-issues.md` (W6-1..13) · `2026-07-10-issue-hunt.md` (Wave-5)
  - `2026-07-10-quality-sweep.md` (Wave-4) · `2026-07-08-quality-initiative.md` (1/2/3)

## §0. Baseline (measured 2026-07-14)

| Check | Verdict | Evidence |
|-------|---------|----------|
| `flutter analyze` | ✅ CLEAN | "No issues found!" (6.4s) |
| Backend API | ✅ UP | port `37245`, `GET /api/v1/marketplace-stats` → 200 |
| Flutter Web build | ✅ SERVED | `http://127.0.0.1:8099/` → 200 |
| Native lib | ✅ BUILT | `target/release/libicp_core.so` |

## §1. Discovery (4 parallel subagents, empirically grounded)

Source findings (cited `file:line` + live probes, no invented issues):
- `.tmp/wave7-ux-findings.md` — 1×P1, 2×P2, 7×P3 (live Chromium, no mocks)
- `.tmp/wave7-audit-findings.md` — 2×P1, 4×P2, 7×P3 (static Dart+Rust)
- `.tmp/wave7-backend-findings.md` — 7×P1, 12×P2, 7×P3 (static + live `curl`)
- `.tmp/wave7-test-findings.md` — 2×P2 coverage gaps, 5×P3 low-signal

### Systemic root cause (backend security P1 cluster)
The vault / passkey / recovery / review / detail-entitlement / stats subsystems all
treat a **client-supplied `account_id` (or `user_id`) as the sole authorization**.
`account_id` is a *public* identifier (UUID / principal, returned in the clear by
`GET /accounts/:username` and leaked in `ScriptDetailResponse.owner_account_id`).
Signature auth **already exists** for script ops + account key-mgmt — it was simply
never extended to these surfaces. **Uniform fix: every state-changing / entitlement
route verifies an Ed25519 signature and resolves `account_id` server-side from the
verified public key.**

### Live-proven exploits
- **SQL injection** (`script_repository.rs:31-32`): `?category=zzz' OR 1=1--` → 118
  scripts incl. "Private Script" (defeats `is_public`). One-line parameterized fix.
- **Entitlement bypass** (`handlers/scripts.rs:73-102`):
  `GET /scripts/interactive-counter?account_id=account-gamedev` → full 852B paid bundle.
- **Account takeover** (`handlers/recovery.rs:18-38`):
  `POST /recovery/generate {account_id}` mints+returns plaintext codes for any account.

## §2. Work Units

> Prefix **W7-** = Wave-7. Each: PoC-first / RED-test-first, one commit,
> `flutter analyze` clean + cited tests green + `cargo nextest`/`clippy` green.
> Shared git index → serialized implementers.

### Phase 1 — Isolated security + functional fixes (high confidence, no cross-system coordination)

#### W7-1 — SQL injection: parameterize `category` filter [P1] (backend W7-002)
- `repositories/script_repository.rs:31-32` interpolates `format!(" AND category = '{}'", cat)`.
- Bind as parameter (sibling `get_by_category` already does at `:397-405`).
- RED test: `?category=zzz' OR 1=1--` returns 0 (not 118, no private scripts).

#### W7-2 — Entitlement bypass: strip `bundle` from GET, add signed entitlement check [P1, coordinated backend+frontend] (backend W7-001)
- `handlers/scripts.rs:73-102` + `models.rs:263-270` (`ScriptDetailQuery.account_id`).
- **Reviewer finding:** naively dropping `?account_id=` strands a paid user on "Buy"
  forever — 3 frontend consumers read `purchased` (`scripts_screen.dart:182-184,604-622`,
  `main.dart:117-126`). The actual LEAK is the **`bundle`** (paid source), not the
  `purchased` boolean. `purchased` is metadata-safe to keep behind a signed check.
- **Fix:** (a) `GET /scripts/:id` NEVER returns `bundle` for a paid script (only the
  signed `POST /scripts/:id/download` does, which already gates correctly); (b) add a
  signed `POST /scripts/:id/entitlement` (Ed25519 over `{id, ts, nonce}`) that returns
  `{purchased: bool}` so the frontend can drive the Buy/Download CTA without leaking the
  bundle; (c) wire the frontend to the new endpoint. `account_id` is resolved server-side
  from the verified public key.
- RED test: `GET /scripts/<paid>?account_id=<owner>` → `bundle:null`; signed entitlement
  → `purchased:true` for owner/purchaser, `false` otherwise.

#### W7-3 — Constant-time secret compares [P1/P2] (backend W7-008 / static W7-01)
- Extract `constant_time_eq` (already in `payment_service.rs:234`) into a shared util.
- Use in `middleware/admin_auth.rs:40` (`token == admin_token`) + `vault.rs:113`.

#### W7-4 — CORS hardening [P2] (backend W7-009)
- `main.rs:356` `Cors::new()` reflects any origin + allows TRACE/CONNECT.
- Explicit origin allow-list (dev localhost + prod origin via dart-define/env);
  drop TRACE/CONNECT; keep GET/POST/PUT/DELETE/OPTIONS.

#### W7-5 — Wire replay-prevention on the signed download [P2] (backend W7-010)
- `handlers/payments/mod.rs:26-82` signs `timestamp`+`nonce` but never calls
  `auth::validate_replay_prevention`. Wire it (account ops already do).

#### W7-6 — Webhook status + no config-detail leak [P2] (backend W7-015)
- `handlers/payments/mod.rs:196-202` returns 500 + `"ICPAY_WEBHOOK_SECRET not configured"`
  to the untrusted caller. → 503 + generic message externally; detail in logs only.

#### W7-7 — Frontend service hardening [P1/P2] (static W7-02/03/04/06/07)
- `marketplace_open_api_service.dart`: (a) `!responseData['success']` → `!= true`
  (`:670`); (b) route the 3 success-path bypasses through `_decodeSuccessResponse`;
  (c) `getScriptVersions` malformed-data → typed throw (not `return []`) (`:610`);
  (d) unguarded `as List` → guarded (`:675`); (e) one-sided `> 299` → `< 200 || > 299`
  (`:552, :664`).
- RED tests for null-`success` + non-list `data`.

#### W7-8 — Versions tab blank [P1] (UX W7-1)
- `widgets/script_details_versions_tab.dart`: tab renders empty in the real dialog
  (Wave-6 test mounted it standalone, bypassing the layout path). The backend has no
  `/versions` route (404), so the tab should show its "No version history" empty-state.
- Fix the layout/lazy-load so the empty-state renders; add a test that mounts the tab
  *via the dialog*. If no version data ever exists, hide the tab honestly.

#### W7-9 — Dead "Marketplace Website" link [P2] (UX W7-2)
- `settings_screen.dart:385` + `app_config.dart:10-13`: link 404s in dev, 530s in prod
  default. Relabel honestly ("API endpoint") or point at a real deployed UI.

#### W7-10 — Polls contradictory identity state [P2] (UX W7-3)
- `dapp_runner_screen.dart` already has the authenticated principal locally; the bundle
  re-derives it via a canister `whoami` that fails when the replica is down → "No profile"
  contradicts the runner chrome "Signed as". Inject the host-known principal into the
  bundle's initial state.

#### W7-11 — Candid type classification DRY [P2] (static W7-05)
- 23 `startsWith` heuristic sites across `candid_smart_form.dart`,
  `candid_args_builder.dart`, `canister_args_editor.dart`. Extract one
  `classifyCandidType(String)` util.

### Phase 2 — Auth-gating cluster (signature auth on every state-changing route)

> The systemic fix. Coordinated backend + frontend. Pattern already exists for
> account/script ops; extend it. Each route: RED test (unsigned → 401; signed-by-non-owner
> → 401; signed-by-owner → 200) → implement → frontend wiring → live verify.
> **Reviewer sequencing note:** vault/passkey/recovery ops all live inside
> `PasskeyService` (`backend/src/services/passkey_service.rs`) — they share one file, so
> they MUST be sequenced vault → passkey → recovery with rebases between (not parallel).
> W7-15 (review) is in a different file and is independent. Use ONE canonical signed
> action-name + payload-shape convention across all of them.
> **Chicken-and-egg resolutions:** first passkey enrolment rides the (signed)
> account-registration session; `recovery/verify` stays open (a locked-out user has no
> keypair by definition) but is rate-limited + Argon2id-bounded.

#### W7-12 — Signature-gate vault routes [P1] (backend W7-003)
- `handlers/vault.rs:74-181` (create/get/update): require Ed25519 signature over
  `{account_id, action, timestamp, nonce}`; resolve account_id from verified pubkey.
- Frontend `vault_crypto_service.dart`/caller signs with the profile keypair.

#### W7-13 — Signature-gate passkey register/delete [P1] (backend W7-004)
- `handlers/passkey.rs:27-62,123-144`: require an already-authenticated session before
  enrolment/deletion; bind the new credential to the proven owner. First-time enrolment
  rides the (signed) account-registration session.

#### W7-14 — Recovery: auth-gate generate, rate-limit verify [P1] (backend W7-005/007)
- `POST /recovery/generate`: require signature auth (codes are minted at setup, when
  logged in). Never return plaintext codes without prior auth.
- `POST /recovery/verify`: rate-limit per account_id + IP.

#### W7-15 — Review signature auth + DB integrity [P1/P2] (backend W7-006/016/017)
- `handlers/reviews.rs:46-74`: require Ed25519 signature; resolve `user_id` server-side.
- Migration: `CREATE UNIQUE INDEX ON reviews(script_id, user_id)`; FK `user_id → accounts(id)`.

#### W7-16 — update-script-stats: remove dead endpoint or gate [P3] (backend W7-018)
- **Reviewer finding:** `POST /update-script-stats` has ZERO frontend callers (grep
  confirms the Flutter app never calls it). Verify where download counts ARE
  incremented; if nowhere, **remove the dead unauthenticated endpoint** (YAGNI) rather
  than gate it. Only add auth/cap if a real caller exists.

### Phase 3 — Robustness, coverage & polish

#### W7-17 — Misc backend robustness [P2/P3] (backend W7-011/012/013/014/019/021/022/024)
- `nonce` DB UNIQUE constraint (kill TOCTOU) + handle conflict (W7-011).
- passkey challenge-delete `.ok()` → log/surface (W7-012).
- `hash_recovery_code().expect()` → `?`-propagate (W7-013).
- `ENVIRONMENT` → typed enum, single source, loud warn when unset in non-dev (W7-014).
- migration error distinguish (duplicate-column vs real fault) (W7-022).
- reuse `tokio::Runtime` via `OnceLock` in canister_client FFI (W7-019).
- `auth.rs:154` `unwrap_or_default()` → propagate (W7-021).
- `cleanup.rs` bind const (W7-024); `script_service.rs:336` `eprintln!` → `tracing` (W7-09 static).

#### W7-18 — Test coverage gaps [P2] (test W7-G1/G2)
- `script_context_menu.dart` (249 lines, 7 callbacks, 0 tests) → widget tests.
- `script_editor_dialog.dart` (192 lines, dialog boundary untested) → widget tests.

#### W7-19 — UX polish [P3] (UX W7-4..10)
- Avatar initials: word-based ("Wave Seven"→"WS", not "WA").
- Run-panel leading icon: use `iconUrl` (📦 only as fallback), mirroring the tile.
- Distinct Copy-button labels ("Copy public key" / "Copy IC principal").
- Wizard username placeholder: drop `alice_dev` template slop.
- Principal clipping consistency + tap-to-copy in dapp chips.
- Canister-card a11y: dedup the doubled name (`excludeSemantics`).
- Profile-chip a11y: clean sentence label, exclude avatar initials.

#### W7-20 — Low-signal test cleanup [P3] (test W7-L1..L5)
- `download_workflow_test.dart` → real workflow or honest rename/fold.
- Tighten 4 bare-`Exception` assertions; await fire-and-forget `.then()`.

## §3. Execution order + parallelism

Serialized git index (shared working tree + caches). Suggested sequence:

1. **Phase 1 isolated fixes** (W7-1..W7-11) — each one commit; group per-file where
   safe. Backend security fixes first (W7-1..W7-6), then frontend (W7-7..W7-11).
2. **Phase 2 auth-gating** (W7-12..W7-16) — coordinated; one route-group per commit,
   backend RED→GREEN then frontend wiring.
3. **Phase 3** (W7-17..W7-20) — robustness, coverage, polish.

## §4. Success criteria (Definition of Done)
- User-visible change reachable from the running app (UX WUs).
- `flutter analyze` clean; cited tests green; `cargo nextest` + `clippy` green.
- No silent errors; single-source constants; typed errors / signature auth, not heuristics.
- Security: no route trusts a client-supplied identity; SQLi closed; entitlement gated.
- Confidence ≥ 8/10. One commit per unit.

## §5. Change log
(populated as units land)

| WU | Commit | Summary |
|----|--------|---------|
| plan | (this commit) | Wave-7 plan |
| review | — | `.tmp/wave7-plan-review.md`: 13 security claims verified real; W7-2 revised; auth-cluster sequencing; W7-16 reclassified |
| W7-1 | `867760c4` | `category` filter parameterized (closes live SQLi); RED test proves `OR 1=1--` no longer leaks private scripts |
| W7-3 | `dfbe36bb` | shared `crypto_util::constant_time_eq`; wired into admin token + recovery code + webhook (de-duped) |
| W7-5 | `71dd7d2d` | signed download now calls `validate_replay_prevention` + records audit; replay → 401 |
| W7-6 | `e20ffdfc` | webhook 500→503 + generic msg (no `ICPAY_WEBHOOK_SECRET` leak); detail in logs |
| W7-2 | `22e96a6b` | GET `/scripts/:id` never ships paid `bundle` (closes `?account_id=` entitlement bypass); new signed `POST /scripts/:id/entitlement` returns `{purchased, owns}`; 3 frontend consumers re-wired to the signed check |
