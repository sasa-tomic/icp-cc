# ICP-CC Prod-Readiness Plan (TypeScript/QuickJS Runtime)

- **Status:** Authoritative — Ready for Execution
- **Date:** 2026-07-01
- **Scope:** (1) Finish cosmetic Lua cleanup; (2) Radical DRY/KISS/YAGNI tech-debt reduction; (3) Test-quality rebalance (drop low-signal, fill gaps, fold, DRY helpers); (4) UX-review plan (click-reduction targets); (5) Prod-readiness / deployment.
- **Predecessor:** `docs/specs/CLEANUP_PLAN.md` (Lua sunset — DONE, WU-1..WU-10) and `docs/specs/SCRIPTING_RUNTIME_MIGRATION.md` (ADR — Phase 4 done).
- **Baseline (per orchestrator, trusted):** Rust core 95/95 · backend 88/88 · SDK vitest 90/90 · `flutter analyze` clean · git clean · `lua_source`/`luaSource`/`ScriptLanguage`/`detectLanguage` all ZERO in production code (rename done).

> **This plan EXTENDS `CLEANUP_PLAN.md`.** It does not re-open any completed work.
> Every Work Unit (WU) is independently committable and leaves the build GREEN.

---

## Section 1 — Executive Summary

### Where we are
The Lua→TypeScript/QuickJS migration is functionally complete. The codebase compiles,
all existing test suites pass, and `lua_source`→`bundle` is fully renamed. What remains
is **not** functional: it is *polish, hygiene, coverage, UX, and operational readiness*.
The system can run today, but it is not yet *shippable* with confidence.

### The five things this plan delivers
1. **A 100% TypeScript narrative** — no stale "Lua" mentions that confuse authors/AI.
2. **A radically simpler codebase** — collapse the worst duplication and the single
   largest files (`scripts_screen.dart` 2,702 lines; `ffi.rs` boilerplate; the 40-site
   forbidden `catch (_)` pandemic).
3. **High-signal tests** — drop framework-asserting / Lua-fixture tests; add the missing
   TS-lifecycle / validation-negative / FFI / marketplace-round-trip coverage.
4. **A click-reduced UX** — a separate swarm runs the app as a real user (Linux desktop,
   since Flutter Web is broken — see R-1) and produces concrete reduction targets.
5. **A production path** — CI (none exists today), a fixed prod-passkey config bug, a
   validated deploy runbook, and a decision on whether Web is a supported target.

### Success criteria (prod-readiness "done")
- [ ] `grep -rin "lua"` across `apps/autorun_flutter/lib`, `crates/`, `backend/src`, `packages/*/src` returns **zero unintentional hits** (test-data string `'lua script'` and ADR history excluded).
- [ ] `cd apps/autorun_flutter && flutter analyze` clean; `flutter test` green (re-baselined count after drops/adds).
- [ ] `cargo nextest run` (workspace) green; `cargo clippy --workspace --all-targets -- -D warnings` green.
- [ ] `npm test` in `packages/marketplace-sdk` + `packages/create-marketplace-script` green.
- [ ] **Zero `catch (_)` silent-failure sites** in `apps/autorun_flutter/lib` (all 40 converted to typed catches or removed).
- [ ] A TS bundle can be authored → validated (incl. `eval`/`Function`/`import`/`Intl.*` rejection) → uploaded → downloaded → executed through the app, on a Linux desktop build.
- [ ] **CI is green on every push** (`.github/workflows/` exists and runs Rust + Flutter + SDK gates).
- [ ] **Prod passkey RP is correctly configured** (`WEBAUTHN_RP_ID`/`WEBAUTHN_RP_ORIGIN` point at the public hostname, not `localhost`).
- [ ] A deploy runbook exists and has been dry-run once end-to-end (binary → docker → compose → health → upload/download/exec a signed TS bundle).
- [ ] `PROD_DEPLOYMENT.md` no longer references a second runtime and documents the prod env vars.

