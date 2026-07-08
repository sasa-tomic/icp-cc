# Quality Initiative — Tech Debt · Test Quality · UX Review · Alignment

- **Status:** PLANNING deliverable (no application code changed). Every claim
  below was **re-verified by grep/glob/read on 2026-07-08** against the CURRENT
  tree. The brief's "likely-live suspects" were measured; several turned out to
  be **already-done** (see §0) and are dropped, not carried forward.
- **Date:** 2026-07-08
- **Scope:** Linux desktop (`flutter run -d linux`) + backend (Rust/Poem) +
  core crate (`icp_core`). Flutter Web *build* is unblocked (R-1); the Web
  *runtime* (R-3 QuickJS + IC agent) remains staged — out of scope.
- **Predecessor (EXTENDS, does not redo):**
  - `docs/specs/NEXT_PHASE_PLAN.md` (2026-07-02) — **COMPLETE.** Its WUs
    (TD-1..5, TQ-1..3, UX-1) are all landed per `TODO.md`. Its §0 grounding
    table is the model this plan follows. Its TD-* IDs are a **different
    series** — this plan starts a fresh TD/TQ/UX/AL series for 2026-07-08.
  - `docs/specs/PROD_READINESS_PLAN.md` (2026-07-01) — older; re-verified
    before borrowing anything (e.g. the `scripts_screen 2702→1670` and Lua
    items it cites are done).
- **Method:** measure, then write. Each WU cites a `rg`/`wc -l`/`flutter
  analyze` result measured on 2026-07-08, with file:line evidence.

---

## 0. Grounding summary (what the empirical re-measure found)

| Brief / suspected claim | Re-verified verdict | Evidence (measured 2026-07-08) |
|--------------------------|---------------------|-------------------------------|
| `backend/src/main.rs` **2875 lines** — over the 2 k rule | **CONFIRMED — TD-1 (highest structural value).** | `wc -l` = **2875**. 44 `#[handler]` fns + 7 inline request structs (`main.rs:816,859,913,992,1046,1118,1145`) + route registration (`main.rs:2037-2125`) + 3 inline `#[cfg(test)]` modules (`:62 webauthn_rp_tests`, `:148 admin_token_tests`, `:2199 payment_http_tests`) + startup helpers. `AppState` is already correctly factored into `models.rs:148`. Mirrors the already-split `services/` + `repositories/` layout. |
| Account handlers map service errors → HTTP status by **`message.contains("…")`** | **CONFIRMED — TD-2 (highest robustness value).** | 4 handlers string-match: `register_account` (`main.rs:~525`), `update_account` (`:~614`), `add_account_key` (`:~660`), `remove_account_key` (`:~703`) all do `message.contains("Signature verification failed" / "already exists" / "Account not found" / "Invalid username")`. Root cause: `account_service.rs` returns `Result<_, String>` across **8** methods (`register_account:29`, `get_account:154`, `get_account_by_public_key:211`, `update_profile:272`, `add_public_key:386`, `remove_public_key:512`, `admin_disable_key:629`, `admin_add_recovery_key:706`) via `Err(format!(…))/Err("…".to_string())`. `script_service.rs` has **2** more. |
| `candid_service.dart` — silent failure + hardcoded Candid fallback | **CONFIRMED — TD-3.** | `_fetchCandidFromRegistry` (`candid_service.dart:60-72`): `catch (e) { // Ignore errors and return null }` + falls back to `_getFallbackCandid` (`:79`) — a hardcoded `switch` of inline Candid strings for 3 canisters (`rrkah-fqaaa…` NNS, `ryjl3-tyaaa…` Ledger, `aaaaa-aa` Mgmt). Plus magic literals: `User-Agent: ICP-Autorun-Flutter/1.0` (`:66`), `Duration(seconds: 30)` (`:64`). Triple rule violation: silent error + fallback + heuristic. |
| `import_keys_dialog.dart` — string-match on `StateError.message` | **CONFIRMED — TD-4.** | `import_keys_dialog.dart:56,59`: `if (e.message.contains('already exists')) … else if (e.message.contains('Decryption failed')) …` on a bare `StateError`. The thrown strings live in `ProfileController.importProfileBackup`. |
| `error_categories.dart` — error classification by substring pattern-lists | **CONFIRMED — TD-5 (Complex).** | `utils/error_categories.dart:95-185`: 6 classifier fns (`_isNetworkError`, `_isAuthenticationError`, `_isValidationError`, `_isNotFoundError`, `_isRateLimitError`, `_isServerError`) each `patterns.any((p) => error.contains(p))`. Partly classifies strings we *control* (our backend HTTP → should use status code at origin), partly opaque OS strings. |
| `ic_icp` shortcode defined in a single place | **VIOLATED — TD-6.** | Backend has `ICPAY_TOKEN_SHORTCODE = "ic_icp"` (`payment_service.rs:41`, single source on the server) BUT the frontend duplicates it as a raw literal `?? 'ic_icp'` (`marketplace_open_api_service.dart:1427`), and tests hardcode `"ic_icp"` (`main.rs:2708`, `payment_service.rs:458`). |
| Frontend route paths duplicated as inline string literals | **CONFIRMED — TD-6.** | `marketplace_open_api_service.dart` builds URLs via `'$_baseUrl/scripts/…'` concatenation at ~25 sites (`:98,164,212,243,266,295,337,458,527,590,623,658,691,786,942,987,1019,1058,…`); `_baseUrl` (`:69`) is `'${AppConfig.apiEndpoint}/api/v1'` — the path *segments* are hand-typed everywhere with no constant table. Backend owns the canonical list (`main.rs:2037-2125`). |
| `catch (_)` silent-failure sweep across `lib` (~40 cited in old plan) | **FALSE — DROP.** | `rg "catch\s*\(\s*_\s*\)" apps/autorun_flutter/lib` → **empty.** There are 171 `catch (e)` blocks, but every sampled one **surfaces** the error (`SnackBar(content: Text('…$e'))`, `debugPrint`, or `setState(_error=…)`): verified in `scripts_screen.dart`, `account_profile_screen.dart`, `download_history_screen.dart`. No silent swallowing. The Flutter error surface is already honest. |
| Rust `.unwrap()` on I/O — sweep backend + core | **LARGELY CLEAN — DROP the sweep.** | `main.rs`: prod-region `.unwrap()` count (lines 1-2198, before `payment_http_tests`) = **0**. `account_service.rs` prod-region (before `:798` test mod) = **0**. `vault.rs` (before `:116`) = **0**. `script_service.rs` (before `:274`) = **0**. `review_service.rs` (before `:112`) = **0**. `payment_service.rs` (before `:240`) = **0**. Only residual: `auth.rs:322,328` — `normalized.chars().next().unwrap()/.last().unwrap()` on a username already validated non-empty (provably-safe; tidy to `.expect("validated non-empty")` if desired — trivial, not a WU). |
| Thread/task termination flag — "one infinite-loop spawn" | **DONE — DROP.** | `backend/src/cleanup.rs:17,24` — `start_audit_cleanup_job(pool, shutdown: CancellationToken)` + `cleanup_loop` selects on `shutdown.cancelled()` (`:45`). `main.rs:2168-2184` installs `shutdown_on_signal` (ctrl-c + SIGTERM, `:1865`) and `Server::run_with_graceful_shutdown(app, shutdown.cancelled(), Some(30s))`. The `std::thread::spawn` in `canister_client.rs:909` is **inside `#[test] call_anonymous_timeout_fires_against_blackhole`** — test-only blackhole-listener scaffolding, not a prod thread. |
| HTTP network I/O timeouts (was 24 `.timeout()` calls) | **DONE — DROP.** | Unchanged since NEXT_PHASE_PLAN §0; all marketplace/passkey/candid calls remain bounded. |
| File-I/O timeouts (TD-1 prior) | **DONE — DROP.** | `AppDurations.ioOperation = Duration(seconds: 5)` exists (`app_design_system.dart:734`); local file ops routed through the timeout helper. |
| JS engine time/mem/interrupt bounds | **DONE — DROP.** | `js_engine/runtime.rs` `DEFAULT_BUDGET_MS=100ms` + `MEM_LIMIT=64MB` + interrupt handler; test at `js_engine.rs:682`. |
| `flutter analyze` baseline not warning-clean (TD-3 prior) | **DONE — DROP.** | `cd apps/autorun_flutter && flutter analyze` → **"No issues found!" (4.0s)** measured 2026-07-08. |
| Paid-bundle entitlement gate | **DONE — DROP.** | `get_script` (`main.rs:332`) strips `bundle` for paid scripts; `purchases` UNIQUE(`account_id,script_id`) idempotent webhook (`006_*`). |
| Duplicated semantic status colors (TD-5 prior) | **DONE — DROP.** | `AppDesignSystem.successColor`/… centralized; prior WU landed. |
| Large Flutter files (account_profile 1919, scripts 1670, marketplace-svc 1481, details-dialog 1194, canister-sheet 1072, profile_menu 976, dapp_runner 929) | **WATCH (under 2 k, not a hard rule violation).** | All below the 2 k split threshold. `account_profile_screen.dart` (1919) + `account_service.rs` (1892) are the closest — flag in §1; do NOT pre-emptively split (high risk for marginal gain; revisit if they cross 2 k). |

