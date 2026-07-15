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
| W7-4 | `2022b4f8` | central `cors::build_cors()` — explicit allow-list (loopback dev `127.0.0.1` / `localhost` any port + `CORS_ALLOWED_ORIGIN` env, default `https://icp-mp.kalaj.org`); TRACE/CONNECT dropped; RED test proves `https://evil.example.com` is not reflected |
| W7-16 | `78e3412b` | dead unauthenticated `POST /update-script-stats` removed entirely (handler, route, `UpdateStatsRequest` model, re-export); empirically zero frontend callers + signed download is the sole downloads-counter write site |
| W7-6 follow-up | `26433e6e` | `GET /payments/icpay/config` 503 no longer echoes `ICPAY_PUBLISHABLE_KEY`; generic external message + `tracing::error!` detail (mirrors W7-6 webhook fix) |
| W7-7 | `a16bfd54` | `marketplace_open_api_service.dart` hardened: null-unsafe `!responseData['success']` → routed through `_decodeSuccessResponse` (a); 3 success-path bypasses (`getCompatibleScripts`, `downloadPaidScriptBundle`, `uploadScript`) now use the shared helpers (b); `getScriptVersions` malformed-data → typed `MalformedVersionsResponseException` instead of silent `return []` (c); unguarded `as List` casts guarded via `_decodeDataField<List>` / `is! List` (d); one-sided `> 299` status bounds eliminated — the helper's `< 200 \|\| > 299` governs all (e); dead `_buildUploadErrorMessage` removed |
| W7-8 | `56196533` | Versions tab removed entirely (widget, dialog state, `getScriptVersions` + `ScriptVersion` + `MalformedVersionsResponseException`, orphaned `DiffViewerDialog`, 4 test files). Backend ships no `/versions` route (404 for every script — `grep "scripts/:id" backend/src/main.rs` confirms absence), so the tab was permanently in its empty-state; Wave-7's live audit caught it rendering BLANK in the real dialog (the Wave-6 regression test had mounted the tab widget in isolation, bypassing the dialog's layout/lazy-load path). YAGNI — restore together with a `/versions` backend route. RED test pumps the dialog via the real layout path and asserts the tab is gone; lazy-load + keyboard tests updated for the 2-tab strip (Details + Reviews) |
| W7-9 | `3e86d801` | Settings → "Marketplace Website" entry removed. The link was dead in every configuration: prod default `https://icp-mp.kalaj.org` → HTTP 530 (Cloudflare 1033, origin unreachable); dev build (embeds the local API endpoint) → HTTP 404 at `/` (backend serves `/api/v1/*`, no UI). No marketplace website is deployed. Relabelling to "API endpoint" would duplicate the existing developer-option row, so the entry was removed (YAGNI). `AppConfig.marketplaceWebUrl` retained — `scripts_screen.dart _shareScript` still builds share URLs from it (a future marketplace-UI deploy will make both work). RED test asserts the entry + its subtitle are absent; Documentation + Report Issue remain |
| W7-10 | `b0306bf4` | On-chain Polls contradictory identity fixed. Root cause: the bundle re-derived the caller's principal via a `whoami` canister call (`lib/examples/06_icp_poll.js` `init` set `state.principal = ""` and only filled it from the `whoami` effect result); when the replica was unreachable, principal stayed empty → body showed "No profile — view-only" while the runner chrome showed the real principal. Fix: `dapp_runner_screen.dart` injects the active keypair's principal into `initialArg.principal`; `06_icp_poll.js init` reads it. The `whoami` effect still fires (refreshes from the canister at the source of truth), but the INITIAL render now matches the chrome. RED test pumps the runner with an active profile and asserts the recorded runtime received the correct principal (no canister round-trip needed for initial identity); a keyless user gets an empty principal (honest view-only) |
| W7-11 | `2b15b7e3` | Candid type classification DRY'd. 26 duplicated `startsWith`/`==`/`contains` Candid-type heuristic lines (across `widgets/candid_smart_form.dart`, `widgets/candid_args_builder.dart`, `widgets/canister_args_editor.dart`) — internally inconsistent (`nat` used `==`, `nat8` used `startsWith`, `nat8foo` silently mis-classified as `nat8`) — replaced by ONE `classifyCandidType(String)` returning a typed `CandidTypeKind` enum (`lib/utils/candid_type_classifier.dart`). The classifier uses full-token matching (regex-extracts the leading `[a-z][a-z0-9_]*` identifier and looks it up in a single keyword→kind table), eliminating prefix-matching entirely. Non-canonical UI aliases (`string`→text, `boolean`→bool, `float`→float64) are folded into their canonical kinds at the table so call-sites no longer repeat them. 37 RED-then-GREEN unit tests codify the classifier contract (scalar/integer/float/aggregate kinds, full-token matching edge cases like `nat8foo`/`natural`/`vector`→unknown, case+whitespace robustness, derived getters `isNumeric`/`isUnboundedInteger`/`isFixedWidthInteger`/`isFloat`/`isAggregate`). All 9 refactored sites are exhaustive Dart-3 switches (no `default`), so future enum extensions are compile-checked. `flutter analyze` clean; 144 candid-related tests green. Historic fall-through semantics preserved verbatim — only nat/nat64/int/int64 get `int.parse`, only float64 gets `double.parse`, all other numeric widths still pass through as text (matching prior buggy-but-shipped behaviour; documented in-code at each switch). Behaviour is identical for every canonical Candid type the parser emits |
| W7-12 | `2d1fb2f3` | Vault routes signature-gated (closes W7-003 IDOR). New shared `signature_gate::verify_signed_account_request` helper factors out the proven `entitlement_check` (W7-2) 5-step pattern (resolve `account_id` SERVER-SIDE from the verified public key → verify Ed25519 over canonical payload → replay prevention → record audit fail-closed) so vault/passkey/recovery/review gates share ONE implementation. `POST /vault` + `PUT /vault` require a signature over `{action:"vault:create"/"vault:update", account_id:<resolved>, nonce, ts}`; the AES-GCM blob nonce is renamed to `blob_nonce` on the wire (replay nonce occupies `nonce`). `GET /vault` converted to signed `POST /vault/get` (signing a GET cleanly is awkward). `account_id` is NO LONGER in the request body — resolved server-side, so an attacker cannot target another account's vault. 5 RED-then-GREEN gate unit tests (real Ed25519 + real SQLite): unknown key→401, empty sig→401, signed-by-non-owner→401, owner→Ok(resolved), replay→401. Frontend `PasskeyService` gains a `_signAccountRequest` helper (reuses `AccountSignatureService.signCanonicalPayload`, single source of truth for canonical signing) and threads a `ProfileKeypair` into create/get/updateVault; the 3 screens + `profile_menu._navigateToVault` pass `activeKeypair` (keypairs live in local secure storage, independent of the vault blob — no circular dependency at unlock time). All vault/passkey feature tests updated to the new wire shape + green; `flutter analyze` clean |
| W7-13 | `792d5cd8` | Passkey register/delete signature-gated (closes W7-004 account takeover). `POST /passkey/register/start` requires a signature over `{action:"passkey:register", account_id:<resolved>, nonce, ts}`; the server resolves account_id SERVER-SIDE and binds the WebAuthn challenge to that proven owner — closing the exploit where anyone could enrol their OWN authenticator on ANY account (then authenticate as the victim / lock them out). `DELETE /passkey/:id` likewise signs `{action:"passkey:delete", passkey_id, account_id:<resolved>, nonce, ts}`; only the owner can delete their passkey. `register/finish` needs no separate signature: it completes a challenge whose account_id was bound to the proven owner at the (now-gated) start. `authenticate/start`+`/finish` STAY OPEN (passkey auth IS the login mechanism — cannot require prior auth; finish already proves passkey possession). `passkey_list` left open (low-sensitivity metadata). Frontend `PasskeyService.registerPasskey`/`deletePasskey` take a `ProfileKeypair` and emit the signed body (reuses the W7-12 `_signAccountRequest` helper); the management screen + 2 launch sites (account_profile_screen, registration_wizard) thread `activeKeypair`/`widget.keypair`/`_profile.primaryKeypair`. All passkey feature tests green; `flutter analyze` clean |
| W7-14 | `1a8d91a9` | Recovery: generate signature-gated, verify open + rate-limited (closes W7-005 takeover/lockout + W7-007 brute-force oracle). `POST /recovery/generate` mints+returns PLAINTEXT codes; now signature-gated (`{action:"recovery:generate", account_id:<resolved>, nonce, ts}`) — the server resolves account_id SERVER-SIDE, so an attacker can no longer mint fresh codes for ANY account (wiping the victim's real codes → lockout) and receive the plaintext. `POST /recovery/verify` STAYS OPEN (a locked-out user has no keypair by definition) but now throttles via a new sliding-window `SlidingWindowRateLimiter` (per `account_id`+source IP via poem's `RealIp`): after 5 failed codes in 15 min → 429; a success clears the history. The codes remain Argon2id-hashed (each guess expensive); the rate-limit adds the missing per-caller cap. `GET /recovery/status/:account_id` left open (returns only a count). New `rate_limit` module (3 unit tests) + an HTTP-level RED test proving 5 wrong codes → `valid:false`, 6th → 429 (real handler + TestClient). Frontend `PasskeyService.generateRecoveryCodes` takes a `ProfileKeypair` (no UI callers yet — wired for the future setup screen). 304 backend tests pass; clippy clean; all passkey feature tests green; `flutter analyze` clean |
| W7-15 | (this commit) | Review signature-gate + DB integrity (closes W7-006 unsigned mutation + W7-016 dup-check TOCTOU). `POST /scripts/:id/reviews` now requires an Ed25519 signature over `{action:"review:create", script_id, rating, account_id:<resolved>, nonce, ts}`; the author (`user_id`) is resolved SERVER-SIDE from the verified public key — never trusted from the body. Closes the W7-006 exploit where anyone could post a review as any user and 1★/5★-bomb any script (featured/trending ordering is rating-driven). DB: new `CREATE UNIQUE INDEX reviews(script_id, user_id)` closes the app-level dup-check TOCTOU (W7-016); a concurrent race past the service's `COUNT(*)` guard now hits the constraint, which the service maps (via `sqlx::Error::Database::is_unique_violation()`) to the typed `ReviewError::Conflict` → 409. **FK follow-up (W7-017):** the `user_id → accounts(id)` FK was intentionally NOT added — sqlx enforces FKs, which would break the review-service unit tests that exercise the service in isolation with synthetic `user_id`s; the signature gate already resolves `user_id` server-side (always a real account id in production), so the FK is marginal defense-in-depth only (requires a service-test refactor — tracked as a follow-up). 2 HTTP-level RED tests (real Ed25519 + real SQLite): unknown key→401, valid owner→201, duplicate→409. Frontend `MarketplaceOpenApiService.createReview` added (signed, throws typed `ReviewAlreadyExistsException` on 409) — no UI consumes it yet (Reviews tab is read-only); shipped so the compose flow is reachable when a submission UI lands. 306 backend tests pass; clippy clean; `flutter analyze` clean (the one unrelated `justfile_dart_define_test` failure is pre-existing — `IC_AGENT_PROXY_HOST` NEW-1 mismatch, untouched by this work) |
| W7-19 | `5d3fcccc` | 7 surgical UX-polish fixes (all P3, UX W7-4..10). (1) Avatar initials: word-based via new `computeInitials(name)` helper (`lib/utils/user_initials.dart`) — first letter of first + last word ("Wave Seven"→"WS", "John Doe"→"JD"), single word → first letter ("Alice"→"A"), empty/whitespace → "?"; replaces 3 buggy `substring(0,2)`/`substring(0,1)` call sites (header avatar, `ProfileAvatarButton`, `_ProfileSwitchRow`); RED-first unit tests (8). Fixed the `navigation_test` that had codified the buggy "JO" for "John Doe" → "JD". (2) Run-panel leading icon: new shared `ScriptLeadingIcon` widget (renders `iconUrl` artwork via `CachedNetworkImage`, falls back to emoji/📦 on load failure) reused by BOTH the list tile and the run panel (`script_execution_bottom_sheet`) — the panel previously hard-coded 📦 even for scripts with valid artwork (W6-9 missed the panel). (3) Distinct copy-button labels: the 4 identical `tooltip:'Copy'` IconButtons on the account screen → "Copy public key" / "Copy IC principal" (+ SnackBar labels "IC principal copied…"); RED widget test asserts distinct tooltips. (4) Wizard username placeholder `alice_dev` → `Choose a username`; also the registration wizard's Twitter field `@alice_dev` → `@your_handle` (same slop). (5) Dapp-runner principal chip: was a dead, clipped non-copyable "qtjow-…-cae"; now shows the FULL principal (monospace, wraps) and is tap-to-copy + SnackBar — matches the Account screen. Dead `_shortenPrincipal` removed. `_StatusChip` gains `onTap` (ripple + trailing copy icon) + `monospace`. (6) Canister-card a11y: the card-level `Semantics(label:'Open …')` already exposes the name; inner title `Text` wrapped in `ExcludeSemantics` so screen readers don't announce "Open NNS Registry NNS Registry …"; widget test asserts the name appears exactly once in the open-action label. (7) Profile-chip a11y: clean single-sentence label ("Profile: Wave Seven. Tap to open." / "Profile menu, no account registered. Tap to open.") replaces the raw concatenated "Profile menu - no account registered WA Profile No account"; avatar initials + visible texts wrapped in `ExcludeSemantics` so nothing splices in; widget test asserts initials are not in the label. `flutter analyze` clean; 415 widget/feature/utils tests green across the touched dirs |
| W7-17 | `571c45e6` | Misc backend robustness (8 fixes, P2/P3). **W7-011** — `signature_audit.nonce` UNIQUE constraint kills the replay-prevention TOCTOU (SELECT-COUNT then INSERT); new `auth::is_audit_replay_error` + `classify_audit_write` (single source) → every audit-recording site (`signature_gate`, `download_script`, `entitlement_check`, 6×`account_service`) maps the unique-violation to 401 replay vs 5xx fault; RED test proves duplicate-nonce INSERT fails + classifies as replay (negative control: distinct nonces both succeed). **W7-012** — 4× silent `delete_challenge().ok()` in `passkey_service` → `consume_challenge` helper that `tracing::warn!`s the failure (best-effort, but visible). **W7-013** — `hash_recovery_code().expect()` → `?`-propagate as `PasskeyError::Internal` (no panic under Argon2 memory pressure). **W7-014** — `ENVIRONMENT` → typed `Environment` enum (`OnceLock`-cached, single source) closing the reader disagreement (`main.rs` warn-helpers said "development" on unset while `is_development()` returned false); unset/empty/unrecognised → loud `tracing::warn!`; main/health/is_development/warn-helpers all threaded through the enum. Side-effect of consistency: `is_development()` now true on unset, so `reset_database` is permissive in a bare `cargo run` (correct for a dev tool — prior 403 was a symptom of the disagreement). **W7-022** — `ALTER TABLE ADD COLUMN` migration loops distinguish SQLite "duplicate column name" (idempotent → debug) from any other DDL fault (fatal panic), so a real schema problem is never masked as "already migrated". **W7-019** — canister FFI reuses a `OnceLock<tokio::runtime::Runtime>` instead of constructing+tearing down a fresh runtime per `fetch_candid`/`call_anonymous`/`call_authenticated` (mirrors `ic_proxy`'s `OnceLock<reqwest::Client>`). **W7-021** — `auth.rs:154` `serde_json::to_string(value).unwrap_or_default()` (would silently verify a signature over an EMPTY payload on the impossible failure) → `.expect` with the documented invariant that `serde_json::Value` serialises infallibly (NaN/Inf cannot inhabit `Value::Number`); `?`-propagation rejected as it would ripple to 24 callers for a provably-impossible error. **W7-024** — `cleanup.rs` `format!`-interpolated `AUDIT_RETENTION_DAYS` → `.bind()` (constant SQL text). **W7-09 static** — lone `eprintln!` in `script_service.rs` test fixture → `tracing::error!` with error context. `cargo nextest run -p icp-marketplace-api` → 308 passed / 1 skipped (+2 W7-011 tests); clippy clean; `icp_core` 102 passed + clippy clean |
| W7-18 | `be86b238` | Coverage for the two zero-test widgets (verified by symbol search). **ScriptContextMenuSheet** (`script_context_menu_test.dart`, 12 tests): local vs marketplace action rendering + cross-section hiding; null-callback hides its action; already-downloaded + downloading-state variants; tapping each of the 7 action callbacks fires it exactly once and closes the sheet (pumped via the production `showModalBottomSheet`). **ScriptEditorDialog** (`script_editor_dialog_test.dart`, 6 tests): opens with record title + source loaded (not dirty); edit + Save persists the editor content via a real `ScriptController`/`MockScriptRepository` (the I/O boundary — no crypto/network), pops, success snackbar; Save failure surfaces 'Save failed' + keeps the dialog open; Cancel clean pops without saving; Cancel dirty shows the discard-confirm; keep-editing on the guard keeps the dialog open. **Drive-by P1 fix discovered by writing the marketplace test** (the exact value of W7-18): the avatar did `Text((item.emoji ?? '📦')[0])`, which returns a lone UTF-16 surrogate for any non-BMP emoji → `ArgumentError: string is not well-formed UTF-16` at paint time, breaking the context menu for EVERY marketplace script (emoji always null → `📦` fallback) and for the local default `📜`. Replaced with a code-point-safe first character (`runes.first`) so multi-unit emoji render whole — approved as a minimal surgical fix. `flutter analyze` clean; 18 new tests green |
| W7-20 | `9c657f86` | Low-signal test cleanup (W7-L1/L2/L5). **W7-L1** — deleted the mis-named `download_workflow_test.dart` (36 lines asserting 3 static empty-state strings on `DownloadHistoryScreen`, exercising no workflow); its empty-state signal was already covered (better) by `download_history_browse_test.dart` which drives the real Browse-Marketplace CTA. Folded the one non-redundant assertion (the screen title) into that test; dropped the rest as no-signal smoke. **W7-L2** — the 4 bare `throwsA(isA<Exception>())` in `marketplace_service_error_test.dart` verified load-bearing (the code under test, `_decodeSuccessResponse`, throws a typed `Exception` from its `success != true` branch; a `TypeError` regression would be an `Error`, not an `Exception`, so the bare assert FAILS if one leaks through — the W6-3 contract). Left as-is + one clarifying comment explaining the bare-ness; NOT tightened (tightening would add no signal — sibling tests already pin wording). **W7-L5** — replaced the two fire-and-forget `.then((x) => flag = x)` sites (`first_run_setup_gate_test`, `wizard_close_and_profile_recovery_test`) with `await` inside an async `onPressed`, removing the latent microtask-drain flake where the flag assertion raced the Navigator-pop Future. `flutter analyze` clean; all touched tests green |
