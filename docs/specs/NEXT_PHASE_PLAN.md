# Next-Phase Plan — Tech Debt · Test Quality · UX Review

- **Status:** PLANNING deliverable (no application code changed). Builds on the
  **COMPLETE** UI Excellence Initiative (`UI_EXCELLENCE_PLAN.md` WU-1..9, WU-S1..3,
  all committed; `UX_REVIEW_ROUND3.md` confirms 9/10 confidence, WU-4 empirically
  verified under the mock Secret Service).
- **Date:** 2026-07-02
- **Target:** Linux desktop (`flutter run -d linux`) + backend (Rust/Poem).
  Flutter Web remains **deferred (R-1)**.
- **Method:** every claim below was **re-verified by read/grep on 2026-07-02**.
  Several of the brief's pre-supplied "findings" turned out to be **false or
  already-done** (see §0) — they are dropped, not carried forward.

---

## 0. Grounding summary (what the empirical re-measure found)

| Brief claim | Re-verified verdict | Evidence (measured 2026-07-02) |
|-------------|---------------------|-------------------------------|
| **"NO HTTP timeouts"** in `candid_service.dart`, `passkey_service.dart`, `marketplace_open_api_service.dart` | **FALSE — DROP.** All three already wrap every call. | `rg -c "\.timeout\(" lib` → **24** calls: marketplace (19), passkey (4), candid (1). All bounded by a service `_timeout`. |
| NO file-I/O timeouts in `script_repository.dart`, `bookmarks_service.dart`, `profile_repository.dart` | **CONFIRMED — TD-1.** | 10 unbounded `readAsString()`/`writeAsString()` sites; `rg timeout` in those three files returns **nothing**. |
| 8 analyze issues, all in `ux_helpers.dart` | **PARTIALLY WRONG.** `flutter analyze` (no path) DOES include `integration_test/`; 8 issues total but spread across **4 files** in `integration_test/ux_probe/`. | See TD-3 table. |
| Large files: bookmarks 1866, details-dialog 1518, scripts 1270, account-profile 1239, marketplace-service 1164 | **CONFIRMED** (exact match). | `wc -l` measured. scripts_screen (1270) is the WU-8 *result* (was 2032). |
| Duplicated `Duration(...)` / success-SnackBar colors, "verify what's left" | **Largely DONE by WU-9.** Residual is low-ROI. | `AppDurations` + `AppDesignSystem.successSnackBar`/`sheetRadius` already exist. 39 raw `Duration(` remain but spread thin (max 4/file, 8 in the token file itself). |
| Rust: unbounded blocking ops / threads w/o termination flag / `.unwrap()` on I/O | **ONE real thread violation (backend); per-call JS exec is well-bounded.** | `execute_js_json` (`js_engine/runtime.rs:134`) uses `DEFAULT_BUDGET_MS=100ms` + `MEM_LIMIT=64MB` + interrupt handler (`runtime.rs:25`) that aborts infinite loops (test at `js_engine.rs:682`). Only `backend/src/cleanup.rs:15` spawns an infinite loop with **no** cancellation. `tokio::spawn`/`std::thread::spawn` count in backend+core = **1**. |
| `SCRIPT_COLUMNS_WITH_ACCOUNT` hand-maintained (TD-7) | **Already guarded — DEFER.** | A drift-detection test exists at `models.rs:418-424` (panics on struct/column mismatch). Silent-drift risk is caught. |

**Net:** the live WUs are **TD-1..5**, **TQ-1..3**, **UX-1**. The brief's "no HTTP
timeouts" finding is **stale and dropped**; WU-9 already did the high-ROI DRY work;
the JS engine is **already** time/memory/interrupt-bounded.

---

## 1. Architectural issues REQUIRING a human decision (flagged, not silently decided)

Carried from `UI_EXCELLENCE_PLAN.md` §1. **No change to the prior decisions.** This
plan does NOT touch any of them; recorded for completeness.

> **Prior decisions (unchanged):**
> - **A-2 (R-1): KEEP Flutter Web deferred.** Reversing needs a conditional
>   `*_io.dart`/`*_web.dart` split + WASM QuickJS + WebCrypto — a separate
>   multi-day initiative. **Out of scope.** See `docs/BROWSER_SUPPORT.md`.
> - **A-3 (cross-profile key sharing): DEFER the model tightening.** Documented in
>   `TODO.md` (MEDIUM) + `lib/models/account.dart` FIXME L18/L307. Backend already
>   enforces public-key uniqueness server-side, so no corrupt data reaches the
>   server; WU-4 already *defends in the UI* (surfaces only the active profile's
>   own keypairs). Tightening the client model may surface latent local-state
>   issues needing careful migration → **recommend KEEP AS DOCUMENTED DEBT**, not a
>   WU here. (See §7 ROI honesty for the full defer list.)
> - **TD-7 (SQL column list): DEFER.** `models.rs:418-424` drift-test already
>   catches the risk; derive-from-metadata is lower ROI now.
> - **Key-label editing: DEFER.** Blocked by a missing backend route, not tech debt.