**Net:** the live, high-value work is **TD-1** (main.rs split), **TD-2** (typed
errors), **TD-3..6** (honest-error + single-source finishes), **TQ-1..2**,
**UX-1** (Round-5 review), **AL-1**. The brief's "silent-failure sweep",
".unwrap() sweep", and "thread termination" items are **stale — dropped** with
evidence. This is a smaller, sharper plan than the brief implied, which is
exactly what empirical grounding is for.

---

## 1. Architectural issues REQUIRING a human decision (flagged, not silently decided)

> **Decision-free by default.** This plan proceeds on the safe default for each;
> the flags below are recorded so a human can redirect before the relevant WU
> starts. None block Wave 1.

- **A-1: Should the `main.rs` split (TD-1) co-locate tests in `handlers/*` or
  move them to a top-level `tests/`?** Default: **co-locate** each `#[cfg(test)]
  mod` with its handler module (Rust idiom; keeps the test next to the code;
  matches how `cleanup.rs:219` already co-locates its cancellation test).
  Alternative (extract to `backend/tests/`) doubles the import surface for no
  gain. Flag if a separate integration-test crate is preferred.
- **A-2: Is Flutter Web now a *supported* target (R-2/R-4/R-5 landed)?**
  `flutter build web` succeeds and Ed25519 + ICP principal + vault crypto +
  passkeys are real on Web (per `TODO.md` "Deferred"). But R-3 (QuickJS exec)
  + IC canister HTTP agent remain stubbed (loud `UnsupportedError`). Default:
  **keep Web "build-only" in this plan** — no UX/TQ WU targets Web until R-3
  lands (separate multi-day initiative, `docs/BROWSER_SUPPORT.md`). Flag if the
  human wants Web promoted to a first-class UX surface now.
- **A-3: DB — stay on SQLite or move to Postgres?** `HUMAN_EXPECTATIONS.md` §4
  says *"Postgres if a database is ever needed."* The backend currently ships
  dual SQLite+Postgres migrations (`backend/migrations/*_sqlite.sql` +
  `*.sql`). Default: **no DB move in this plan** — the entitlement/webhook work
  proved SQLite sufficient for current scale, and a cutover is its own
  initiative. Flag if the human wants Postgres promoted to primary now (would
  allow dropping the `_sqlite` migration duplication — a real DRY win).
- **A-4: Should the route-path constants be shared cross-language (codegen)?**
  TD-6 centralizes routes *within* Dart and *within* Rust separately. A single
  shared source (e.g. OpenAPI codegen) is heavier and not justified by current
  route count (~40). Default: **two single-sources** (one per language). Flag
  if the human wants a contract-gen step.

---

## 2. Work Units

> Conventions (same as `NEXT_PHASE_PLAN.md` §2): every WU follows the
> **PoC-first** workflow (AGENTS.md). **One commit per WU** (file-split WUs:
> one commit per extracted module). Each leaves `flutter analyze` clean, the
> cited tests green, and `cargo nextest` + `cargo clippy` clean.
> **TD = tech debt, TQ = test quality, UX = UX, AL = alignment.**

---

### TD-1 — Split `backend/src/main.rs` (2875 lines) into domain handler modules