### Key items requiring a HUMAN decision (see Section 3)
- **R-1 (HIGH):** Is Flutter Web a supported target? It is currently unbuildable (`dart:ffi` unconditional import). The whole plan assumes desktop+Android are the targets.
- **R-2 (MEDIUM):** The cross-profile key-sharing model violation (`lib/models/account.dart:18,304`) — fix now or accept and document?
- **R-3 (MEDIUM):** CI runner matrix — Linux only (Web can't be tested until R-1 is resolved)?
- **R-4 (LOW):** `scripts_screen.dart` 2,702-line split — approved in principle?

---

## Section 2 — Work Units

ID prefixes: **FC**=Final Cleanup · **TD**=Tech Debt · **TQ**=Test Quality · **UX**=UX Review · **PR**=Prod Readiness.

---

### FC-1 — Drop the dead `syntax_highlighting_test.dart`
**Complexity:** Simple · **Dependencies:** none · **Risk:** Low

`apps/autorun_flutter/test/widgets/syntax_highlighting_test.dart` (83 lines) feeds **Lua**
fixtures (`-- Simple Lua test`, `local function greet`) into `ScriptEditor` — but the
editor is TS-only since `CLEANUP_PLAN` WU-5 (the `lua` highlighter import was deleted and
`language` is hardcoded to `javascript`). The tests assert **framework behavior**, not app
behavior: "CodeField renders", "theme dropdown shows Vs2015/Monokai", "gutter renders".

Per `AGENTS.md`: *"Drop tests that assert framework behavior not app behavior."* This file
is the canonical example.

**Files & exact changes:**
- **DELETE** `apps/autorun_flutter/test/widgets/syntax_highlighting_test.dart` (all 83 lines).

**Verification:**
```bash
cd apps/autorun_flutter && flutter analyze
cd apps/autorun_flutter && flutter test test/widgets --timeout=120s   # remaining widget tests still green
```

**Estimated delta:** −83 lines · −3 tests.

---

### FC-2 — Rename residual cosmetic Lua references in tests + SDK
**Complexity:** Simple · **Dependencies:** none · **Risk:** Low

Mechanical rename of variable names / placeholder strings / comments. None touch logic.

**Files & exact changes:**
1. `apps/autorun_flutter/test/integration/script_upload_api_test.dart`
   - L203,210,233: `largeLuaCode` → `largeBundle` (it holds a TS bundle body — the field is already `bundle:`).
2. `apps/autorun_flutter/test/features/scripts/script_bottom_sheet_test.dart`
   - L7,27,59,91,123,155,193,228: `_validLuaScript` → `_validBundle` (value is a TS bundle).
3. `apps/autorun_flutter/test/widgets/script_execution_progress_test.dart`
   - L180: placeholder `script: '-- lua --'` → `script: '/* ts bundle */'`.
4. `apps/autorun_flutter/test/script_app_host_permission_test.dart`
   - L59: `script: '-- lua --'` → `script: '/* ts bundle */'`.
5. `apps/autorun_flutter/test/ui_conditional_rendering_test.dart`
   - L40,103–104,114: comments "In Lua, this would evaluate to false…" → "In JS, falsy values…" (or delete the comments — they explain a non-existent Lua semantics).
6. `apps/autorun_flutter/test/script_editor_test.dart`
   - L215: `expect(find.text('LUA'), findsNothing);` — the language badge was removed in WU-5; asserting its absence is tautological. **Delete this single assertion** (keep the rest of the test).
7. `packages/marketplace-sdk/src/__tests__/parity.vectors.test.ts`
   - L28: **DELETE** the dead field `expectedLua: unknown;` from `interface ParityCase`. The field is never read (only `expectedJs` is asserted, L99–102); `parity/vectors.json` already dropped `expectedLua` (confirmed: zero hits).
8. `packages/marketplace-sdk/src/__tests__/format.test.ts:17` + `helpers.test.ts:17` + `pilot.e2e.test.ts:62`
   - Comments/describe text "Rust/Lua oracle values", "byte-identical to Rust/Lua oracle", "exact Lua state shape" → drop the "/Lua" qualifier (it's "Rust oracle" / "exact state shape" now). Pure wording.

**KEEP (do not touch):**
- `apps/autorun_flutter/test/features/scripts/search_history_test.dart:100,117,121` — `'lua script'` is **legitimate search-query test data** (a user could type it).

**Verification:**
```bash
cd apps/autorun_flutter && flutter analyze && flutter test test/integration test/features/scripts/script_bottom_sheet_test.dart test/widgets/script_execution_progress_test.dart test/script_app_host_permission_test.dart test/ui_conditional_rendering_test.dart test/script_editor_test.dart --timeout=120s
cd packages/marketplace-sdk && npm test
rg -in "lua" apps/autorun_flutter/test packages   # only legit 'lua script' data + ADR history remain
```

**Estimated delta:** ~0 net lines (renames + ~3 comment trims + 1 dead field + 1 assertion).

---

### FC-3 — Sweep docs for stale Lua instructions + Web/passkey contradiction
**Complexity:** Simple · **Dependencies:** FC-2 (so the sweep is final) · **Risk:** Low

**Files & exact changes:**
1. `AGENTS.md` — **L192–205 ("Passkey Testing on Linux")**: still instructs `flutter run -d chrome` for passkey testing. This is **unreachable** (R-1: Web build broken). Reword: "Passkey testing requires a Web-capable target; the Flutter Web build is currently broken (see TODO.md F-0). Until it is fixed, passkey flows are testable only on macOS/Windows/Android desktop authenticators that the `passkeys` package supports." Cross-link to R-1.
2. `AGENTS.md` Feature Map L156 — already says QuickJS; verify no stray "Lua engine" prose remains.
3. `TODO.md` — verify the "TS App Contracts" / "UI_v1 Widget Types" sections are current (they are, per the read). No change unless FC-2 surfaces a stale ref.
4. `ARCHITECTURE.md`, `README.md`, `LOCAL_DEVELOPMENT.md`, `backend/README.md` — `rg -in "lua\|lua_source"` and update any prose that implies a second runtime. (CLEANUP_PLAN WU-9 covered most; this is the final mop-up.)
5. `parity/README.md` + `parity/vectors.json` `notes` field — verify dual-runtime framing is gone (CLEANUP_PLAN WU-8 target; confirm).

**Verification:**
```bash
rg -in "lua" AGENTS.md ARCHITECTURE.md README.md LOCAL_DEVELOPMENT.md backend/README.md backend/PROD_DEPLOYMENT.md parity/ docs/ TODO.md
# Review each hit; only intentional ADR history in docs/specs/SCRIPTING_RUNTIME_MIGRATION.md + CLEANUP_PLAN.md should remain.
```

**Estimated delta:** ~±20 lines of prose.

---

### TD-1 — `ffi.rs`: collapse CStr-null + error-JSON boilerplate
**Complexity:** Medium · **Dependencies:** none · **Risk:** Low–Medium (FFI signature surface — keep `#[no_mangle]`/`extern "C"` untouched)

`crates/icp_core/src/ffi.rs` (598 lines) repeats two idioms ~10× each:
- The null-safe CStr read: `if ptr.is_null() { "" } else { CStr::from_ptr(ptr).to_str().unwrap_or("") }` (seen at L165–168, L214–217, L265–268, L320–323, etc.).
- The error→JSON→CString: `let err_json = json!({"ok": false, "error": ...}).to_string(); return CString::new(err_json).unwrap().into_raw();` (L92–93, L99–100, L107–109, L117–120, L241–244, L299–301, L466–468, L508–510, L593–595, etc.).

**Files & exact changes:**
- `crates/icp_core/src/ffi.rs`:
  - **ADD** private helpers near `null_c_string()` (L148):
    ```rust
    /// Null-safe CStr read. Returns "" for null or invalid UTF-8.
    unsafe fn cstr_or_empty<'a>(p: *const c_char) -> &'a str {
        if p.is_null() { "" } else { CStr::from_ptr(p).to_str().unwrap_or("") }
    }
    /// Null-safe optional CStr read (None for null).
    unsafe fn cstr_opt<'a>(p: *const c_char) -> Option<&'a str> {
        if p.is_null() { None } else { CStr::from_ptr(p).to_str().ok() }
    }
    /// Allocate a heap C string carrying `{"ok":false,"error":E}`.
    fn err_ptr<E: std::fmt::Display>(e: E) -> *mut c_char {
        CString::new(json!({"ok": false, "error": e}).to_string()).unwrap().into_raw()
    }
    ```
  - **Replace** every repeated block with a one-liner call. Each public `extern "C"` fn keeps its `#[no_mangle]`, signature, and `# Safety` doc — only the body shrinks.
  - The `icp_call_anonymous`/`icp_call_authenticated` `kind` match (L234–238, L292–296) is near-duplicated → extract `fn method_kind(kind: i32) -> MethodKind`.

**Verification:**
```bash
cargo build -p icp_core 2>&1 | tail -3
cargo nextest run -p icp_core 2>&1 | tail -5          # still 95/95
cargo clippy -p icp_core --all-targets -- -D warnings 2>&1 | tail -3
# FFI behavior unchanged: smoke a few symbols from Dart
cd apps/autorun_flutter && flutter test test/native_bridge_js_smoke_test.dart
```

**Estimated delta:** −130 lines net (598 → ~465). No behavior change.

---

### TD-2 — `script_runner.dart`: dedupe `run()` against `_executeCanisterCall`; kill dead branch
**Complexity:** Medium · **Dependencies:** none · **Risk:** Medium (central runtime path — cover with TQ-3 before/after)

`apps/autorun_flutter/lib/services/script_runner.dart`:
- **`run()` L440–478** reimplements resolve-keypair → call-anon/auth → JSON-decode that already lives in `_executeCanisterCall()` (L353–391). ~38 duplicated lines.
- **L526–529**: the `if (result['action'] == 'ui') return ScriptRunResult(ok: true, result: result);` is immediately followed by an identical fallthrough `return ScriptRunResult(ok: true, result: result);` (L530). The `'ui'` branch is dead — delete it.

**Files & exact changes:**
- `apps/autorun_flutter/lib/services/script_runner.dart`:
  - In `run()`, replace the inline loop (L440–478) with calls to `_executeCanisterCall(spec, resolveContext: 'pre-call ${spec.label}', emptyError: 'Empty response from ${spec.label}')`, collecting `result.result` into `callOutputs[spec.label]`. Note `_executeCanisterCall` returns raw-decoded values on non-JSON (matches current behavior L470–477).
  - **DELETE** L526–529 (redundant 'ui' branch).
  - Tighten the JSON-decode `catch (_) { return ScriptRunResult(ok: true, result: callOut); }` (L386–390 and L536) — see TD-3 (typed `catch (FormatException)`). Document that raw-string passthrough is intentional for non-JSON canister responses.

**Verification:**
```bash
cd apps/autorun_flutter && flutter analyze lib/services/script_runner.dart
cd apps/autorun_flutter && flutter test test/script_runner_test.dart test/features/scripts --timeout=180s
just test-feature scripts
```

**Estimated delta:** −~45 lines. Behavior-preserving (exercise TQ-3 first to lock the contract).

---

### TD-3 — Eradicate the forbidden `catch (_)` silent-failure pattern (40 sites)
**Complexity:** Medium (mechanical but wide) · **Dependencies:** TD-2 (script_runner sites handled there) · **Risk:** Medium

`AGENTS.md` explicitly forbids `try { ... } catch (_) { /* ignore */ }`. A workspace grep
finds **40 occurrences in `apps/autorun_flutter/lib`**. They fall into 3 classes:

| Class | Sites | Correct fix |
|-------|-------|-------------|
| **A. Silent swallow (real bug)** | `canister_history_service.dart:102`, `search_history_service.dart:33`, `native_bridge.dart:91,104` (mac/linux path probe), `bookmarks_screen.dart:1263` | These genuinely swallow errors. Either (a) `catch (e) { debugPrint('…: $e'); }` so failures are observable, or (b) catch the specific exception (`FormatException`, `ArgumentError`). For FFI path-probing (`native_bridge.dart`), `catch (e)` + `debugPrint` once per platform is acceptable — **but log it** so a missing `.so`/`.dll` is diagnosable. |
| **B. Intentional JSON-decode fallback** | `script_runner.dart:388,536` (handled in TD-2), `data_transformer.dart:29,43,86,116,128,145,217`, `result_display.dart:380`, `candid_args.dart:176`, `json_format.dart:10`, `candid_form_model.dart:50` | These return raw string when JSON parse fails. Convert to `catch (FormatException) { return raw; }` — semantically identical, no longer catches programming bugs silently. |
| **C. Platform/state tolerance** | `account.dart:100`, `marketplace_script.dart:88`, `profile.dart:73`, `script_repository.dart:52`, `canister_history_service.dart:91`, `passkey_service.dart:210`, `profile_repository.dart:60`, `script_integrity_service.dart:38`, `marketplace_open_api_service.dart:647,1042`, `bookmarks_screen.dart:1181`, `script_app_host.dart:203,300`, `script_editor.dart:162`, `candid_smart_form.dart:85,571,622`, `native_bridge.dart:71,78,111` | Case-by-case: most are "parse optional field, default on miss". Convert to `catch (e) { debugPrint('…: $e'); return default; }`. **`passkey_service.dart:210` is highest-risk** — swallowing a passkey error silently can hide an auth failure; convert to a logged re-throw or explicit typed catch. |

**Files & exact changes:**
- See table. **Do NOT batch-blindly** — each site needs the right typed catch or a log line. The executor must classify each of the 40 (the table above is the classification).
- **Split into two commits** if reviewable scope helps:
  - TD-3a: Class A + C (silent swallows) — each becomes logged or typed.
  - TD-3b: Class B (JSON fallback) — `catch (FormatException)`.
- Also sweep `crates/icp_core/src/canister_client.rs:122,123,125,127,602,687` `.ok()?` chains that discard the underlying `Err` — at minimum `map_err(|e| ...).ok()?` so the error is logged once before being dropped (or return `Result`).

**Verification:**
```bash
cd apps/autorun_flutter && flutter analyze
cd apps/autorun_flutter && flutter test --timeout=360s
rg -n "catch\s*\(\s*_\s*\)" apps/autorun_flutter/lib      # MUST return zero hits
just test
```

**Estimated delta:** ~+60 lines (log lines / typed catches), −0. Net: 0 silent-failure sites.

---

### TD-4 — Split `scripts_screen.dart` (2,702 lines) into focused widgets
**Complexity:** Complex · **Dependencies:** none (but do after TD-2/TD-3 to reduce churn) · **Risk:** High (navigation/touch surface) — **requires R-4 approval**

`apps/autorun_flutter/lib/screens/scripts_screen.dart` is 2,702 lines holding **6 independent
widget classes** + the main screen + 12 `_build*` methods. This is the single largest
maintainability debt in the app.

**Files & exact changes (extract, do not rewrite logic):**
1. **NEW** `apps/autorun_flutter/lib/widgets/script_editor_dialog.dart`
   ← extract `_ScriptEditorDialog` + `_ScriptEditorDialogState` (L1969–2156).
2. **NEW** `apps/autorun_flutter/lib/widgets/script_filter_sheet.dart`
   ← extract `_FilterBottomSheet` + `_FilterBottomSheetState` (L2157–2369), `_ActiveFilter` (L2370–2380), `_ActiveFilterChip` (L2381–2427).
3. **NEW** `apps/autorun_flutter/lib/widgets/script_context_menu.dart`
   ← extract `_ScriptContextMenuSheet` (L2428–2608), `_ContextMenuAction` (L2609–2671).
4. **NEW** `apps/autorun_flutter/lib/widgets/account_registration_prompt_dialog.dart`
   ← extract `_AccountRegistrationPromptDialog` (L2672–2702). (Or fold into the existing `account_registration_wizard.dart` flow — executor's call.)
5. **`scripts_screen.dart`**: shrink to `ScriptsScreen` + `ScriptsScreenState` + the view-builder helpers (`_buildUnifiedListView`, `_buildAllScriptsListItem`, `_buildLocalScriptMenu`, `_buildMarketplaceScriptMenu`, `_buildSourceIcon`, `_buildSearchBar` cluster, `_buildFavoriteStarButton`). Target ≤ ~1,400 lines. Move shared private state to package-private fields or a small `_ScriptsScreenController` value object only if a dialog truly needs it; otherwise pass `ScriptRecord`/`MarketplaceScript` params directly.
6. Update imports in `scripts_screen.dart`; update any test that references the moved classes by adding the new import.

**Rules for the executor:** pure *move* refactor — no logic changes, no renames beyond the
class-file alignment. Each extraction is one commit so a bisect is meaningful.

**Verification:**
```bash
cd apps/autorun_flutter && flutter analyze
cd apps/autorun_flutter && flutter test test/features/scripts test/screens --timeout=240s
just test-feature scripts
# Manual: launch on Linux desktop, open scripts screen, open filter sheet, long-press an item (context menu), tap edit (editor dialog) — all unchanged.
```

**Estimated delta:** 0 net lines; `scripts_screen.dart` 2,702 → ~1,400; 4 new focused files.

---

### TD-5 — Consolidate the two test-helper directories
**Complexity:** Medium · **Dependencies:** TQ-1, TQ-7 (helpers rationalized first) · **Risk:** Medium (many import sites)

There are **two** helper directories doing overlapping work:
- `apps/autorun_flutter/test/shared/` (the canonical one per `AGENTS.md` — `test_keypair_factory.dart`, `test_signature_utils.dart`, `fake_repositories.dart`-ish).
- `apps/autorun_flutter/test/test_helpers/` (20 files: `poem_script_repository.dart`, `poem_test_helper.dart`, `unified_test_builder.dart`, `mock_marketplace_service.dart`, `http_test_helper.dart`, `fake_passkey_authenticator.dart`, …).

The "poem" theme helpers were flagged in `CLEANUP_PLAN` R-8 as Lua-coupled; they survived the
sunset but their naming/fixtures must be **verified TS-correct** (no embedded Lua bundles).

**Files & exact changes:**
- **Audit** `test/test_helpers/poem_*.dart`: confirm fixtures are TS IIFE bundles (port to the `pilot-sample` bundle from `crates/icp_core/tests/fixtures/pilot_sample.bundle.js` if not). Rename `poem_*` → neutral names (`sample_script_repository.dart`) — the "poem" theme carries no domain meaning.
- **Consolidate** `test/test_helpers/` into `test/shared/`: move files, update the ~all test imports (`package:autorun_flutter/test/test_helpers/...` → `.../test/shared/...`). Keep `test/shared/AGENTS.md` as the index.
- **Delete** any helper imported nowhere (orphan check: `rg -l "<helper basename>"`).
- Update `AGENTS.md` Test Helpers table (L209–217) if helper locations change.

**Verification:**
```bash
cd apps/autorun_flutter && flutter analyze
cd apps/autorun_flutter && flutter test --timeout=360s
ls apps/autorun_flutter/test/test_helpers   # gone
```

**Estimated delta:** −~200 lines (deduped/orphaned helpers) + churn; one canonical helper dir.

---

### TD-6 — `backend/src/main.rs`: extract inline handler tests; document the handler map
**Complexity:** Complex · **Dependencies:** none · **Risk:** Medium · **Optional** (lower priority than TD-1..TD-4)

`backend/src/main.rs` is 2,088 lines: ~20 `#[handler]`s (L380–1018), helper fns, route
registration, AND a large inline `#[cfg(test)] mod tests` block with fixture seeding
(CLEANUP_PLAN WU-7 cites L1796–2088 for `bundle` fixture churn).

**Files & exact changes:**
- Move the inline `#[cfg(test)] mod tests` (the back ~300–400 lines) into `backend/tests/` integration tests where feasible (sqlx + test handlers). Where a test must live next to the handler, leave it but keep the module small.
- **Do NOT** split the 20 handlers into separate files unless R-4/R-5 expand scope — Poem apps conventionally keep handlers in `main.rs`. Instead add a one-page **route-map comment** at the top of `main.rs` listing handler → method+path → purpose, so the 2,088 lines are navigable.
- Resolve `main.rs:1547` `if reset_scripts.is_ok() && reset_reviews.is_ok()` — discards both errors. Convert to explicit `?`/`map_err` so a DB reset failure is loud.

**Verification:**
```bash
cd backend && cargo nextest run 2>&1 | tail -5     # still 88/88
cd backend && cargo clippy --all-targets -- -D warnings 2>&1 | tail -3
```

**Estimated delta:** −~300 lines moved to `backend/tests/`; `main.rs` 2,088 → ~1,750.

---

### TD-7 — `models.rs::SCRIPT_COLUMNS_WITH_ACCOUNT`: stop hand-maintaining SQL
**Complexity:** Medium · **Dependencies:** none · **Risk:** Low (deferred from CLEANUP_PLAN TD-7 / migration §11 TD-7)

`backend/src/models.rs:162` is a 25-column hand-typed SQL string that must be edited on
every `scripts` schema change (it already burned the WU-7 rename). It must stay byte-aligned
with `struct Script` (L5–33) and the DB schema (`db.rs`).

**Files & exact changes:**
- `backend/src/models.rs`: derive the column list from `Script` field names, or at minimum add a **compile-time test** that parses `SCRIPT_COLUMNS_WITH_ACCOUNT`, cross-checks it against `sqlx::query_as::<Script>` columns (via a `DESCRIBE scripts` round-trip in a test), and fails loudly on drift. Preferred: a `const` built from field-name tuples so there is one source of truth.

**Verification:**
```bash
cd backend && cargo nextest run script_columns   # new drift-guard test
cd backend && cargo nextest run                  # 88/88 + 1
```

**Estimated delta:** +~40 lines (guard) or −~5 net (derivation). Closes migration §11 TD-7.

---

### TQ-1 — Triage & drop low-signal / tautological tests (`test/features/scripts/`)
**Complexity:** Medium · **Dependencies:** FC-1 (dead test gone) · **Risk:** Low

`apps/autorun_flutter/test/features/scripts/` has **31 files** — many sub-widget-granular.
The executor must open each and classify DROP / KEEP / FOLD. Confirmed/strong DROP candidates
(signals to verify):

| File | Reason to DROP or FOLD |
|------|------------------------|
| `simplified_view_poc_test.dart` | "POC" tests are throwaway by intent; verify the simplified view is covered by `simplified_actions_test.dart` + `unified_view_test.dart`, then DROP. |
| `source_badge_test.dart` | Likely asserts a badge widget renders (framework-level). If it only checks `find.byType(SourceBadge)`, FOLD into `hybrid_view_test.dart` or DROP. |
| `favorite_star_icon_test.dart` | May duplicate `scripts_screen.dart`'s `_buildFavoriteStarButton` coverage and `favorites_filter_test.dart`. Keep ONE star test. |
| `filter_popover_test.dart` ↔ `active_filter_chips_test.dart` ↔ `favorites_filter_test.dart` ↔ `downloaded_filter_test.dart` | Four filter tests — FOLD into ≤2 (`filter_chips_test.dart` + `filter_logic_test.dart`) since they share the same filter-sheet setup. |
| `selection_hint_test.dart` ↔ `selection_mode_removal_test.dart` | Two facets of selection mode — likely FOLD into `selection_mode_test.dart`. |
| `scripts_view_machine_test.dart` | "View machine" suggests a state-machine test; verify it asserts app behavior (not just widget tree) before keeping. |

**Rules:** every DROP must cite the higher-signal test that already covers the behavior.
Never drop a test that is the sole coverage of a negative path.

**Files & exact changes:**
- Per-file: DELETE or MERGE. Update `test/features/scripts/` to a tight, high-signal set.

**Verification:**
```bash
cd apps/autorun_flutter && flutter test test/features/scripts --timeout=240s
# Coverage must not drop on script_runner / script_app_host / ui_v1_renderer
```

**Estimated delta:** −4..−7 files; −~300–500 lines; coverage signal density rises.

---

### TQ-2 — Decompose the 2,274-line `integration_with_mocks_test.dart`
**Complexity:** Medium · **Dependencies:** TD-5 (helpers consolidated) · **Risk:** Medium

`apps/autorun_flutter/test/integration_with_mocks_test.dart`: `void main()` is at **line
1234** — i.e. 1,233 lines of preamble (helper classes, fake builders, setup) precede a single
test entry point. It contains two groups: "Read → Transform → Display" (L1245) and
"Read → Transform → Call" (L1647).

**Files & exact changes:**
- Extract the 1,233-line preamble into `test/shared/` helpers (fakes/builders) — most belong with TD-5's consolidation.
- Split into **two** focused files matching the groups:
  - `test/features/scripts/integration_transform_display_test.dart`
  - `test/features/scripts/integration_transform_call_test.dart`
- DELETE the original monolith.

**Verification:**
```bash
cd apps/autorun_flutter && flutter test test/features/scripts/integration_transform_display_test.dart test/features/scripts/integration_transform_call_test.dart --timeout=240s
```

**Estimated delta:** 0 net lines; 1 monolith → 2 focused files + shared helpers.

---

### TQ-3 — ADD: TS bundle full lifecycle E2E (init/view/update/effects)
**Complexity:** Medium · **Dependencies:** TD-2 (contract locked) · **Risk:** Low

**No Dart E2E** exists for the TS app lifecycle — only Rust-side `crates/icp_core/tests/pilot_e2e.rs`. The `ScriptAppRuntime` (init/view/update) path through FFI is uncovered on the Dart side.

**Files & exact changes:**
- **NEW** `apps/autorun_flutter/test/features/scripts/ts_bundle_lifecycle_test.dart`:
  - Use the real `RustScriptBridge` against the `pilot_sample.bundle.js` fixture (copy from `crates/icp_core/tests/fixtures/pilot_sample.bundle.js` into a Dart test asset, or load via `rootBundle` in a test harness).
  - **Positive:** `init(arg)` → `{state, effects:[]}`; `view(state)` → a `ui_v1` tree; `update({type:'effect/result', ok:true, data:{...}}, state)` → new state with effect results merged; roundtrip returns to a stable `view`.
  - **Negative:** `init` with malformed bundle → `StateError('app init error: …')`; `update` returning `{ok:false}` → throws.
  - **Edge:** a bundle that emits an `icp_call` effect → host re-enters `update` with `{type:'effect/result', id, ok, data}` — assert the effect/result shape is what the host produces.

**Verification:**
```bash
cd apps/autorun_flutter && flutter test test/features/scripts/ts_bundle_lifecycle_test.dart --timeout=180s
```

**Estimated delta:** +~180 lines, +1 file, +~6 tests.

---

### TQ-4 — ADD: validation negative paths through `ScriptValidationService`
**Complexity:** Simple · **Dependencies:** none · **Risk:** Low

`crates/icp_core/tests/sandbox_adversarial.rs` covers `eval`/`Function`/`import`/`Intl.*`
rejection on the Rust side; the **Dart `ScriptValidationService` layer is uncovered** for
these (CLEANUP_PLAN §4 gap).

**Files & exact changes:**
- **NEW** `apps/autorun_flutter/test/features/scripts/ts_validation_negative_test.dart`:
  - Assert `eval("evil")`, `new Function("…")`, `import 'fs'`, `Intl.NumberFormat(...)` each yield `isValid: false` with a specific error string (via `validateJsComprehensive` over FFI). Use the real `NativeBridge` (not mocked crypto — but this is validation, not signing, so a real FFI call is the correct oracle).
  - Positive: the `pilot-sample` bundle validates `isValid: true`.
  - Use `TestKeypairFactory` only if signing is needed (it isn't for pure validation).

**Verification:**
```bash
cd apps/autorun_flutter && flutter test test/features/scripts/ts_validation_negative_test.dart --timeout=120s
```

**Estimated delta:** +~120 lines, +1 file, +~6 tests.

---

### TQ-5 — EXTEND: `native_bridge_js_smoke_test.dart` to cover all JS FFI symbols
**Complexity:** Simple · **Dependencies:** none · **Risk:** Low

`native_bridge_js_smoke_test.dart` only exercises `jsExec` (per CLEANUP_PLAN §4). The
`jsAppInit`/`jsAppView`/`jsAppUpdate`/`validateJsComprehensive`/`jsLint` symbols are
unverified at the Dart FFI boundary — an FFI mis-wire can reintroduce globals silently.

**Files & exact changes:**
- `apps/autorun_flutter/test/native_bridge_js_smoke_test.dart`: add smoke cases:
  - `jsAppInit` on the pilot bundle → JSON with `ok:true` + `state`.
  - `jsAppView` on the returned state → JSON with `ok:true` + a `view`/`result` node.
  - `jsAppUpdate` with a `{type:'effect/result',...}` msg → JSON with `ok:true` + new state.
  - `validateJsComprehensive` on a clean bundle → `is_valid:true`; on `eval("x")` → `is_valid:false`.
  - `jsLint` on a bundle → returns JSON (non-empty).

**Verification:**
```bash
cd apps/autorun_flutter && flutter test test/native_bridge_js_smoke_test.dart --timeout=120s
```

**Estimated delta:** +~100 lines, +5 tests.

---

### TQ-6 — ADD: marketplace round-trip with the `bundle` wire field
**Complexity:** Medium · **Dependencies:** none (post-WU-7; rename is done) · **Risk:** Low

No end-to-end test asserts the `bundle` key survives upload → GET → download → execute.

**Files & exact changes:**
- **NEW** or **EXTEND** `apps/autorun_flutter/test/integration/marketplace_bundle_roundtrip_test.dart`:
  - Spin up the dev API (`just api-dev-up` in CI / local), sign a TS bundle with `TestSignatureUtils.createTestScriptRequest`, POST `/api/v1/scripts`, GET `/api/v1/scripts/{id}`, fetch the `bundle`, execute via `ScriptRunner.run(ScriptRunPlan(bundle: …))`, assert a non-empty `ok:true` result.
  - Use `TestKeypairFactory.getEd25519Keypair()` (real keypair, real signing — never mock crypto).

**Verification:**
```bash
just api-dev-up && cd apps/autorun_flutter && flutter test test/integration/marketplace_bundle_roundtrip_test.dart --timeout=180s; just api-dev-down
```

**Estimated delta:** +~140 lines, +1 file, +~3 tests.

---

### TQ-7 — DRY: a single canonical TS-bundle test fixture + shared lifecycle helper
**Complexity:** Simple · **Dependencies:** TQ-3 (extracted) · **Risk:** Low

Multiple tests will need "a valid TS bundle" + "a running `ScriptAppRuntime`". DRY this
without overengineering.

**Files & exact changes:**
- **NEW** `apps/autorun_flutter/test/shared/ts_bundle_fixtures.dart`:
  - `const String kPilotBundle = '''…'''` (the pilot-sample IIFE, single source for Dart tests).
  - `ScriptAppRuntime bootRuntime()` → returns a `ScriptAppRuntime(RustScriptBridge(RustBridgeLoader()))` with the bundle already `init`-ed and its first `state`/`view` cached, so lifecycle tests share one boot.
- Replace ad-hoc bundle literals across `test/features/scripts/*` with `kPilotBundle`.

**Verification:**
```bash
cd apps/autorun_flutter && flutter test test/features/scripts --timeout=240s
```

**Estimated delta:** +~60 lines helper; −scattered duplicates.

---

### UX-1 — UX-review execution spec (swarm-run, not code review)
**Complexity:** Complex (swarm executes) · **Dependencies:** R-1 (target decision) · **Risk:** None (observational)

**Target:** Linux desktop (`flutter run -d linux`) — **NOT** Chrome. Flutter Web is unbuildable (R-1). Build first: `just linux`.

**The common operations the swarm must measure (clicks/actions each):**
1. **First-run onboarding → profile + account creation** — from cold launch to a usable profile. Count taps, screen transitions, text fields. Target: collapse to ≤ 3 screens.
2. **Browse marketplace → download → run a script** — the core loop. Target: ≤ 2 taps from app open to a running script's `view`.
3. **Author flow: new script → edit → validate → publish** — from scripts screen to a published bundle. The recent commits (`4d6002a`, `245d065`) already collapsed this; verify the collapse and find the next click.
4. **Run a script → interact with UI → trigger an action (`icp_call`)** — the `ui_v1` button → `performAction` round-trip. Target: ≤ 1 tap from rendered button to result.
5. **Profile / key management** — add a keypair, switch profile, set signing key. Target: ≤ 2 taps to switch the active profile.
6. **Passkey setup** — on Linux desktop `PasskeyPlatform.isSupported == false`; document this limitation in the report (don't try to test the flow on Linux).

**Deliverable the swarm must produce:** a `docs/specs/UX_REVIEW_FINDINGS.md` with, per flow:
(a) screenshots, (b) current action count, (c) concrete reduction proposal (screen merge / default-skip / inline), (d) proposed target count, (e) dev cost estimate. **No code** — proposals only.

**Friction heuristics to log:** any screen with > 1 redundant confirmation; any required field that could default; any 2-step flow that is really 1 step; dead-end/error states with no recovery path.

**Estimated delta:** +1 findings doc; drives future UX WUs (out of this plan's scope).

---

### PR-1 — Add CI (`.github/workflows/`) — none exists today
**Complexity:** Medium · **Dependencies:** R-3 (matrix decision) · **Risk:** Low

There is **no `.github/` directory**. Every gate (`just test`) is manual. This is the top
prod-readiness gap.

**Files & exact changes:**
- **NEW** `.github/workflows/ci.yml`:
  - Job `rust`: `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo nextest run` (fallback `cargo test` if nextest unavailable). Cache `~/.cargo` + `target` via `Swatinem/rust-cache`.
  - Job `sdk`: `npm ci`, `npm test` (vitest) in `packages/marketplace-sdk` + `packages/create-marketplace-script`; `npm run check:deps`.
  - Job `flutter`: `flutter pub get`, `flutter analyze`, `just linux` (build native lib first), `just api-dev-up`, `flutter test --concurrency=$(nproc) --timeout=360s`, `just api-dev-down`. (`just` must be installed on the runner.)
  - Runner: `ubuntu-latest` (Linux). **Do NOT add a `flutter build web` job** — it will fail (R-1); gate it behind R-1's resolution.
  - Trigger: `on: [push, pull_request]`.
- **NEW** `.github/workflows/deploy.yml` (optional, gated on R-deploy decision): docker build + push on tag.

**Verification:**
```bash
# After merge, confirm a green run on the default branch.
act -j rust 2>&1 | tail   # optional local dry-run via `act`
```

**Estimated delta:** +~120 lines YAML.

---

### PR-2 — Fix the prod passkey RP configuration bug
**Complexity:** Simple · **Dependencies:** none · **Risk:** High if unaddressed (passkeys silently broken in prod)

`backend/src/main.rs:1613–1615` defaults `WEBAUTHN_RP_ID` to `localhost` and
`WEBAUTHN_RP_ORIGIN` to `http://localhost:58000`. **`backend/docker-compose.prod.yml` passes
NEITHER** — so in prod, passkeys are registered/authenticated against RP `localhost`, which
will not validate against the public hostname `icp-mp.kalaj.org`. Result: passkey login works
in dev and silently fails in prod.

**Files & exact changes:**
- `backend/docker-compose.prod.yml`: add to `api-prod.environment`:
  ```yaml
  - WEBAUTHN_RP_ID=${WEBAUTHN_RP_ID:-icp-mp.kalaj.org}
  - WEBAUTHN_RP_ORIGIN=${WEBAUTHN_RP_ORIGIN:-https://icp-mp.kalaj.org}
  ```
- `backend/.env.example` + `backend/PROD_DEPLOYMENT.md`: document both vars as **required for prod** with the correct values. Add a **diagnostic check**: on boot, if `ENVIRONMENT=production` and `WEBAUTHN_RP_ID` resolves to `localhost`, log a **LOUD warning** (AGENTS.md: be loud about misconfigurations) — implement in `main.rs` near L1613.
- Add a backend test asserting the warning fires under `(production, localhost)`.

**Verification:**
```bash
cd backend && cargo nextest run webauthn   # new warning test
WEBAUTHN_RP_ID=localhost ENVIRONMENT=production cargo run &   # logs the loud warning
```

**Estimated delta:** +~30 lines. Closes a silent-prod-failure.

---

### PR-3 — Validate the deployment path + update `PROD_DEPLOYMENT.md`
**Complexity:** Medium · **Dependencies:** PR-2 · **Risk:** Low

`backend/PROD_DEPLOYMENT.md` is Cloudflare-tunnel-focused and pre-dates the TS runtime. Verify
the deploy actually works with the TS-only backend and document a runbook.

**Files & exact changes:**
- `backend/PROD_DEPLOYMENT.md`:
  - **Dry-run the path** (`cargo build --release` → `docker build` → `docker compose -f docker-compose.prod.yml --env-file .env.tunnel up -d`) and fix anything that breaks.
  - **Reconcile the port story**: `docker-compose.prod.yml` maps `58100:58000` (host:container); `PROD_DEPLOYMENT.md` says `icp-mp.kalaj.org → api:58000`. Confirm cloudflared reaches `api-prod:58000` over the `api-network-prod` bridge (it does). Document the host port 58100 is for direct/debug access only.
  - Add the WEBAUTHN vars (PR-2) and `RUST_LOG` to the env table.
  - Drop any implication of a second runtime; note the backend serves TS bundles only.
- **NEW** `backend/DEPLOY_RUNBOOK.md` (or a section in PROD_DEPLOYMENT.md): a checklist —
  build → docker build → compose up → `curl health` → seed is empty? → upload one signed TS bundle (sample `curl` with a real signature) → GET it back → confirm `bundle` key → smoke-execute. Include the rollback (`docker compose down` + re-run previous image).

**Verification:**
```bash
cd backend && cargo build --release
cd backend && docker build -f Dockerfile -t icp-marketplace-api:prod ..
cd backend && docker compose -f docker-compose.prod.yml --env-file .env.tunnel up -d
curl -s http://127.0.0.1:58100/api/v1/health        # {"status":"ok"}
```

**Estimated delta:** +~120 lines docs.

---

### PR-4 — Decide & document R-1 (Flutter Web support)
**Complexity:** Simple (decision + doc, not code) · **Dependencies:** none · **Risk:** None

Per `TODO.md` F-0, `lib/main.dart:11` + `lib/rust/native_bridge.dart:2` import `dart:ffi`
unconditionally, so `flutter build web` cannot compile. The fix (conditional `*_io.dart` /
`*_web.dart` split + a WASM QuickJS + WebCrypto key/sign strategy) is a **large, separate
initiative** and is **out of scope** for prod-readiness unless R-1 resolves "Web is supported".

**Files & exact changes:**
- `TODO.md`: sharpen the F-0 entry with the explicit decision options (drop Web / defer / fix-now) and the consequence for passkey testing (it currently routes through Web per `AGENTS.md`).
- `AGENTS.md` "Passkey Testing on Linux" (FC-3) — align with the decision.
- If **Web is dropped**: add a `docs/BROWSER_SUPPORT.md` stating desktop+Android are the supported targets; remove the `-d chrome` recipe from the justfile (`flutter-dev-local`, justfile:387–393) to stop advertising a broken path.
- If **Web is deferred**: leave the code as-is; ensure CI (PR-1) does not run a web build.

**Verification:**
```bash
# Decision recorded in TODO.md + AGENTS.md; no broken recipes advertised.
```

**Estimated delta:** ~±40 lines docs.

---

### PR-5 — End-to-end prod smoke (validation gate, not a code WU)
**Complexity:** Medium · **Dependencies:** PR-2, PR-3 · **Risk:** Low

The cumulative verification that the TS runtime is prod-shippable. Not a separate code
change — it is the **acceptance test** for this whole plan, executed on a clean checkout.

**Steps (record pass/fail in `docs/specs/PROD_READINESS_PLAN.md` §5 once done):**
1. `cargo nextest run` (workspace) — all green.
2. `cd packages/marketplace-sdk && npm test` — 90/90.
3. `just linux` builds; `flutter analyze` clean; `flutter test` green.
4. Linux desktop: launch, complete onboarding, create a profile, register an account, **author a TS bundle, validate it, publish it, download it, execute it, trigger an action** — full loop.
5. `just api-dev-up`; `curl` upload a signed bundle; GET it; verify `bundle` key; download-execute via the app.
6. Docker prod path (PR-3) dry-run green, including the WEBAUTHN warning when misconfigured (PR-2).

**Estimated delta:** 0; produces the §5 acceptance checklist (filled in).

---

## Section 3 — Risk Register

### Items requiring a HUMAN decision (do NOT auto-resolve)

| ID | Item | Severity | Why a human must decide | Default if no answer |
|----|------|----------|-------------------------|----------------------|
| **R-1** | **Is Flutter Web a supported target?** Web is unbuildable (`dart:ffi` unconditional import at `lib/main.dart:11`, `native_bridge.dart:2`). Fixing it = conditional-import split + WASM QuickJS + WebCrypto (a large initiative). Passkey testing routes through Web per `AGENTS.md`. | **HIGH** | It determines (a) whether UX-1 can use Chrome, (b) whether CI (PR-1) needs a web job, (c) whether passkey testing is even reachable, (d) PR-4's outcome. | **Defer Web**; ship desktop+Android only; remove the `-d chrome` recipe; document in `docs/BROWSER_SUPPORT.md`. UX-1 uses Linux desktop. |
| **R-2** | **Cross-profile key-sharing model violation** (`lib/models/account.dart:18,304`). The Flutter models allow a keypair to be associated across accounts/profiles, violating the profile-centric rule ("a keypair belongs to exactly ONE profile"). The backend enforces key uniqueness, so the client is the loose end. | **MEDIUM** | Architectural — affects the data model and every key-management screen. Could be a real bug or a documented edge case. | **Document and defer** to a follow-up; add a `TODO.md` entry under "Architectural Issues Requiring Review" but do NOT ship a half-fix. |
| **R-3** | **CI runner matrix** — Linux-only, or include macOS/Windows desktop + Android? | **MEDIUM** | Affects PR-1 cost and whether the FFI symbols are cross-compiled per OS. Android NDK cross-compile of the QuickJS cdylib is itself an open question (migration §11 G2 — "NDK not present in current environment"). | **Linux-only CI** for Rust+SDK+Flutter(host); Android/macOS/Windows are out-of-band until NDK G2 is resolved. |
| **R-4** | **`scripts_screen.dart` 2,702-line split (TD-4)** approved? High-touch refactor of the most-used screen. | **LOW–MEDIUM** | Pure refactor risk; no behavior change intended but large diff. | **Proceed** — it's a move-only refactor with strong test coverage gating it (`just test-feature scripts`). |
| **R-5** | **Backend `main.rs` handler split (TD-6)** — expand scope to split the 20 handlers into route modules, or keep them in `main.rs` (Poem convention) and only extract tests? | **LOW** | Style call; affects TD-6 size. | **Keep handlers in `main.rs`** (Poem convention); only extract the inline test module + add the route-map comment. |
| **R-6** | **Test-data string `'lua script'`** in `search_history_test.dart` — keep as legitimate user input, or rename for narrative consistency? | **TRIVIAL** | Cosmetic. | **Keep** — a user *could* type "lua script". |

### Execution risks (technical, the executor mitigates)

| ID | Risk | Detection | Mitigation |
|----|------|-----------|------------|
| **X-1** | TD-1/TD-4 refactors silently change behavior (FFI signatures / navigation). | FFI smoke (TQ-5), `just test-feature scripts`. | Land TQ-3/TQ-5 **before** TD-2/TD-4 so the contract is locked. |
| **X-2** | TD-3 typed-catch conversion introduces a regression where a previously-swallowed error now surfaces (correct, but may break a test that relied on the swallow). | `flutter test` red. | Each TD-3 site is one focused commit; fix the dependent test in the same commit. |
| **X-3** | TD-5 helper-dir merge breaks dozens of imports. | `flutter analyze` red. | Mechanical relpath tool (`dart fix` / `sed`); one big commit for the move. |
| **X-4** | TQ-1 drops a test that was sole coverage of a negative path. | Coverage regression. | Each DROP cites its covering test; require positive+negative coverage audit per feature. |
| **X-5** | PR-1 CI flake (Flutter `flutter test` timing). | Red CI on green code. | Use `--timeout=360s` + `--concurrency=$(nproc)` (already in justfile:143); retry once. |
| **X-6** | UX-1 swarm tries to use Chrome and wastes a cycle (Web is broken). | Swarm blocks. | UX-1 spec explicitly mandates `flutter run -d linux`; R-1 decision first. |

---

## Section 4 — Sequencing Recommendation

### Dependency graph

```
R-1 decision ─────────────────────────────┐  (gates UX-1 target, PR-1 web job, PR-4)
                                          │
FC-1 (drop dead test) ─┐                  │
FC-2 (rename cosmetics)┼── FC-3 (doc sweep)│
                       │                  │
TQ-3 (lifecycle E2E) ──┼── TD-2 (dedupe run) ── TD-3 (catch (_) purge)
TQ-5 (FFI smoke) ──────┘                  │
                                          │
TD-1 (ffi.rs DRY)  ─────────── independent│
TD-7 (SQL columns) ─────────── independent│
TD-6 (main.rs) ──── optional, low priority│
                                          │
TQ-1 (drop low-signal) ── TQ-7 (fixture DRY) ── TD-5 (helper-dir merge) ── TQ-2 (split monolith)
TQ-4 (validation neg)  ─── independent     │
TQ-6 (marketplace RT)  ─── independent     │
                                          │
TD-4 (split scripts_screen) ── after TD-2/TD-3 (rely on R-4)
                                          │
PR-2 (passkey RP bug) ──── PR-3 (deploy doc + runbook) ─── PR-5 (e2e smoke)
PR-1 (CI) ──── after R-3; gates nothing but blocks merge-to-main confidence
PR-4 (Web decision doc) ─── after R-1
                                          │
UX-1 (swarm) ─── after R-1; produces findings, drives future UX work (out of plan)
```

### Parallelization for a subagent swarm

The WUs partition into **5 nearly-independent tracks** that can run in parallel, with TD-2/TQ-3/TQ-5 as the one serialized island:

- **Track A — Final Cleanup (FC-1 → FC-2 → FC-3):** one agent, sequential, ~half a day. Low risk, fast.
- **Track B — Runtime correctness island (TQ-5, TQ-3 → TD-2 → TD-3a/b):** one agent, sequential. **This is the critical path** — lock the contract with tests, then dedupe, then purge `catch (_)`. TD-3 touches 40 files; keep it last in this track.
- **Track C — Rust backend hygiene (TD-1, TD-7, optional TD-6):** one agent, fully parallel with B. Pure Rust; `cargo nextest` is the gate.
- **Track D — Test rebalance (TQ-1, TQ-4, TQ-6 parallel → TQ-7 → TD-5 → TQ-2):** one agent. TQ-1/4/6 are independent; TD-5 (helper merge) and TQ-2 (monolith split) must follow TQ-7.
- **Track E — Refactor big files (TD-4):** one agent, **after Track B** (so the runtime contract is locked). Single focused effort.
- **Track F — Prod (PR-2 → PR-3 → PR-5; PR-1 and PR-4 independent):** one agent. PR-2 is a real bug fix — ship it early. PR-1 (CI) unblocks everything else's confidence.

**UX-1** is a separate observational swarm that runs **after R-1 is decided** and consumes the
Linux desktop build; it produces `docs/specs/UX_REVIEW_FINDINGS.md` and does not block any WU.

### Recommended commit cadence
- One commit per WU (or per WU-half for TD-3 and TD-4). Message convention (matches repo history): `refactor(<area>): <WU-id> <title>`, `test(<area>): <TQ-id> <title>`, `chore(<area>): <FC-id> <title>`, `ci: <PR-id> <title>`, `docs: <WU-id> <title>`.
- Each commit must leave `just test-feature <affected>` green (or the relevant `cargo nextest`/`npm test` subset).
- **Do not** land TD-2, TD-3, TD-4, or TD-5 without their gating tests (TQ-3/5 for TD-2; the dependent tests fixed in-commit for TD-3; `just test-feature scripts` for TD-4/5).

### Definition of Done for this plan
All Section-1 success-criteria checkboxes ticked · all R-1..R-6 decisions recorded ·
`grep -rin "lua\|catch (_)\|lua_source\|luaSource" apps/autorun_flutter/lib crates/ backend/src packages/*/src`
returns **zero unintentional hits** · CI green on default branch · PR-5 acceptance checklist filled.

---

## Section 5 — Acceptance Checklist (fill in on PR-5 completion)

| Check | Command / Action | Pass |
|-------|------------------|------|
| Rust workspace tests | `cargo nextest run` | ☐ |
| Rust lint | `cargo clippy --workspace --all-targets -- -D warnings` | ☐ |
| SDK tests | `cd packages/marketplace-sdk && npm test` | ☐ |
| Scaffold tests | `cd packages/create-marketplace-script && npm test` | ☐ |
| Flutter analyze | `cd apps/autorun_flutter && flutter analyze` | ☐ |
| Flutter tests | `just flutter-tests` | ☐ |
| No `catch (_)` in lib | `rg -n "catch\s*\(\s*_\s*\)" apps/autorun_flutter/lib` → 0 | ☐ |
| No stray `lua` in prod code | `rg -rin "lua" apps/autorun_flutter/lib crates/ backend/src packages/*/src` → only legit | ☐ |
| TS bundle full loop on Linux desktop | author → validate → publish → download → execute → action | ☐ |
| CI green | `.github/workflows/ci.yml` run on main | ☐ |
| Prod passkey RP | `WEBAUTHN_RP_ID` set to public host in prod compose | ☐ |
| Deploy dry-run | docker build + compose up + curl health + upload/download/exec | ☐ |
| R-1..R-6 decided | each recorded in TODO.md / docs | ☐ |