---

## 2. Work Units

> Conventions (same as `UI_EXCELLENCE_PLAN.md` §2): every WU follows the
> **PoC-first** workflow (AGENTS.md §"Mandatory Workflow"). One commit per WU
> (file-split WUs: one commit per file). Every commit leaves `flutter analyze`
> clean and the cited tests green. **TD = tech debt, TQ = test quality, UX = UX.**

---

### TD-1 — Add bounded timeouts to ALL local file I/O
- **Problem (maintainability + rule compliance):** AGENTS.md mandates *"ALL I/O
  operations (local AND network) must have a timeout."* Network I/O is already
  compliant (24 `.timeout()` calls); **local file I/O is not** — 10 sites in the
  three local-persistence services can hang indefinitely on a stalled/corrupt
  filesystem (NFS, fuse, full disk, dying SSD). The app would freeze on profile
  load/save with no error path.
- **Grounding (measured):**
  - `lib/services/profile_repository.dart:74` (writeAsString), `:92` (readAsString),
    `:149` (writeAsString), `:206` (writeAsString).
  - `lib/services/bookmarks_service.dart:97` (readAsString), `:122` (writeAsString).
  - `lib/services/script_repository.dart:64` (writeAsString), `:78` (readAsString),
    `:91` (writeAsString — the corruption-recovery path), `:106` (writeAsString).
  - `rg -n "timeout|Duration" lib/services/{script_repository,bookmarks_service,profile_repository}.dart` → **no matches.**
- **Concrete change:**
  1. Add a single shared bound in `lib/theme/app_design_system.dart` (the existing
     `AppDurations` class): `static const Duration ioOperation = Duration(seconds: 5);`
     (file ops on small JSON; 5s is generous and well above any sane local-disk RTT).
  2. Introduce ONE tiny helper (e.g. in a new `lib/services/file_io.dart` or fold
     into an existing util): `Future<String> readJson(File f)` and
     `Future<void> writeJson(File f, String s)` that wrap `readAsString`/`writeAsString`
     with `.timeout(AppDurations.ioOperation)`. **Single source of truth** for the
     timeout value.
  3. Replace the 10 raw sites with the helper. On `TimeoutException`, **fail loud**
     (propagate — AGENTS.md "no silent failures"); the callers already handle
     `FormatException` (e.g. `script_repository.dart:88`), add `TimeoutException`
     to the same honest-error surface.
- **Dependencies:** none. Independent of all other WUs.
- **Risk:** LOW. Mechanical wrap; behavior is "bounded instead of unbounded" only
  in the failure case.