- **Problem (rule compliance + maintainability):** AGENTS.md: *"Files over 2 k
  lines should be split into logical units."* `main.rs` is the **only** file in
  the repo over 2 k (2875). It mixes 44 `#[handler]` functions, 7 inline
  request structs, the full Poem route table, 3 inline test modules, and
  startup/shutdown wiring in one file. This is the single biggest structural
  win and the lowest-controversy large refactor: the `services/` and
  `repositories/` directories already prove the module-per-domain pattern the
  backend wants.
- **Grounding (measured):**
  - `wc -l backend/src/main.rs` = **2875**.
  - `rg -c "#\[handler\]" backend/src/main.rs` = **44**.
  - Inline request structs: `main.rs:816 (PasskeyRegisterStartRequest)`,
    `:859 (PasskeyAuthStartRequest)`, `:913 (PasskeyDeleteRequest)`,
    `:992 (VaultBlobRequest)`, `:1046 (VaultGetQuery)`,
    `:1118 (RecoveryGenerateRequest)`, `:1145 (RecoveryVerifyRequest)`.
  - Route table: `main.rs:2037-2125` (`Route::new().at("/api/v1/health", …)`).
  - Startup helpers: `is_development:24`, `is_localhost_webauthn_rp:28`,
    `warn_if_broken_prod_passkey_rp:35`, `is_insecure_admin_token:118`,
    `warn_if_insecure_prod_admin_token:122`, `warn_if_icpay_unconfigured:190`,
    `verify_script_ownership:222`.
  - Inline test modules: `:62 webauthn_rp_tests`, `:148 admin_token_tests`,
    `:2199 payment_http_tests` (the webhook/entitlement suite — 148 tests).
  - `AppState` is **already** in `models.rs:148` (no move needed).
  - Sibling layout exists: `backend/src/services/{account,script,review,payment,passkey}_service.rs`
    + `mod.rs`; `backend/src/repositories/{account,script,review,passkey,purchase}_repository.rs`
    + `mod.rs`.
- **Concrete change (mirror the services/ pattern):**
  1. Create `backend/src/handlers/` with one module per domain and a `mod.rs`:
     `health.rs`, `scripts.rs`, `accounts.rs`, `passkey.rs`, `vault.rs`,
     `recovery.rs`, `payments.rs` (config + webhook + download-entitlement),
     `reviews.rs`, `admin.rs`. Move each `#[handler]` fn into its domain
     module. Move the 7 request structs to **co-locate** with their handler
     module (or, if shared, into `models.rs` alongside `AppState`).
  2. Move startup-validation helpers (`warn_if_*`, `is_*`, `verify_script_ownership`)
     into `backend/src/startup_checks.rs`.
  3. Relocate the 3 inline test modules to co-located `#[cfg(test)] mod` blocks
     inside the relevant handler module (e.g. `payment_http_tests` →
     `handlers/payments.rs`; `webauthn_rp_tests` → `handlers/passkey.rs` or
     `startup_checks.rs`; `admin_token_tests` → `handlers/admin.rs`).
  4. `main.rs` becomes thin wiring only: `mod` declarations, `AppState`/pool
     construction, the `Route::new().at(…)` table (still readable in one
     screen-full), signal handling, `Server::run_with_graceful_shutdown`.
     Target: **< 400 lines.**
  5. Route paths referenced in the table can stay as string literals **here**
     (single location: the registration site) — TD-6 handles the *frontend*
     route-constant dedup, not the backend registration strings.
- **Dependencies:** none. Fully self-contained backend refactor. Soft-preferred
  **before TD-2** (so the typed-error change lands in already-isolated handler
  modules, not in the monolith), but can proceed independently.
- **Risk:** MED. Large but mechanical; behavior-preserving (pure move). The
  148-test `payment_http_tests` suite + `cargo nextest` (233 tests) gate any
  regression. **Mitigation: one commit per extracted module** (compile + test
  after each) so a bisect stays granular; keep `pub(crate)` visibility minimal.
- **Commit:** one per module, e.g. `refactor(backend): TD-1a extract handlers/scripts`,
  … `TD-1h slim main.rs to wiring`. Final: `refactor(backend): TD-1 main.rs 2875→<400 (handler modules)`.
- **Acceptance:**
  - `cargo nextest run` (all 233) + `cargo clippy -- -D warnings` green.
  - `wc -l backend/src/main.rs` < 400; no `handlers/*.rs` over ~600.
  - The `payment_http_tests` entitlement/webhook cases pass unchanged (proof of
    behavior preservation).
  - `rg "#\[handler\]" backend/src/main.rs` → **0** (all relocated).

---

### TD-2 — Replace account-handler error-string heuristic with typed errors

- **Problem (rule compliance — the explicit directive):** AGENTS.md /
  HUMAN_EXPECTATIONS: *"Replace heuristics with fundamentally more robust
  techniques — instead of checking if a 'wrong' substring is present, eliminate
  the possibility of the wrong strings existing."* Four account handlers decide
  the HTTP status by **substring-matching the service's English error string**.
  Rename a message, add a translation, or change capitalization and the status
  silently degrades to a wrong code. The robust technique is a **typed error
  enum**: the service returns a variant, the handler matches the variant.
- **Grounding (measured):**
  - Handlers: `register_account` (`main.rs:~525`), `update_account` (`:~614`),
    `add_account_key` (`:~660`), `remove_account_key` (`:~703`) — each a chain
    of `if message.contains("Signature verification failed") → 401`,
    `…("already exists"|"already registered") → 409`, `…("Account not found"|"Key not found") → 404`,
    `…("Invalid username"|"Timestamp out of range") → 400`.
  - Root cause: `account_service.rs` returns `Result<_, String>` on **8**
    methods (cited in §0) via `Err(format!("Username '{}' already exists", …))`
    (`:66`), `Err("Public key already registered".to_string())` (`:77,448`),
    `Err("Signing public key does not belong to this account".to_string())`
    (`:302,416,543`), etc. `script_service.rs` has 2 `Result<_, String>` too.