- **Commit:** `fix(services): TD-1 bound all local file I/O with a shared timeout`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter test test/script_repository_test.dart test/bookmarks_service_test.dart test/secure_storage_unit_test.dart`
  - `just test-feature profile` green.
  - New negative test: a mocked-slow file read (a `Future.delayed` > timeout via a
    test-only seam) raises `TimeoutException` instead of hanging.
  - `rg "readAsString\(\)|writeAsString\(" lib/services` shows every site routed
    through the timeout helper.

---

### TD-2 — Give the backend cleanup job a real termination path
- **Problem (rule compliance):** AGENTS.md mandates *"ALL threads must check a
  level-based termination flag and terminate correctly."* The **only** background
  task in the entire backend (`tokio::spawn`/`std::thread::spawn` count = 1) is an
  **infinite loop with no cancellation**: it runs forever and is merely *dropped*
  on process exit. There is **no** `CancellationToken`, `shutdown`, `ctrl_c`, or
  `SignalKind` anywhere in `backend/src` (verified: `rg` returns empty).
- **Grounding:**
  - `backend/src/cleanup.rs:15-36` — `tokio::spawn(async move { loop { interval.tick().await; … } })`.
  - `backend/src/main.rs:1675` — `cleanup::start_audit_cleanup_job(cleanup_pool).await;`
    (task is fire-and-forget; return value discarded).
  - `backend/src/main.rs:1683` — `Server::new(listener).run(app).await` (Poem blocks
    until process killed; no signal handler wired).
  - `rg "CancellationToken|shutdown|abort\(\)|signal::ctrl_c|SignalKind" backend/src` → **empty.**
- **Concrete change:**
  1. Thread a `tokio_util::sync::CancellationToken` (already a transitive dep via
     tokio; if not present, add `tokio-util = { version = "0.7", features = ["rt"] }`)
     into `start_audit_cleanup_job(pool, shutdown: CancellationToken)`.
  2. Replace the bare `loop` with `tokio::select!` over `interval.tick()` and
     `shutdown.cancelled()`; on cancel, `return` cleanly (log "cleanup job stopped").
  3. In `main.rs`, install a ctrl-C / SIGTERM handler (`tokio::signal::ctrl_c()` +
     Unix `SIGTERM` via `signal::unix::SignalKind::terminate`), create the token,
     pass it in, and `select!` the server `.run()` against the token so SIGTERM
     triggers graceful server + task shutdown. (Server: Poem's `run()` returns the
     `Server` handle; use `.handle()` + `.stop()` if available, else select on the
     future and abort.)
- **Dependencies:** none (backend-only).
- **Risk:** MED. Touches process-lifecycle. Mitigation: keep behavior identical in
  the happy path (no signal ⇒ runs forever as before); the cancellation only adds
  an exit path. Add an integration-style test that asserts `cancel()` makes the
  task return within a bounded time.
- **Commit:** `fix(backend): TD-2 cancellation token + signal-driven graceful shutdown`
- **Acceptance:**
  - `cargo test -p icp-cc-backend cleanup` (or `just` equivalent) green; new test:
    spawn the job, `cancel()`, assert the task completes (use a oneshot to observe
    exit) within 2s.
  - Manual: `just api-dev-up` then `kill -TERM <pid>` → log shows "cleanup job
    stopped" and the process exits cleanly (no orphan).

---

### TD-3 — `flutter analyze` clean: fix the `integration_test/ux_probe` warnings
- **Problem (baseline hygiene):** AGENTS.md's post-change checklist requires
  `flutter analyze` warning-clean. It is **not**: 8 pre-existing warnings linger
  in the UX-probe scaffolding (introduced during the Round-2/3 reviews and never
  swept). Every future WU must pass this gate, so the baseline must be clean first.
- **Grounding (`flutter analyze` output, measured):**
  | File | Line | Issue |
  |------|------|-------|
  | `integration_test/ux_probe/a_first_run_test.dart` | 97 | unused_local_variable (`t`) |
  | `integration_test/ux_probe/b_create_test.dart` | 11 | unused_import (`main.dart`) |
  | `integration_test/ux_probe/b_download_test.dart` | 95 | unused_local_variable (`anySnackbar`) |
  | `integration_test/ux_probe/c_explore_test.dart` | 10 | unused_import (`main.dart`) |
  | `integration_test/ux_probe/r3_helpers.dart` | 76 | invalid_use_of_protected_member (`layer`) |
  | `integration_test/ux_probe/ux_helpers.dart` | 13 | unnecessary_import (`material.dart`) |
  | `integration_test/ux_probe/ux_helpers.dart` | 30 | unintended_html_in_doc_comment (angle brackets) |
  | `integration_test/ux_probe/ux_helpers.dart` | 70 | invalid_use_of_protected_member (`layer`) |
- **Concrete change:** remove the unused vars/imports; escape the `<…>` in the doc
  comment (backtick-wrap or rephrase); for the two `layer` accesses
  (`invalid_use_of_protected_member`), either route through a public Flutter API
  or extract the screenshot capture into a `// ignore: invalid_use_of_protected_member`
  with a one-line justification (screenshot capture genuinely needs the layer).
- **Dependencies:** none.
- **Risk:** TRIVIAL.
- **Commit:** `chore(test): TD-3 fix integration_test/ux_probe analyze warnings`
- **Acceptance:** `cd apps/autorun_flutter && flutter analyze` → **"No issues found!"**

---

### TD-4 — Eliminate panic-across-FFI in `ffi.rs`
- **Problem (correctness/UB):** `ffi.rs` builds C-strings to return across the FFI
  boundary with `CString::new(s).unwrap()`. A Rust **panic across an `extern "C"`
  boundary is undefined behavior**. `CString::new` fails on interior NUL bytes;
  today the inputs are host-built JSON / principals so it "can't happen" — but
  "can't happen" inputs panicking across FFI is exactly the latent-UB class that
  AGENTS.md's "fail fast, no silent failures" wants surfaced as a *defined* error,
  not a crash. The infrastructure to do this **already exists**: every FFI fn has
  an `err_ptr(e)` error-return path (e.g. `ffi.rs:278`); the unwraps just bypass it.
- **Grounding:**
  - `crates/icp_core/src/ffi.rs` — **~17** `CString::new(…).unwrap().into_raw()`
    sites (lines 39, 52, 75, 106, 152, 181, 199, 224, 252, 277, 293, 329, 348, 367,
    388, 434, 495). `:277` is the success arm right next to the existing `err_ptr`
    at `:278` — the template to generalize.
- **Concrete change:** introduce `fn into_cstring_ptr(s: String) -> *mut c_char`
  that maps `CString::new` failure to a JSON error string
  (`{"ok":false,"error":"internal nul byte"}`) and returns *that* via `into_raw`
  (never panics). Replace the ~17 unwraps with calls to it. Purely defensive: the
  happy path is byte-identical; the failure path becomes a defined JSON error
  instead of UB. (Also lets the FFI test suite assert the no-panic contract.)
- **Dependencies:** none (Rust-only). Pairs naturally with TD-2 (same `cargo` gate).
- **Risk:** LOW. Behavior-preserving on all real inputs; the FFI smoke test
  (`test/native_bridge_js_smoke_test.dart` + `crates/icp_core`) gates it.
- **Commit:** `fix(ffi): TD-4 no panics across the C boundary — route CString errors to JSON`
- **Acceptance:**
  - `cargo test -p icp-core` green; new test feeds an interior-NUL string through
    the helper and asserts a `{"ok":false,…}` JSON pointer is returned (no panic).
  - `cd apps/autorun_flutter && flutter test test/native_bridge_js_smoke_test.dart` green.
  - `rg "CString::new\(.*\)\.unwrap\(\)" crates/icp_core/src/ffi.rs` → **empty.**

---

### TD-5 — Centralize semantic status colors (DRY finish-up)
- **Problem (rule compliance):** AGENTS.md: *"a single constant (value) may be
  defined in a SINGLE PLACE ONLY."* WU-9 centralized the success-*SnackBar* green
  and the sheet radius / durations, but **58 raw `Colors.(green|red|orange)`
  literals** remain. Many encode the **same semantic value** in different files
  (success/verified = green, error/delete = red, warning = orange), so a restyle
  or a11y pass (e.g. colorblind-safe palette) touches dozens of sites.
- **Grounding (measured):**
  - `rg -c "Colors\.(green|red|orange)" lib` → **58** across ~15 files. Hotspots:
    `script_details_dialog.dart` (~12, "verified"/"available" green), `bookmarks_screen.dart`
    (~6), `script_card.dart`, `script_creation_screen.dart` (status traffic-lights),
    `scripts_screen.dart`, `script_row_menus.dart` (delete = red ×4).
  - WU-9's `AppDesignSystem.successSnackBar` proves the pattern; `Colors.green` at
    `app_design_system.dart:258` is the existing success token source.
- **Concrete change:**
  1. Add to `lib/theme/app_design_system.dart`: `AppDesignSystem.successColor`,
     `warningColor`, `errorColor` (each a `Color` — the ONE definition), plus
     shades used for backgrounds (`.withValues(alpha: 0.1)` is already the pattern).
  2. Sweep the 58 literals to the semantic token where they encode status
     (success/warning/error). Leave genuinely *non*-status uses (e.g. a decorative
     green gradient) as-is only if documented inline; default to the token.
  3. Do NOT touch `Material`/framework `Colors.*` that aren't status semantics.
- **Dependencies:** ideally after TD-1/TQ-1 (avoids rebase churn in the same
  service/screen files); can start the token addition immediately.