- **Concrete change:**
  1. Define a typed error enum in `backend/src/services/account_service.rs`
     (or a new `services/error.rs`): `AccountError { NotFound, Conflict,
     BadRequest, SignatureFailed, Internal }`, each carrying the human message
     + an associated `StatusCode` (via an `impl` / `IntoResponse`). **Single
     place** mapping variant → status.
  2. Change the 8 `Result<_, String>` returns to `Result<_, AccountError>`
     (`Err(AccountError::Conflict("Username … already exists".into()))`, etc.).
  3. Handlers become `match` on the variant (or `err.into_response()` if the
     enum implements `IntoResponse`) — **zero `.contains()`**. Delete the
     string-matching chains.
  4. Apply the same pattern to the 2 `Result<_, String>` in `script_service.rs`
     (`ScriptError`) where a handler maps them to status.
  5. Keep the human-readable message in the variant payload so the response
     body / logs are unchanged from the user's perspective (the JSON shape
     stays identical).
- **Dependencies:** ideally **after TD-1** (handlers already isolated) — soft
  edge; can be done in the monolith if TD-1 is delayed.
- **Risk:** MED. Touches the service→handler contract for account ops. Fully
  gated by the existing `payment_http_tests` + account service tests +
  **TQ-1** (new variant tests). Behavior-preserving on the wire (same status +
  same body) — that is the acceptance bar.
- **Commit:** `refactor(backend): TD-2 typed AccountError replaces string-matching`
- **Acceptance:**
  - `rg "message\.contains\(" backend/src` → **0** in account/script handlers.
  - `cargo nextest` green; TQ-1 covers each `AccountError` variant → status.
  - Diff-proof: a sampling of `payment_http_tests` assertions on status + body
    pass unchanged.

---

### TD-3 — Make `candid_service.dart` honest (no silent failure, no hardcoded fallback)

- **Problem (3 rule violations in one function):** AGENTS.md / HUMAN_EXPECTATIONS:
  *"no silent failures"*, *"no offline mode / no cached fallbacks"*, *"replace
  heuristics with robust techniques"*. `_fetchCandidFromRegistry` catches all
  errors with `// Ignore errors and return null`, then falls back to a
  **hardcoded switch of inline Candid strings** for 3 well-known canisters. A
  stale/wrong hardcoded Candid silently feeds the canister-call builder
  incorrect method signatures — exactly the "wrong strings existing" class.
- **Grounding (measured):**
  - `candid_service.dart:60-72` — the `try { http.get } catch (e) { // Ignore } return null`.
  - `candid_service.dart:79-…` — `_getFallbackCandid(canisterId)` `switch` with
    inline Candid for `rrkah-fqaaa-aaaaa-aaaaq-cai` (NNS), `ryjl3-tyaaa-aaaaa-aaaba-cai`
    (Ledger), `aaaaa-aa` (Management).
  - Magic literals: `User-Agent: ICP-Autorun-Flutter/1.0` (`:66`),
    `Duration(seconds: 30)` (`:64`) — neither from a shared constant.
- **Concrete change:**
  1. **Surface the error loudly**: replace the swallowed catch with a typed
     result — propagate a `CandidFetchException` (network / non-200 / empty-body
     variants) so the caller (the canister-call builder UI) can show *"Couldn't
     load Candid for <canister>: <body> (<code>)"* instead of silently degrading.
  2. **Delete `_getFallbackCandid`** (the hardcoded inline Candid). Rationale: a
     hardcoded Candid is a silent fallback by another name; if a canister's
     Candid is needed it must be fetched from the real registry
     (`icp-api.io/api/v2/canister/…/candid`) or, for a curated set, from a
     **maintained data file** loaded explicitly and versioned (not inlined in
     app logic). If the human wants a curated fallback, it becomes an explicit,
     logged, user-visible "using bundled Candid (may be stale)" path — never
     silent. (Default per HUMAN_EXPECTATIONS: **remove**; fail loudly.)
  3. Centralize the two literals: `User-Agent` → a single `AppConfig.userAgent`
     (or `http_headers.dart` shared constant); the timeout →
     `AppDurations.ioOperation`-equivalent for network (reuse the existing
     network-timeout token; do not introduce a second `30`).
- **Dependencies:** none (Flutter-only).
- **Risk:** LOW–MED. Removing the fallback changes behavior for the 3
  well-known canisters when the registry is unreachable — but that is the
  *intended* honesty gain (today it silently lies). Mitigation: confirm the
  registry endpoint is reachable in normal operation (it is the same source
  `dfx` uses); the loud error is the correct UX.
- **Commit:** `fix(candid): TD-3 surface fetch errors; drop hardcoded Candid fallback`
- **Acceptance:**
  - `rg "Ignore errors|_getFallbackCandid" apps/autorun_flutter/lib` → **0**.
  - New test: network failure / non-200 → typed `CandidFetchException` (no
    null, no fallback string). Positive: 200 + body → the Candid string.
  - `just test-feature canister-client` (or the canister_client feature) green.

---

### TD-4 — Typed exceptions in `import_keys_dialog` (replace `StateError` string-match)

- **Problem (heuristic):** `import_keys_dialog.dart:56,59` branches on
  `e.message.contains('already exists')` / `e.message.contains('Decryption failed')`
  applied to a bare `StateError`. The dialog guesses the failure cause from
  English phrasing; rename the thrown string and the UX silently mis-routes
  ("Invalid password" shown for an already-exists profile).
- **Grounding:** `import_keys_dialog.dart:50-65` — `on StateError catch (e)`
  with the two `.contains()` branches; the strings originate in
  `ProfileController.importProfileBackup` (and the crypto layer it calls).
- **Concrete change:**
  1. Define typed exceptions in the profile import path (e.g. in
     `lib/services/profile_repository.dart` or a `lib/utils/profile_errors.dart`):
     `ProfileAlreadyExistsException`, `BackupDecryptionException`,
     `InvalidBackupFormatException` (replacing the `FormatException`/`StateError`
     throws).
  2. Throw the typed variants at the origin (where the condition is detected).
  3. The dialog `catch`es **by type** — no `.contains()`. Each type → its exact
     user message.
- **Dependencies:** none (Flutter-only). Pairs naturally with TD-3 (same
  "typed-error replaces heuristic" theme).
- **Risk:** LOW. Additive error typing; the user-visible messages are preserved
  (acceptance: same copy per cause).