- **Risk:** LOW (mechanical, value-preserving). Wide touch → per-area commits.
- **Commit:** `refactor(theme): TD-5 single-source semantic status colors`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter analyze` clean; `just test` green.
  - `rg "Colors\.(green|red|orange)\b" lib | wc -l` drops sharply (residual only
    the token definitions + documented non-status uses).
  - Colorblind-sanity: tokens make a future palette swap a one-file change.

---

### TQ-1 — Inject a dependency seam into `ScriptsScreen`; close the WU-2/WU-3 widget-test gap
- **Problem (test quality + the explicit brief item):** The single highest-value
  test-quality fix. `ScriptsScreen` constructs its collaborators **internally and
  privately**, so the two shipped UI wins — WU-2 ("Run" snackbar after download)
  and WU-3 ("Publish" snackbar after create) — have **no widget test** and were
  left "code-verified only" in `UX_REVIEW_ROUND3.md` (the only reason they weren't
  empirically screenshotted was input injection, but the underlying *test* gap is
  this DI absence). A dedicated file **documents the gap as a skipped test**.
- **Grounding:**
  - `test/features/scripts/snackbar_actions_coverage_gap_test.dart` — the skipped
    test; its header is the precise diagnosis (collaborators + singleton + private
    methods). Read it first.
  - `lib/screens/scripts_screen.dart:59` — `final MarketplaceOpenApiService
    _marketplaceService = MarketplaceOpenApiService.instance;` (in-place,
    real HTTP).
  - `lib/screens/scripts_screen.dart:97` — `ScriptController _controller =
    ScriptController(ScriptRepository.instance);` (singleton repo).
  - `lib/screens/scripts_screen.dart:436-440` — the WU-2 `SnackBarAction(label:'Run')`.
  - `lib/screens/scripts_screen.dart:576-580` — the WU-3 `SnackBarAction(label:'Publish')`.
- **Concrete change:**
  1. Make the two collaborators **injectable**: add optional constructor params
     to `ScriptsScreen` (or a small `ScriptsScreenServices` value object) defaulting
     to the current singletons — **production behavior is unchanged**, only the
     seam is opened. (Pattern: `ScriptsScreen({super.key, MarketplaceOpenApiService?
     marketplaceService, ScriptController? controller})` → use `?? default`.)
  2. Keep `DownloadHistoryService` / `OnboardingProgressService` injectable too if
     the snackbar paths touch them (the gap-test header lists them).
  3. **Delete the skipped gap test** and replace it with two real widget tests
     (this is the PoC-first proof): pump `ScriptsScreen` with a fake marketplace
     service whose `downloadScript` completes, tap "Run" on the snackbar, assert
     the execution sheet opens with the created `ScriptRecord`; symmetrically for
     "Publish" → `QuickUploadDialog` (and the no-account → registration-wizard branch).
  4. Mocks are on the **service collaborator** (non-crypto orchestration) — this is
     compliant with AGENTS.md (only **cryptography** must not be mocked). Use real
     keypairs for any signing path.
- **Dependencies:** none for the seam; **unblocks** the empirical UX sign-off of
  WU-2/WU-3 (the widget test *is* the verification).
- **Risk:** MED. Opening a seam on the most-used screen — but it's **additive**
  (defaults preserve behavior), and the new tests gate it. Avoid over-injecting
  (KISS): only what the snackbar paths need.
- **Commit:** `test(scripts): TQ-1 inject ScriptsScreen services + real WU-2/WU-3 tests`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter test test/features/scripts/snackbar_actions_coverage_test.dart`
    (renamed from `…_gap_test.dart`, no longer skipped) green.
  - `just test-feature scripts` green.
  - `grep "skip:" test/features/scripts/*snackbar*` → no skipped WU-2/WU-3 tests.
  - WU-2/WU-3 can now be marked **empirically verified** in a Round-4 UX note.

---

### TQ-2 — Marketplace service: add the missing negative/edge tests
- **Problem (test coverage):** `MarketplaceOpenApiService` is the **entire backend
  contract** (1164 lines, ~14 endpoints), yet `test/features/marketplace/` has only
  **5** files and only **2** touch error paths. The negative dimensions that matter
  for a fail-fast app — network failure, 401/403 (bad signature), 404 (missing
  script), malformed JSON, and **timeout** (the timeouts TD-adjacent to this exist
  but their *behavior* on firing is untested) — are largely uncovered.
- **Grounding:**
  - `lib/services/marketplace_open_api_service.dart` — endpoints at `:65` (upload),
    `:105` (get), `:139` (featured), `:162` (trending), `:199`/`:240` (search),
    `:347` (version), `:447`/`:542` (update/publish), `:698`/`:743`/`:775` (account),
    `:815`/`:855` (by-username / by-public-key), `:897`/`:941` (register/delete).
  - `test/features/marketplace/` = `diff_service_test.dart`,
    `script_details_reviews_test.dart`, `script_details_versions_test.dart`,
    `stats_banner_test.dart`, `version_test.dart`. **No** dedicated
    `*_service_error_test.dart`.
- **Concrete change:** add `test/features/marketplace/marketplace_service_error_test.dart`
  (and fold related setup into the existing `test/shared/` helpers — DRY) covering,
  per the highest-risk endpoints (search/get/upload/update/delete/account): HTTP 5xx
  → typed exception; 401/403 → auth exception; 404 → not-found; malformed JSON body
  → decode exception; **timeout firing** (the bound added by the existing
  `_timeout`) → `TimeoutException`. Use a stub `http.Client` (mockito) for HTTP
  shape — **no crypto mocked** (signing helpers stay real where a request body is
  signed). Drop any low-signal "service returns data" test that only restates the
  happy path already covered elsewhere.