- **Commit:** `refactor(profile): TD-4 typed import exceptions replace string-match`
- **Acceptance:**
  - `rg "\.contains\('already exists'\)|\.contains\('Decryption failed'\)" apps/autorun_flutter/lib` → **0**.
  - `just test-feature profile` green; new tests assert each typed exception →
    the right dialog message (positive per-cause + the unknown-cause fallback).

---

### TD-5 — Robustify `error_categories.dart` (status-code at origin, not string at display)

- **Problem (heuristic — the directive's canonical example):**
  `utils/error_categories.dart` classifies an error for UX display by running
  the error **string** through six substring pattern-lists. For errors we
  *produce* (our backend's HTTP responses), the robust source of truth is the
  **HTTP status code**, which we already have at the call site — classifying the
  string later discards that signal and re-derives it flimsily.
- **Grounding:** `error_categories.dart:95-185` — `_isNetworkError`,
  `_isAuthenticationError` (matches `'401','unauthorized','forbidden','403'`),
  `_isValidationError`, `_isNotFoundError` (`'404','not found'`),
  `_isRateLimitError` (`'429'`), `_isServerError` (`'500','502','503','504'`).
  Callers feed these an `error.toString()` blob.
- **Concrete change (judgment-heavy — do the investigation first):**
  1. Audit where the classified string originates: (a) our own
     `MarketplaceOpenApiService` HTTP errors (we **control** — carry the status
     code on the exception and classify by code); (b) OS/socket errors (we
     don't control — string match is the only option, but narrow + document it).
  2. For (a): attach `int? statusCode` to the marketplace exception types
     (already partially typed — `PurchaseRequiredException`,
     `DownloadAuthException` exist) and classify by code at the point of
     display. Delete the corresponding pattern entries.
  3. For (b): keep a *minimal*, documented residual string-match (e.g. socket
     family) with a comment naming the uncontrolled source. Eliminate every
     pattern whose source we control.
- **Dependencies:** ideally **after TD-2** (same typed-error discipline) and
  informed by TQ-1.
- **Risk:** MED (Complex — needs the origin audit before coding). Mitigation:
  the PoC step is the audit table itself (string → source → controlled?); only
  then refactor.
- **Commit:** `refactor(errors): TD-5 classify by status code at origin, not string at display`
- **Acceptance:**
  - Audit table committed in the plan/spec (or doc comment) naming each
    residual pattern's uncontrolled source.
  - `rg "'40[1349]'|'50[0234]'|'unauthorized'|'forbidden'" apps/autorun_flutter/lib/utils/error_categories.dart`
    → only documented OS-string residuals remain.
  - Existing UX error-display tests green; new tests assert status-code
    classification for the marketplace error types.

---

### TD-6 — Single-source constants sweep (`ic_icp`, route paths, User-Agent)

- **Problem (rule compliance):** AGENTS.md / HUMAN_EXPECTATIONS: *"a single
  constant (value) may be defined in a SINGLE PLACE ONLY; everywhere else
  (incl. tests/docs) uses a symbolic name."* Three confirmed violations:
  - `ic_icp` shortcode — backend const exists but the frontend hardcodes the
    literal and tests inline it.
  - Frontend route path segments — ~25 inline concatenations, no constant table.
  - `User-Agent` header string — single inline literal (TD-3 will move it; this
    WU owns the shared home).
- **Grounding (measured):**
  - `ic_icp`: `payment_service.rs:41 (const)`, `marketplace_open_api_service.dart:1427 (?? 'ic_icp')`,
    `main.rs:2708 + payment_service.rs:458 (tests)`.
  - Route paths: `marketplace_open_api_service.dart:98,164,212,243,266,295,337,458,527,590,623,658,691,786,942,987,1019,1058,…`
    (`'$_baseUrl/scripts/…'`).
  - `User-Agent`: `candid_service.dart:66`.
- **Concrete change:**
  1. Create `lib/services/api_routes.dart` (or extend `AppConfig`): a single
     `abstract final class ApiRoutes` with each path as a `static const` (e.g.
     `scriptsSearch`, `script(String id)`, `scriptDownload(String id)`,
     `paymentsConfig`, `accountsByUsername(String)`). Migrate the ~25 inline
     sites. The backend registration list (`main.rs:2037-2125`) remains the
     cross-language source of truth (A-4); this WU only de-duplicates *within*
     Dart.
  2. `ic_icp`: the backend config already returns `shortcode` in the `/payments/icpay/config`
     payload (the frontend consumes it at `marketplace_open_api_service.dart:1427`).
     **Drop the `?? 'ic_icp'` fallback** — if config is missing, fail loudly
     (the 503 path already warns at startup); do not shadow it with a literal.
     Tests reference the backend `ICPAY_TOKEN_SHORTCODE` constant symbolically
     (or assert equality to the returned config value, not a bare literal).
  3. `User-Agent`: one `AppConfig.userAgent` constant; TD-3 references it.
- **Dependencies:** coordinate with TD-3 (shares the User-Agent home). Otherwise
  independent.
- **Risk:** LOW. Mechanical de-dup; behavior identical. The `ic_icp` fallback
  removal is an *intended* honesty gain (consistent with HUMAN_EXPECTATIONS).
- **Commit:** `refactor(services): TD-6 single-source ApiRoutes + shortcode + UA`
- **Acceptance:**
  - `rg "ic_icp" apps/autorun_flutter/lib` → **0** (no bare literal; uses
    config value).
  - `rg "scripts/search|scripts/trending|/accounts/" apps/autorun_flutter/lib/services` →
    only inside `api_routes.dart`.
  - `flutter analyze` clean; `just test-feature marketplace` green.

---

### TQ-1 — Tests for the new typed-error / honest-error boundaries (TD-2/3/4/6)

- **Problem (test quality + gating the refactor WUs):** TD-2 introduces an
  `AccountError` enum, TD-3 a `CandidFetchException`, TD-4 typed profile-import
  exceptions, TD-6 removes the `ic_icp` fallback. Each needs positive **and**
  negative coverage so the refactor is regression-proof and the rule
  ("eliminate the wrong strings") stays enforced. AGENTS.md: a new behavior
  must be codified by a test.
- **Concrete change:** add focused tests (no crypto mocked — real keypairs for
  any signed path):
  - `backend`: per-`AccountError` variant → expected `StatusCode` + body shape
    (one test per variant; negative for the "unknown → Internal" arm). Gates TD-2.
  - Flutter `candid_service`: network-fail / non-200 / empty-body → typed
    `CandidFetchException`; 200+body → Candid string. Gates TD-3.
  - Flutter `import_keys_dialog`: each typed exception → correct dialog copy;
    unknown-cause → generic copy. Gates TD-4.
  - Flutter `marketplace` config: missing-shortcode path surfaces loudly (no
    silent `ic_icp`). Gates TD-6.
- **Dependencies:** hard-depends on TD-2/3/4/6 (tests the types they create).
  Fold into each WU's commit if built by the same agent; otherwise this WU
  lands immediately after, per track.
- **Risk:** LOW (test-only).
- **Commit:** `test(errors): TQ-1 typed-error boundary coverage (Account/Candid/Profile/shortcode)`
- **Acceptance:** each TD's acceptance "new test" bullet is satisfied; no
  overlap with existing tests (AGENTS.md).

---

### TQ-2 — Targeted test-suite audit: drop low-signal, fold shared setup (new areas)

- **Problem (test maintainability — the directive's "drop tests that don't
  provide meaningful signal"):** the suite is large (179 Flutter files + 233
  Rust tests). NEXT_PHASE TQ-3 already pruned ~233 false-confidence *scripts*
  tests and folded the scripts harness — so the scripts area is **excluded**
  from this sweep (do not re-touch). The areas added *since* (ICPay
  entitlement, dapp runner, vault-Web crypto, canister-client) have not had a
  signal audit and may carry renders-only / overlapping cases.
- **Grounding:** `find apps/autorun_flutter/test -name "*_test.dart" | wc -l`
  = **179**; feature counts: scripts 25, marketplace 11, onboarding 7,
  account_profile 9, profile 6, dapps 5, canister_client 4, passkey 3, vault 2,
  web 2. Rust = 233 tests (`rg "#\[test\]|#\[tokio::test\]" backend/src crates`).
- **Concrete change:**
  1. Audit the **post-TQ-3** areas (marketplace/icpay, dapps, canister_client,
     vault, web) for tests whose only assertion is `findsWidgets` /
     `pumpAndSettle` with no interaction or state change. For each: **strengthen**
     (add the behavior assertion) or **delete** with a commit message naming it
     + the one-line "why redundant". Do **not** delete by size — a tiny test
     can be high-signal.
  2. Fold shared `MaterialApp`/`Scaffold`/service-setup into the existing
     `test/features/_*_harness.dart` pattern where a feature has ≥3 repeated
     harnesses (mirror the scripts harness from TQ-3-prior). DRY without
     over-engineering.
  3. Scrutinize any mocked-HTTP test for false confidence (mock asserting the
     mock). Mocks only at the smallest boundary (the outbound `http.Client`
     call); real crypto everywhere.
- **Dependencies:** none (independent). Do not touch `test/features/scripts/`.
- **Risk:** LOW–MED (judgment-heavy on deletions; keep a net-positive signal bar).
- **Commit:** `refactor(test): TQ-2 prune low-signal + fold harness (marketplace/dapps/canister/vault)`
- **Acceptance:**
  - The audited feature dirs: `flutter test test/features/<dir>` green; test
    count unchanged-or-down only where each deletion is justified in the commit.
  - Commit message lists every deleted test with its "why".

---

### UX-1 — Round-5 live UX review (ICPay purchase flow + dapp runner + account)

- **Problem (UX — the directive, verbatim):** *"ALWAYS by starting the app with
  tmux or chrome-cli as a regular user, NEVER plain code review … MAY NEVER use
  mocks."* Three high-value surfaces have **never** had a live friction review
  against the current build:
  - **The ICPay paid-script purchase CTA** (just landed; `TODO.md` lists 3
    *verify-live* unknowns: hosted-checkout URL/field name, webhook signature
    scheme, end-to-end purchase). This is the highest-value review target.
  - **`dapp_runner_screen.dart`** (929 lines — the dual-path dapp surface, with
    the new "Revoke trust" / "Create a profile to vote" / reactive
    connection-panel affordances).
  - **`account_profile_screen.dart`** (1919 lines — identity/key surface, with
    the new editable key-label flow).
- **Grounding (method, per AGENTS.md + Round-3 addendum):** rebuild the
  **release bundle first** (stale binaries silently mislead), launch under Xvfb
  **with the mock Secret Service** (`scripts/run-with-mock-keyring.sh --display :99 …`,
  proven to create real profiles), drive via chrome-cli (screenshots + DOM).
  New **and** returning user paths. Genuine passkey flows stay out of scope on
  this Linux box (AGENTS.md "Passkey Testing on Linux"). **No mocks in the
  review** — if something can't be exercised without a mock, that's a BUG to
  fix, recorded as a derived WU.
- **Concrete change (REVIEW → findings → derived WUs):**
  1. Produce `docs/specs/UX_REVIEW_ROUND5.md`: per surface, screenshots (new +
     returning), DOM/click-count analysis, spinner-stall checks (> a few sec →
     flag), keyboard-path audit, and **concrete** proposals in the
     `UI_EXCELLENCE_PLAN.md` format.
  2. Special focus: attempt the ICPay **verify-live** trio against the sandbox
     (if the sandbox is network-blocked again, document precisely what blocks
     it and propose the unblock — do not mock around it).
  3. Each accepted proposal → a derived **UX-2…** WU listed in the findings doc,
    gated on review outcome (YAGNI — not pre-specified here).
- **Dependencies:** none for the friction audit (independent from Wave 1). The
  ICPay verify-live half depends only on network availability to the sandbox.
- **Risk:** LOW (review deliverable; no app code in this WU).
- **Commit:** `docs(ux): UX-1 Round-5 review (ICPay purchase / dapp runner / account)`
- **Acceptance:**
  - `docs/specs/UX_REVIEW_ROUND5.md` exists; screenshots under
    `docs/specs/ux_screenshots/round5/`; ≥1 concrete proposal per surface.
  - The ICPay verify-live trio is either confirmed or documented with a precise
    blocker + proposed unblock (no silent skip).

---

### AL-1 — Verify + refresh `HUMAN_EXPECTATIONS.md`; audit `AGENTS.md` drift

- **Problem (alignment — the directive, verbatim):** *"Check (a) mechanical
  alignment with project rules (AGENTS.md) and (b) CRITICAL alignment with
  human values (docs/HUMAN_EXPECTATIONS.md). Keep that file current."* The
  values doc has a single dated implementation note (vault ZK, 2026-07-04) and
  does not yet reflect the ICPay entitlement model, the Web-crypto landing
  (R-2/R-4/R-5), or the dapp dual-path direction as *values* (not status). It
  risks drifting from intent of record.
- **Grounding:** `docs/HUMAN_EXPECTATIONS.md` — 81 lines; §1 product vision
  mentions passkey+vault (with ZK note) and dapp dual-path, but not the
  paid-script/entitlement value or the "Web is build-only until R-3" guardrail
  as a stated value. AGENTS.md "Feature Map" + line counts (e.g. scripts_screen
  cited as 2702 in places) have drifted.
- **Concrete change:**
  1. Add crisp *value* bullets to HUMAN_EXPECTATIONS (not status log): the
     entitlement principle ("paid scripts never leak their bundle; purchase is
     the only authenticated path"), the Web guardrail ("Web builds but does not
     execute scripts until R-3 — never ship a half-stub"), and confirm the dapp
     dual-path bullet is current.
  2. Sweep `AGENTS.md` for stale line-counts / file references (re-measure;
     fix or annotate). Leave a dated "verified" note.
  3. Do **not** rewrite values — only add/refine to match reality. If reality
     diverges from the doc, the doc wins (fix the code separately).
- **Dependencies:** none. Pairs well with the start of Wave 1 (sets the bar).
- **Risk:** TRIVIAL (docs-only).
- **Commit:** `docs(alignment): AL-1 refresh HUMAN_EXPECTATIONS + audit AGENTS drift`
- **Acceptance:** `docs/HUMAN_EXPECTATIONS.md` gains the entitlement + Web
  guardrail bullets; stale counts in AGENTS.md corrected; dated verify note added.

---

## 3. Execution order + parallelism

```
Track R (Rust backend)   TD-1 (main.rs split)  ──►  TD-2 (typed errors)
                          │                         (soft edge; cleaner post-split)
Track F (Flutter services) TD-3 (candid honest) ─┬─► TQ-1 (boundary tests)
                          TD-4 (import typed)   ─┤
                          TD-6 (constants)      ─┘   (TD-3 + TD-6 share the UA home)
Track T (Tests)           TQ-2 (audit new areas) — independent (no scripts/ touch)
Track U (UX)              UX-1 (Round-5 review)   — independent (plan deliverable)
Track A (Alignment)       AL-1 (values refresh)   — independent, land first

Track Errors-Complex      TD-5 (error_categories) — after TD-2 (informed by typed-error pattern)
```

| Track | Owns WUs | Touches (primary) | Blocks / notes |
|-------|----------|-------------------|----------------|
| **R — Rust/Backend** | **TD-1 → TD-2** | `backend/src/{main.rs → handlers/*, services/account_service.rs, startup_checks.rs}` | TD-1 before TD-2 (soft). One commit per handler module. `cargo nextest`+`clippy` gate. |
| **F — Flutter services** | **TD-3, TD-4, TD-6 → TQ-1** | `lib/services/{candid_service,marketplace_open_api_service}.dart`, `lib/screens/import_keys_dialog.dart`, `lib/services/api_routes.dart` (new) | TD-3 & TD-6 coordinate on UA home; else disjoint. TQ-1 gates the trio. |
| **E — Errors-Complex** | **TD-5** | `lib/utils/error_categories.dart`, marketplace exception types | After TD-2; needs PoC audit table first. |
| **T — Tests** | **TQ-2** | `test/features/{marketplace,dapps,canister_client,vault,web}/*` | Independent; **exclude `test/features/scripts/`** (pruned in TQ-3-prior). |
| **U — UX** | **UX-1** | `docs/specs/UX_REVIEW_ROUND5.md`, screenshots | Independent; ICPay verify-live needs sandbox network. |
| **A — Alignment** | **AL-1** | `docs/HUMAN_EXPECTATIONS.md`, `AGENTS.md` | Trivial; land first to set the bar. |

**Recommended launch order:**
1. **Wave 1 (parallel, disjoint files):** **AL-1** (reset the bar), **TD-1**
   (main.rs split — biggest win, start early), **TD-3**, **TD-4**, **TD-6**,
   **TQ-2**, and the **friction-audit half of UX-1** — all touch disjoint file
   sets.
2. **Wave 2 (dependency-gated):** **TD-2** (after TD-1), **TQ-1** (after
   TD-3/4/6 and gated by TD-2 for the AccountError arm), **TD-5** (after TD-2),
   and the **ICPay verify-live half of UX-1** (needs Wave-1 findings for
   context).
3. **Wave 3 (derived):** any **UX-2…** proposals accepted from UX-1's
   findings (YAGNI — not pre-specified).

- **Hard edges:** TD-2 → TD-1 (soft); TQ-1 → TD-2/3/4/6 (hard); TD-5 → TD-2 (soft).
- **Soft edges (rebase-able):** TD-3 ↔ TD-6 (share the User-Agent constant
  home — agree the home in `api_routes.dart`/`AppConfig` up front, then both
  can proceed).

---

## 4. Success criteria (Definition of Done)

A WU/track is DONE when **all** of:

- [ ] **User/maintainer access:** the change is real and reachable (not dead code).
- [ ] **PoC demonstrated** end-to-end before productionizing (esp. TD-2 wire-shape
      preservation, TD-3 loud-error UX, UX-1 real-app screenshots).
- [ ] **Tests:** the WU's named tests + `just test-feature <name>` pass; a new
      test codifies the behavior (positive + negative/edge).
- [ ] **Flutter clean:** `cd apps/autorun_flutter && flutter analyze` →
      "No issues found!" (baseline already clean — keep it so).
- [ ] **Rust clean:** `cargo nextest run` (233) green; `cargo clippy -- -D warnings` clean.
- [ ] **Rule compliance:** no silent errors (TD-3); single-source constants (TD-6);
      typed errors replace heuristics (TD-2/4/5); threads check termination flags
      (already DONE — §0); every I/O has a timeout (already DONE — §0).
- [ ] **Minimal diff;** no zombie code / dead imports / legacy comments.
- [ ] **Fail-loud:** no `try { … } catch (_) {}`, no silent fallbacks, no
      `if (status != 200) return null`.
- [ ] **Confidence ≥ 8/10** (else STOP and ask).

### Full-gate command set (before final sign-off)
```bash
# Per-feature, during each WU
just test-feature marketplace     # TD-6, TD-5, TQ-2 (marketplace)
just test-feature profile         # TD-4
just test-feature canister-client # TD-3
just test-feature scripts         # (excluded from TQ-2; sanity only)
cargo nextest run                 # TD-1, TD-2
cargo clippy --all-targets -- -D warnings

# Whole-app gate (before final sign-off)
cd apps/autorun_flutter && flutter analyze
just test
rg "message\.contains\(" backend/src                           # TD-2: 0 in acct/script handlers
rg "_getFallbackCandid|Ignore errors" apps/autorun_flutter/lib  # TD-3: 0
rg "ic_icp" apps/autorun_flutter/lib                            # TD-6: 0 bare literals
wc -l backend/src/main.rs                                       # TD-1: < 400
rg "#\[handler\]" backend/src/main.rs                           # TD-1: 0 (all moved)
```

---

## 5. Commit cadence & conventions

(Same as `NEXT_PHASE_PLAN.md` §5.) One commit per WU; file-split WUs one commit
per extracted module/area. Each commit leaves `flutter analyze` clean and the
cited tests green. **Never land a code WU without its gating test.**

- Tech debt: `fix(<area>): TD-<n> …` / `refactor(<area>): TD-<n> …`
- Tests:    `test(<area>): TQ-<n> …` / `refactor(test): TQ-<n> …`
- UX:       `docs(ux): UX-<n> …`
- Alignment:`docs(alignment): AL-<n> …`

---

## 6. Risk & ROI honesty

**Do first (highest ROI / lowest risk):**
- **AL-1** — trivial; sets the alignment bar for the whole initiative.
- **TD-1** — the single biggest structural win; the only >2 k file; mechanical
  (move-only) with a 233-test gate. Start in Wave 1.
- **TD-3** — fixes a triple rule violation (silent error + fallback + heuristic)
  in one small file; high honesty gain, low risk.
- **TD-6** — direct single-source compliance; mechanical.
- **UX-1** — the ICPay purchase flow has *never* been live-reviewed and has 3
  open verify-live items; highest information value.

**Medium ROI / medium risk:**
- **TD-2** — the directive's canonical "replace heuristics" item; touches the
  service→handler contract but is wire-preserving and well-gated.
- **TD-4** — small, clean typed-exception win.
- **TQ-1** — regression-proofs the refactor WUs.

**Lower ROI / do last / Complex:**
- **TD-5** — genuinely Complex (needs an origin audit before code); only do
  after TD-2 establishes the typed-error pattern.
- **TQ-2** — net-positive but judgment-heavy; the worst offenders were already
  pruned in TQ-3-prior, so this is a lighter touch on the newer areas.

**DEFER (with justification — do NOT plan here):**
- **R-3 (Web QuickJS + IC agent)** — multi-day initiative; `docs/BROWSER_SUPPORT.md`.
- **A-3b (structural `profileId` on `ProfileKeypair`)** — invariant already
  enforced (`profile_invariants.dart`); wide blast radius; YAGNI (`TODO.md`).
- **Postgres cutover (A-3)** — its own initiative; would let us drop the
  `_sqlite` migration duplication.
- **Split the ~1.9 k files** (`account_profile_screen.dart` 1919,
  `account_service.rs` 1892) — *under* the 2 k rule; high risk / marginal gain;
  revisit only if they cross 2 k.
- **"Silent-failure sweep in lib", ".unwrap() sweep", "thread-termination sweep"**
  — all **stale** (§0): `catch (_)` = 0; prod `.unwrap()` ≈ 0 (2 provably-safe
  in `auth.rs`); backend already cancellation-safe. **Dropped with evidence.**

---

## 7. What changed vs. the brief (transparency)

The brief supplied several "likely-live suspects." Re-measurement changed most:

1. **"Silent failures: ~40 `catch (_)` in lib" → FALSE.** `catch (_)` count is
   **0**; the 171 `catch (e)` blocks all surface the error (verified by
   sampling). The *real* silent failure is one function — `candid_service.dart`
   (→ TD-3), not a sweep. *(This is exactly why the brief demanded empirical
   re-verification.)*
2. **"`.unwrap()` on I/O sweep" → LARGELY CLEAN.** Prod-region `.unwrap()` is
   **0** in `main.rs`, `account_service.rs`, `vault.rs`, `script_service.rs`,
   `review_service.rs`, `payment_service.rs`; 2 provably-safe in `auth.rs`.
   The Rust code is already disciplined — no sweep WU.
3. **"Thread/task termination — one infinite-loop spawn" → DONE.** `cleanup.rs`
   now takes a `CancellationToken`; `main.rs` has `shutdown_on_signal` +
   `run_with_graceful_shutdown`. The `std::thread::spawn` in `canister_client`
   is **test-only**. No WU.
4. **"main.rs split" → CONFIRMED** (2875 lines, 44 handlers) → **TD-1**,
   highest structural value.
5. **"Heuristics to replace" → CONFIRMED and bigger than stated.** Not just
   `getVault`-style status matching: the *entire account-handler* status
   mapping is string-based (→ TD-2), plus `import_keys_dialog` (→ TD-4),
   `candid_service` fallback (→ TD-3), and `error_categories.dart` (→ TD-5).
6. **"Duplicated constants" → CONFIRMED** for `ic_icp`, route paths, User-Agent
   (→ TD-6). The HTTP-timeout / file-timeout / status-color duplication cited
   in older plans is **already fixed** (§0).

The live plan is therefore **smaller and sharper** than a naive reading of the
brief: one big structural split (TD-1), one canonical robustness fix (TD-2),
three honest-error/single-source finishes (TD-3/4/6), one Complex heuristic
(TD-5), focused test work (TQ-1/2), a Round-5 UX review (UX-1), and an
alignment refresh (AL-1).