- **Dependencies:** none. Independent.
- **Risk:** LOW. Test-only.
- **Commit:** `test(marketplace): TQ-2 negative/edge coverage (5xx/4xx/timeout/malformed)`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter test test/features/marketplace/` green.
  - Coverage delta: the error/exception branches in marketplace_open_api_service
    go from uncovered to covered (assert at least one test per failure class above).

---

### TQ-3 — Fold the scripts test harness; sweep "renders-only" assertions
- **Problem (test maintainability + the brief's "drop low-signal" item):** **30 of
  37** `test/features/scripts/*` tests independently rebuild a
  `MaterialApp(home: Scaffold(body: …))` harness with near-identical setup — DRY
  violation that slows every new scripts test. Separately, the brief asks to
  *scrutinize* low-signal tests; the honest criterion (verified by reading
  `json_format_test.dart`, which is small but **high**-signal) is *"asserts only
  that a widget renders, with no behavior"* — **size is not a signal**. So this WU
  is a focused sweep, not a blind deletion.
- **Grounding:**
  - `rg -l "MaterialApp|ScriptController|setUp\(\)" test/features/scripts/ | wc -l` → **30**.
  - `test/features/scripts/publish_button_test.dart` — example of the harness pattern
    (wraps a `LocalScriptRowTest`); many siblings repeat it.
- **Concrete change:**
  1. Add `test/features/scripts/_scripts_test_harness.dart`: a `pumpScriptRow(…)` /
     `pumpScriptsScreen(…)` helper that owns the `MaterialApp`+`Scaffold`+default
     `ScriptRecord` setup. Migrate the 30 callers (mechanical).
  2. **Sweep** the scripts suite for tests whose only assertion is
     `findsWidgets`/`pumpAndSettle` with no interaction or state change. For each:
     either strengthen it (add the behavior assertion) or delete with a commit
     message naming it. **Do NOT delete by size** — `json_format_test.dart` proves
     tiny tests can be high-signal.
  3. After TQ-1 lands, point the harness at the injectable seam so widget tests
     use fake services by default.
- **Dependencies:** ideally **after TQ-1** (the harness should bake in the seam).
  Otherwise independent.
- **Risk:** LOW–MED. Harness migration is mechanical; the deletion sweep needs
  judgment — keep a net-positive signal bar (delete only provably-redundant tests).
- **Commit:** `refactor(test): TQ-3 fold scripts test harness + drop renders-only tests`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter test test/features/scripts/` green (count
    unchanged-or-up, signal per-test higher).
  - `rg -c "MaterialApp\(" test/features/scripts/` drops to ~1 (the harness).
  - Commit message lists every deleted test with a one-line "why redundant".

---

### UX-1 — Live-app friction audit of the UN-reviewed large screens (review-first)
- **Problem (UX, the brief's "ALWAYS start the app as a real user"):** The UI
  Excellence Initiative concentrated click-reduction on `scripts_screen.dart`.
  Three **large, complex screens got zero friction review** and are prime
  new-vs-returning-user friction surfaces:
  - **"Canisters" tab** = `bookmarks_screen.dart` (**1866 lines**, the app's
    largest screen) — a canister-call dev tool (`_openInlineClient`,
    `CanisterClientSheet`, `popularCanisters`, Candid arg builders) now occupying
    the 2nd nav slot under an *honest* label (WU-7) but with **unexamined** flow.
  - **`script_details_dialog.dart`** (**1518 lines**) — the most-traversed dialog
    (details → download → run), the path WU-2 optimized *after* download but whose
    *in-dialog* affordances were not re-audited.
  - **`account_profile_screen.dart`** (**1239 lines**) — identity/key surface.
- **Grounding (method, per AGENTS.md + Round-3):** launch the **release bundle**
  under Xvfb **with the mock Secret Service** (`scripts/run-with-mock-keyring.sh
  --display :99 …`, proven in `UX_REVIEW_ROUND3.md` Addendum to create real
  profiles), then drive via chrome-cli/screenshots + DOM analysis. **Rebuild the
  bundle first** (Round-3 addendum: stale binaries silently mislead). Genuine
  passkey flows stay out of scope on this box (Linux limitation, per AGENTS.md).
- **Concrete change (REVIEW → findings → derived WUs):**
  1. Produce `docs/specs/UX_REVIEW_ROUND4.md` with, per screen: screenshots (new vs
     returning user), DOM/click-count analysis, and **concrete** proposals in the
     `UI_EXCELLENCE_PLAN.md` proposal format (e.g. "Canisters: collapse the 3-step
     canister-call builder to 1 with a recent-cannisters quick row").
  2. **Re-verify WU-2/WU-3 empirically** now that TQ-1 makes the full `ScriptsScreen`
     pumpable as a Flutter integration test — capture the missing download→Run and
     create→Publish snackbar screenshots (Round-3's only open verification item).
  3. Each accepted proposal becomes a **derived UX WU** (UX-2…) listed in the
     findings doc, gated on the review outcome — **not** pre-specified here (YAGNI).
- **Dependencies:** **after TQ-1** (needed for the WU-2/WU-3 re-verification step).
  The 3-screen friction audit itself is independent and can start immediately.
- **Risk:** LOW (review deliverable; no app code changes in this WU).
- **Commit:** `docs(ux): UX-1 Round-4 review of Canisters/details/account screens`
- **Acceptance:**
  - `docs/specs/UX_REVIEW_ROUND4.md` exists with screenshots under
    `docs/specs/ux_screenshots/round4/`, per-screen click analyses, and ≥1 concrete
    proposal per screen.
  - WU-2/WU-3 have their first in-app screenshots (or the doc states precisely why
    input-injection still blocks it — building on the Round-3 addendum honesty).

---

## 3. Dependency graph

```
   TD-1 (file I/O timeouts) ──┐
   TD-2 (backend cancel) ─────┤
   TD-3 (analyze clean) ──────┼── all independent of each other (parallel wave 1)
   TD-4 (ffi no-panic) ───────┤
   TQ-2 (marketplace negs) ───┘

   TQ-1 (ScriptsScreen DI seam) ──┬──► TQ-3 (harness fold — uses the seam)
                                  └──► UX-1 (WU-2/3 re-verification step needs TQ-1)

   TD-5 (status-color tokens) ── ideally after TD-1/TQ-1 (avoids rebase churn)

   UX-1's 3-screen friction audit ── independent (can run from wave 1)
```

- **Hard edges:** TQ-3 → TQ-1; UX-1's WU-2/3 step → TQ-1.
- **Soft edges (rebase-able only):** TD-5 ↔ TD-1/TQ-1 (same files); all others are
  in disjoint file sets.

---

## 4. Parallel build tracks

| Track | Owns WUs | Touches (primary) | Blocks / notes |
|-------|----------|-------------------|----------------|
| **Track R — Rust/Backend** | **TD-2, TD-4** | `backend/src/{cleanup,main}.rs`, `crates/icp_core/src/ffi.rs` | Independent; single `cargo` gate. TD-2+TD-4 sequential or parallel. |
| **Track F — Flutter services** | **TD-1** (+ TD-5 tokens) | `lib/services/*`, `lib/theme/app_design_system.dart` | Independent. |
| **Track T — Tests** | **TQ-1 → TQ-3, TQ-2** | `lib/screens/scripts_screen.dart` (TQ-1), `test/features/{scripts,marketplace}/*` | TQ-3 waits on TQ-1. |
| **Track A — Analyze hygiene** | **TD-3** | `integration_test/ux_probe/*` | Trivial; land first to reset the gate. |
| **Track U — UX review** | **UX-1** | `docs/specs/UX_REVIEW_ROUND4.md`, screenshots | Friction-audit half is independent; WU-2/3 half needs TQ-1. |

**Recommended launch order:**
1. **Wave 1 (parallel):** TD-3 (15-min gate reset), TD-1, TD-2, TD-4, TQ-1, TQ-2,
   and the **friction-audit half** of UX-1 — all touch disjoint files.
2. **Wave 2:** TQ-3 (after TQ-1), TD-5 (after TD-1/TQ-1 settle their files), and
   the **WU-2/3 re-verification half** of UX-1 (after TQ-1).
3. **Wave 3 (derived):** any UX-2… proposals accepted from UX-1's findings.

---

## 5. Commit cadence & conventions

(Same as `UI_EXCELLENCE_PLAN.md` §5.) One commit per WU; file-split/area WUs one
commit per file/area. Each commit leaves `flutter analyze` clean and the cited
tests green.

- Tech debt: `fix(<area>): TD-<n> …` / `refactor(<area>): TD-<n> …`
- Tests:    `test(<area>): TQ-<n> …` / `refactor(test): TQ-<n> …`
- UX:       `docs(ux): UX-<n> …`
- Never land a code WU without its gating test (AGENTS.md "Write Failing Tests").

---

## 6. Definition of Done + acceptance checklist

A WU/track is DONE when **all** of (mirrors `UI_EXCELLENCE_PLAN.md` §6):

- [ ] **User/maintainer access:** the change is real and reachable (not dead code).
- [ ] **PoC demonstrated** end-to-end before productionizing.
- [ ] **Tests:** the WU's named tests + `just test-feature <name>` pass; a new test
      codifies the behavior (positive + negative/edge where applicable).
- [ ] **Clean:** `cd apps/autorun_flutter && flutter analyze` warning-clean
      (TD-3 makes the *baseline* clean; every later WU keeps it so).
- [ ] **Rust clean:** `cargo test` from repo root green; no new panics across FFI.
- [ ] **Rule compliance:** every I/O has a timeout (TD-1); every background thread
      checks a termination flag (TD-2); single-source constants (TD-5); no
      panic-across-FFI (TD-4).
- [ ] **Minimal diff;** no zombie code / dead imports / legacy comments.
- [ ] **Fail-loud:** no `try { … } catch (_) {}`, no silent no-ops, no cache fallback.
- [ ] **Confidence ≥ 8/10** (else STOP and ask).

### Full-gate command set (before final sign-off)
```bash
# Per-feature, during each WU
just test-feature scripts        # TQ-1, TQ-3
just test-feature marketplace    # TQ-2
just test-feature profile        # TD-1
cargo test                       # TD-2, TD-4

# Whole-app gate (before final sign-off)
cd apps/autorun_flutter && flutter analyze                       # TD-3 + every WU
just test                                                         # Rust + Flutter
rg "\.unwrap\(\)" crates/icp_core/src/ffi.rs | wc -l             # TD-4: 0 on CString
rg "CancellationToken" backend/src | wc -l                       # TD-2: ≥1
rg "readAsString\(\)|writeAsString\(" apps/autorun_flutter/lib/services  # TD-1: all via helper
```

---

## 7. Risk & ROI honesty

**Do first (highest ROI / lowest risk):**
- **TD-3** — trivial, resets the analyze gate for every later WU.
- **TD-1** — direct rule compliance ("all I/O has a timeout"); the genuine gap now
  that HTTP is confirmed already covered.
- **TQ-1** — biggest test-quality win AND unblocks empirical sign-off of WU-2/WU-3
  (the one open verification item from the completed UI initiative).
- **TD-2** — the *only* thread-termination violation in the codebase; small surface.

**Medium ROI / medium risk:**
- **TD-4** — eliminates a latent UB class; defensive, behavior-preserving.
- **TQ-2** — closes real negative-path gaps in the entire backend contract.
- **UX-1** — only genuine new UX value is the 3 un-reviewed large screens (the
  click-reduction surface is done); high information value, low risk.

**Lower ROI / do last:**
- **TD-5** — mechanical DRY finish-up; satisfies the single-source rule but the
  hot-spots already got the worst of it in WU-9.
- **TQ-3** — harness DRY + sweep; net-positive but judgment-heavy; gate behind TQ-1.

**DEFER (with justification — do NOT plan here):**
- **R-1 (Flutter Web)** — human instruction; separate multi-day initiative.
- **A-3 (cross-profile key model)** — architectural; backend already enforces
  uniqueness, WU-4 defends in-UI; tightening may surface latent local-state issues.
- **TD-7 (SQL column list)** — already guarded by the drift-detection test at
  `backend/src/models.rs:418-424`.
- **Key-label editing** — blocked by a missing backend route (feature, not debt).
- **"No HTTP timeouts" finding** — **FALSE** (24 `.timeout()` calls exist); dropped.
- **Persist "Always allow" across restarts** — deferred in the prior plan (WU-5
  notes); not in scope.

---

## 8. What changed vs. the brief (transparency)

The brief supplied 5 pre-measured "findings". Re-measurement changed three:
1. **"NO HTTP timeouts" → FALSE.** All three named services already wrap every call
   (24 total). Dropped. *(This is exactly why the brief demanded empirical
   re-verification.)*
2. **"8 analyze issues, all in ux_helpers.dart" → 8 total but across 4 files** in
   `integration_test/ux_probe/`. Scope of TD-3 widened slightly; still one WU.
3. **Rust "unbounded ops / threads w/o flag / unwrap on I/O" → ONE real violation**
   (`backend/src/cleanup.rs`). The JS engine is **already** time-bounded (100 ms) +
   memory-bounded (64 MB) + interrupt-bounded (kills infinite loops). ffi.rs
   `.unwrap()` is panic-across-FFI (UB class), not "I/O unwrap" — re-scoped to TD-4.

Everything else (large-file sizes, file-I/O gap, DI test gap, marketplace negative
coverage) **confirmed**.
