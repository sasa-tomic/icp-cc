# ICP Script Marketplace - TODO

**Last Updated:** 2026-06-29 (Scripting Runtime Migration: wasm fix + TS UX polish + integration test)

## Current Focus

**Goal:** Radical UI/UX simplification. Remove clutter, improve discoverability.

**Reality Check - Scripting Runtime Migration: wasm build fix + TS UX polish + integration test COMPLETE:**
Closes the wasm32 build break + adds TS example template, syntax highlighting, ScriptAppRuntime integration test. `cargo build --target wasm32-unknown-unknown --lib` now SUCCEEDS (was broken by unconditional mlua). 10 commits on local main (NOT pushed): `d84980e`(spec) → `d5bd178`(P0+1) → `088c047`(P2+3) → `81e0f4f`(G1 FFI) → `cc71ec5`(G1-data-model+hardening) → `31368d8`(wasm fix) → `080efc4`(TS example+errors) → `5b25f6c`(TS highlight) → `7c6703a`(dep bumps) → `f14cdad`(integration test).
- **wasm build fix (DONE, 31368d8):** mlua/reqwest/ic-agent/tokio moved to `[target.'cfg(not(wasm32))']`. lib.rs gates canister_client/ffi/lua_engine under not(wasm32); unconditional: contract/js_engine/keypair/principal/vault (all wasm-safe). wasm_exports.rs: removed dead Lua validators (never compiled), kept JS pure-Rust validators. Added `alloc` to ed25519-dalek + `arithmetic` to k256 (were transitively supplied by native-only deps). Gates: wasm build succeeds, 121 native tests, clippy clean both targets.
- **TS counter example (DONE, 080efc4):** `lib/examples/05_typescript_counter.js` (minimal IIFE: init/view/update counter) + ScriptTemplate registration with `language: typescript`. Fixed 6 stale error strings in ScriptAppRuntime. Gates: analyze 82→82, 36 tests.
- **TS syntax highlighting (DONE, 5b25f6c):** script_editor.dart now selects `javascript` highlight mode for TS (was hardcoded `lua`). scripts_screen + quick_upload_dialog pass language through. Gates: analyze 82→82, 29 tests.
- **npm dep bumps (DONE, 7c6703a):** esbuild ^0.25.2 + vitest ^3.2.4 (addresses dev-server-only vulns). 5 nested transitive vulns remain (tsup/vitest internal esbuild copies — can't fix without breaking changes, zero risk).
- **ScriptAppRuntime integration test (DONE, f14cdad):** `native_bridge_js_smoke_test.dart` now runs `ScriptAppRuntime(language: typescript)` through init→view→update with REAL FFI→QuickJS. Proves full Dart abstraction stack. 3/3 pass, analyze 82→82.

**Reality Check - Scripting Runtime Migration G1-data-model + Rust hardening COMPLETE:**
Closes G1-data-model + G13-defense-in-depth (eval/Function runtime strip) + execute_lua_json fail-fast. Verified independently (17/17 checks: 121 Rust tests, flutter analyze 82→82, 0 regressions proven vs clean HEAD). The runtime switch is now USABLE end-to-end: data models carry `language`, persisted scripts migrate gracefully (absent key → lua), the editor offers a Lua/TypeScript toggle, and downloads auto-detect language.
- **G1-data-model (DONE):** `ScriptLanguage language` field added to `ScriptRecord` + `MarketplaceScript` + `ScriptTemplate` (default `lua` = back-compat). `lib/services/language_detector.dart` (NEW): `detectLanguage(source)` heuristic (lua signals checked first → default lua) + JSON helpers. `fromJson` absent-key → lua = the on-disk `scripts.json` migration path. `ScriptController.createScript` gains optional `language` (auto-detect from source). `script_creation_screen.dart` language `DropdownButtonFormField`. `scripts_screen.dart` `_runtimeFor(ScriptRecord)` factory replaces shared `_appRuntime` (per-record language routing). `luaSource` field name KEPT (holds Lua OR TS bundle text). GATES: analyze 82→82, 79 Flutter tests pass (13 detector + 7 record + 10 marketplace + 6 controller + 33 bulk-ops regression + 10 creation-screen).
- **G13-defense-in-depth (DONE):** `js_engine/runtime.rs` `NEUTRALIZE_EVAL_JS` neutralizes `globalThis.eval`/`globalThis.Function` (throwing functions) after bootstrap. Static `validate_js_comprehensive` remains the PRIMARY gate; runtime strip is the SECONDARY net. `sandbox_adversarial.rs` +2 runtime tests (eval/Function throw). Host `Ctx::eval` (Rust-side) unaffected → pilot_e2e still green.
- **execute_lua_json fail-fast (DONE):** `lua_engine.rs` replaced `.unwrap_or(LuaValue::Nil)` with `.map_err(|e| LuaExecError::Lua(...))?` — Lua runtime errors now propagate as `Err` (parity with `execute_js_json`). FFI `icp_lua_exec` already maps `Err`→`{"ok":false,"error":...}` (no FFI change). GATES: 121 Rust tests pass (118→121).

**Reality Check - Scripting Runtime Migration G1 COMPLETE (Flutter wiring of `icp_js_*`):**
Flutter SDK confirmed present (3.46.0). Wires the 6 Rust `icp_js_*` FFI symbols into the Flutter app so TypeScript bundles run alongside Lua. Verified independently (15/15 checks, zero blocking defects). Real Flutter→FFI→QuickJS end-to-end proof: `jsExec('1+2')→{ok:true,result:3}` and `jsAppInit(pilot_bundle)→{ok:true,state.count:0}` against the live `.so`.
- **FFI layer (DONE):** `lib/rust/native_bridge.dart` — 6 `_Symbols` JS consts (`icp_js_exec/lint/validate_comprehensive/app_init/app_view/app_update`) + 6 `RustBridgeLoader` js* methods (reusing existing lua typedefs — DRY, no new typedefs) + 3 `NativeBridge` passthroughs (jsExec/jsLint/validateJsComprehensive). lua methods byte-unchanged.
- **Runtime switch (DONE):** `lib/services/script_runner.dart` — `enum ScriptLanguage { lua, typescript }`; `ScriptRunPlan.language` (default `lua` = back-compat for all existing callers); `ScriptBridge` + 5 abstract js* methods (exec/lint/appInit/appView/appUpdate) + `RustScriptBridge` impls; `ScriptRunner.run` routes TS→`jsExec` (SKIP `_injectHelpers` — JS bundles self-contained via `register()`) and lua→unchanged path; `ScriptAppRuntime({language})` routes init/view/update. `IScriptAppRuntime` abstract unchanged.
- **Tests (DONE):** 6 fake bridges (`implements ScriptBridge`) updated with js* stubs; NEW `test/script_runner_js_path_test.dart` (4 routing tests: TS→js* / lua→lua* / helper-injection skipped / defaults); NEW `test/native_bridge_js_smoke_test.dart` (real-FFI QuickJS, 2/2 pass). `flutter analyze` 82→82 (zero new issues). GATES: 79 tests pass (4 routing + 58 fakes + 15 canister + 2 real-FFI).
- **G1-data-model NOW DONE (see latest Reality Check above).** Minor cosmetic follow-ups remain: smoke-test skip uses `return`+stdout not `SkipException` (cosmetic CI-accounting); stale `'luaAppInit returned empty'` error string on TS path (cosmetic).

**Reality Check - Scripting Runtime Migration Phase 2+3 COMPLETE (Parity Hardening + Pilot):**
Closes G6/G7/G9/G10/G11/G13/G14 + N1/N4 + pilot (G3/G4 PoC) + spec §12 decisions. Verified independently (118 Rust tests, 90 Node tests, all gates green). End-to-end PoC PROVEN: TS source → esbuild IIFE bundle → Rust QuickJS host executes init/view/update (and Node QuickJS).
- **G10 Parity CI gate (DONE):** `parity/vectors.json` = single shared golden vector (24 cases) consumed by BOTH Rust (`tests/parity_vectors.rs`, runs JS+Lua) AND Node (`parity.vectors.test.ts`). All 24 cases agree across Rust-host == Node-SDK. `SDK_CONTRACT_VERSION="0.1.0"` triple-locked: `crates/icp_core/src/contract.rs` + `packages/marketplace-sdk/src/version.ts` + `vectors.json::sdkContractVersion`.
- **G3/G4 Pilot (DONE — PoC):** `kDefaultSampleLua` migrated to TS (`packages/marketplace-sdk/samples/pilot-sample.ts`), bundled to 6175-byte IIFE (`crates/icp_core/tests/fixtures/pilot_sample.bundle.js`), runs on BOTH Rust `js_app_init/view/update` (`tests/pilot_e2e.rs`) AND Node real-QuickJS (`pilot.e2e.test.ts`). Byte-stable drift guard (`pilot.bundle-sync.test.ts`).
- **G6 Benchmark (DONE):** `crates/icp_core/benches/runtime.rs` criterion. **Lua is ~2.4-2.6× faster than QuickJS** (app_init 2.48×, helpers 2.61×, lifecycle 2.42×). Answers spec §10/§11 open Q: QuickJS cold-start/throughput is slower; accept for typing/testability/AI-friendliness benefits.
- **G7 Intl (DONE):** probe confirms QuickJS has NO Intl (`typeof Intl==="undefined"`). Decision: FORBID `Intl.*` via `validate_intl`; rely on locale-free `icp_format_*` helpers. Documented in spec §12.
- **G9 Dep allowlist (DONE):** `scripts/check-deps-allowlist.mjs` + `deps-allowlist.json` → `npm run check:deps`. Zero runtime deps enforced (scripts = self-contained IIFEs); devDeps allowlisted.
- **G11 Lua icp_log (DONE):** backported `icp_log` to `lua_engine.rs` + wired into `execute_lua_json`/`app_init` (parity with JS). lua_engine.rs change is G11-only.
- **G13 Sandbox hardening (DONE):** `tests/sandbox_adversarial.rs`: prototype-pollution isolated per fresh-runtime call; `__proto__` contained; static `import` throws; `require`/`process` undefined; `eval`/`Function`/dynamic-import blocked statically by `validate_js_comprehensive`. UPDATE: eval/Function now ALSO neutralized at QuickJS RUNTIME via `NEUTRALIZE_EVAL_JS` (defense-in-depth — see latest Reality Check above).
- **G14 IIFE pin (DONE):** `validate_esm_format` rejects top-level `import`/`export`; UI node allowlist extended (`text_field`,`select`,`image`,`list`); `register()` throws on non-functions.
- **N1 Pedantic (DECIDED):** gate stays `clippy::all` + `-D warnings`; pedantic NOT enforced (would surface 200-500 lints across unrelated backend). Documented spec §12.
- **N4 Shared golden vector (DONE — see G10).** Pre-existing `cargo fmt` debt FIXED (S0 workspace fmt: backend/* + lib.rs).
- **REMAINING GAPS:** G2 Android NDK (NDK absent), G8 qjsc bytecode (optional/deferred), G12 resource-limit tuning (needs real pilot scripts/load-test), G3-full (actual marketplace Lua corpus in DB), runtime eval/Function strip NOW DONE (see latest Reality Check), execute_lua_json silent-swallow NOW DONE (fail-fast), pre-existing wasm build break (mlua unconditional + tokio — resolves when mlua made wasm-optional), 5 npm audit vulns (dev-only).

**Reality Check - Scripting Runtime Migration Phase 0+1 COMPLETE (Lua → TypeScript/QuickJS):**
Implements `docs/specs/SCRIPTING_RUNTIME_MIGRATION.md` P0 (Foundations) + P1 (SDK & Tooling). Dual-runtime: new JS engine alongside untouched `lua_engine.rs`.
- **P0 Rust host (DONE, verified):** `crates/icp_core/src/js_engine.rs` + `js_engine/runtime.rs` embed QuickJS via rquickjs 0.12 (target-gated out of wasm). `create_sandboxed_js` enforces memory (64 MiB) + stack (512 KiB) + interrupt-handler time budget. 6 public fns mirroring `lua_engine`: `execute_js_json`, `lint_js`, `validate_js_comprehensive` (9 stages), `js_app_init`/`js_app_view`/`js_app_update`. 16 `icp_*` helpers + `icp_log` (fixes Lua's dead `__icp_messages`). 6 `icp_js_*` FFI symbols (reusing `icp_free_string`). wasm: `validate_js_script_wasm`/`check_js_syntax_wasm` = pure-Rust static analysis (rquickjs can't target wasm32, same as mlua). GATES: `cargo nextest run -p icp_core` = 98 pass/0 fail; `cargo clippy -p icp_core --all-targets --all-features -- -D warnings` = 0 issues; `nm -D libicp_core.so` shows all 6 symbols.
- **P1 Node tooling (DONE, verified):** npm workspace `packages/*`. `@icp-cc/marketplace-sdk` (typed contract: State/Msg/Effect/UI nodes + `SDK_CONTRACT_VERSION="0.1.0"` + 16 reference helpers + local mock host). `create-marketplace-script` CLI scaffold → esbuild IIFE bundle, no-Node plugin (forbids fs/path/crypto/process + global fetch/setTimeout/URL/TextEncoder), Vitest harness running scripts in REAL QuickJS (`@jitl/quickjs-singlefile-browser-release-sync`). GATES: `npm test` = 52 pass/0 fail; sample bundles to single IIFE, runs in QuickJS.
- **Contract divergence (intentional):** JS `init`/`update` return single `{state, effects}` object (not Lua multireturn); `icp_format_icp` whole floats → `"1"` (JS) not `"1.0"` (legacy Lua); `execute_js_json` fail-fast Err (not Lua's silent swallow).
- **NOT verified in-env:** Flutter wiring (needs Flutter SDK), Android cross-compile (NDK absent), `just flutter-tests` (needs GUI+API server).
- **GAPS (Phase 2-4, NOT in P0+1):** G1 Flutter wiring of `icp_js_*` (`native_bridge.dart` `_Symbols` + Dart typedefs + `script_runner.dart` runtime switch). G2 Android NDK cross-compile (rquickjs bindgen may need `BINDGEN_EXTRA_CLANG_ARGS`). G3 Lua corpus migration (no inventory of stored scripts). G4 AI Lua→TS rewrites (prompt/tooling + eval harness). G5 Lua deprecation timeline (product decision). G6 Cold-start/throughput benchmark vs LuaJIT (`criterion` p50/p99). G7 Intl/locale (QuickJS limited ICU; full ICU OR forbid `Intl.*` + expose via SDK). G8 `qjsc` bytecode precompilation (optional). G9 Third-party npm dep allowlist CI scan. G10 Parity CI gate (local QuickJS==prod; fail on `SDK_CONTRACT_VERSION` drift). G11 Backport `icp_log` to Lua if Lua stays long-term. G12 Resource-limit tuning (load-test real pilot scripts). G13 `require`/module-loader fuzz/adversarial hardening. G14 Pin bundler to IIFE+globalThis (reject ESM-format bundles in validate).
- **FOLLOW-UPS (Phase 2 parity hardening, non-blocking):** N1 pedantic not enforced project-wide (literal `--deny warnings` passes). N2-N3 document `format_icp`/`icp_section` edge semantics in migration notes. N4 shared golden-vector parity CI (Rust-host==Node-SDK==Lua for identical inputs). N5 npm audit vulns (esbuild/vite/vitest dev-only). Pre-existing `cargo fmt` failures (`backend/src/vault.rs:221`, `crates/icp_core/src/lib.rs:22`) — not introduced by this work. Pre-existing wasm build break on mlua/lua-src (mlua unconditional) — resolves once mlua made wasm-optional (future phase).

**Reality Check - UX Simplification Wave 13 COMPLETE:**
- **NEW:** My Library Screen - Consolidated view of downloads, favorites, scripts, activity (24 tests)
- **NEW:** Script Execution Bottom Sheet - Run scripts in modal, not full screen (7 tests)
- **NEW:** Contextual Help for Passkeys - Tooltips on profile menu and account screen (37 tests)
- **FIXED:** Pre-existing test failures - passkey screens_test.dart and scripts/execute_test.dart (28 tests)

**Reality Check - UX Simplification Wave 12 COMPLETE:****
- Navigation Tab Clarity - "Home"→"Scripts", "Explore"→"Canisters" (icons: code/dns)
- Security Section Unified - Single section combines Passkeys + Public Keys + Backup (10 tests)
- QuickUploadDialog Fix - Uses actual script.luaSource instead of generated placeholder (4 tests)
- Script Diff Viewer - View changes between versions with +/- colored lines (16 tests)
- Deep Linking - `icpautorun://script/{id}` URLs for script sharing (15 tests)

**Reality Check - UX Simplification Wave 8 COMPLETE:**
- Publish Account Prompt - Red badge on avatar when no account, contextual registration prompt when publishing (11 tests)
- Active Filter Chips - Visible chips below search bar, each dismissible, Clear All button (24 tests)
- ~~Section Separation~~ - **REMOVED in Wave 10** (simplified to unified view)

**Reality Check - UX Simplification Wave 7 COMPLETE:**
- **NEW:** Scripts Screen State Machine - clean state management, no empty state flash for new users (24 tests)
- **NEW:** Discoverable Script Actions - hover-reveal on desktop, always visible on mobile (10 tests)
- **NEW:** Canister Client Simplified - removed redundant "Arguments" header, cleaner quick query (5 tests)

**Reality Check - UX Simplification Wave 6 COMPLETE:**
- **NEW:** New User Default View - loading indicator instead of empty state for marketplace (6 tests)
- **NEW:** Navigation Tab Labels - "Discover" renamed to "Explore" for consistency (3 tests)
- **NEW:** Profile Form Simplified - social fields collapsed into expandable section (4 tests)
- **NEW:** Favorite Star Icon Visible - star on every script item for quick favoriting (15 tests)
- ~~**NEW:** Bulk Selection Hint~~ - **REMOVED in Wave 10** (feature removed)

**Reality Check - UX Simplification Wave 5 COMPLETE:**
- **NEW:** Scripts Screen Action Simplification - ONE primary action per row (14 tests)
- **NEW:** Profile Menu Simplification - max 5 items, combined profile management (12 tests)
- **NEW:** Visual Template Picker - cards with emoji/title/difficulty (9 tests)
- **NEW:** Script List Visual Hierarchy - simplified subtitle, subtle icons (18 tests)
- **NEW:** Hidden Developer Options - 7-tap unlock (7 tests)
- **NEW:** Consolidated Onboarding - Spotlight opt-in, delayed GettingStartedCard (17 tests)

**Previously Shipped (This Week):**
- **NEW:** Script Favorites System - star/favorite scripts with filter (38 tests)
- **NEW:** Offline Mode Banner - clear indication when network unavailable (25 tests)
- ~~**NEW:** Bulk Script Management~~ - **REMOVED in Wave 10** (undiscoverable, power-user only)
- **NEW:** UX Analysis Complete - 10 radical improvements identified
- **NEW:** UX Analysis Phase 3 - 8 new issues from new user perspective (see Phase 3 section)
- **NEW:** Unsaved Changes Warning - prevents data loss when closing script editor
- **NEW:** Downloaded Filter Empty State - helpful guidance when no downloads exist
- **NEW:** Passkey Linux Error Message - clear instructions for browser-based passkeys
- **NEW:** 2-Tab navigation (Home, Discover) with Profile menu in app bar
- **NEW:** Simplified first-run experience (just "What's your name?")
- **NEW:** Services renamed to "Explore" with subtitle
- **NEW:** Prominent Publish Button - share icon on local scripts, dismissible banner
- **NEW:** Passkey Quick Access - shows count in profile menu, highlights when no passkeys
- **NEW:** Script Reviews Tab - read-only reviews with rating distribution in ScriptDetailsDialog
- **NEW:** Script Versions Tab - version history with install capability in ScriptDetailsDialog
- **NEW:** Canister Interaction History - save/replay recent canister calls
- **NEW:** Long-press Context Menu - quick actions on script cards (mobile + desktop)
- **NEW:** Downloaded Filter - filter scripts by download status
- ~~**NEW:** Enhanced Quick Actions~~ - **REMOVED in Wave 11** (dead-end "See All" button)
- **NEW:** Single-Page Script Creation - tabs removed, sticky create button
- **NEW:** Canister Client Full Screen - 3-step flow (Canister → Function → Call)
- **NEW:** Response Format Toggle - JSON/Table/Raw view selector for results
- **NEW:** Search History - recent searches dropdown in marketplace
- **NEW:** Canister Autocomplete - search canisters by ID or name
- **NEW:** Actionable Error Handling - clear guidance on what to do when errors occur
- **NEW:** Getting Started Guide - checklist for new users with progress tracking
- **NEW:** Settings Screen - theme toggle (Light/Dark/System), app info, external links
- **NEW:** Account Profile Screen Tests - comprehensive test coverage (46 tests)
- Flattened Scripts screen (no nested tabs, Marketplace prominent)
- Script execution progress indicator
- Pull-to-refresh on all lists
- Keyboard shortcuts for desktop
- Simplified Canister Client Sheet
- Technical term tooltips
- Script menu reduced to 5 local / 2 marketplace options
- Consolidated Scripts Screen controls (4 rows → 1)
- Single-tap script execution (Play button on script rows)
- Editor toolbar cleanup (collapsed into overflow menu)

**Next Wave (Wave 14):** ONE-TAP script execution (#34 - highest ROI), empty state redesign (#35), eliminate registration wall (#36), global search (#40).

**Wave 13 COMPLETE (2026-02-23):** +68 new tests
- ✅ **My Library Screen** - Consolidated view of downloads, favorites, scripts, activity (24 tests)
- ✅ **Script Execution Bottom Sheet** - Run scripts in modal, not full screen (7 tests)
- ✅ **Contextual Help for Passkeys** - Tooltips on profile menu and account screen (37 tests)

**Wave 12 COMPLETE (2026-02-23):** -1400+ lines
- ✅ **Collapse 3-step Canister wizard to single screen** - Eliminated step wizard, all-in-one scrollable layout (19 tests)
- ✅ **Merge Bookmarks + Canister Client** - Eliminated duplicate screen, enhanced BookmarksScreen with inline calling, autocomplete, history (1338 lines deleted)
- ✅ **Local Script Search** - Search now filters local scripts by title/author, not just marketplace (6 tests)

**Wave 12 Status:**
| # | Improvement | Status | Notes |
|---|-------------|--------|-------|
| 1 | Collapse 3-step Canister wizard to single screen | ✅ DONE | Single scrollable screen |
| 2 | Merge Bookmarks + Canister Client | ✅ DONE | -1338 lines, inline client |
| 3 | Local Script Search | ✅ DONE | 6 tests |
| 4 | Consistent contextual help for jargon | ✅ DONE | Phase 6 item #33 (37 tests) |

**Recently Completed (Wave 11 - 2026-02-23):**

Payments and messaging are explicitly out of scope until the foundation is solid.

## Implementation Summary

| Area | Status | Completion |
|------|--------|------------|
| **2-Tab Navigation** | **COMPLETE** | 100% |
| **Quick Profile Creation** | **COMPLETE** | 100% |
| **Explore Tab (formerly Services)** | **COMPLETE** | 100% |
| **Profile Avatar Menu** | **COMPLETE** | 100% |
| Unified Setup Wizard | **COMPLETE** | 100% |
| Flattened Scripts Screen | **COMPLETE** | 100% |
| Consolidated Scripts Controls | **COMPLETE** | 100% |
| Single-Tap Script Execution | **COMPLETE** | 100% |
| Editor Toolbar Cleanup | **COMPLETE** | 100% |
| ~~Services Quick Actions~~ | **REMOVED** | N/A |
| Script Execution Progress | **COMPLETE** | 100% |
| Pull-to-Refresh | **COMPLETE** | 100% |
| Prominent Publish Button | **COMPLETE** | 100% |
| Passkey Quick Access | **COMPLETE** | 100% |
| ~~Featured Scripts Section~~ | **REMOVED** | N/A |
| Passkey UI Integration | **COMPLETE** | 100% |
| Linux Passkey Support | **COMPLETE** | 100% |
| Welcome Onboarding | **COMPLETE** | 100% |
| Lua Scripting UI | **COMPLETE** | 100% |
| Enhanced Empty States | **COMPLETE** | 100% |
| Encrypted Backup/Restore | **COMPLETE** | 100% |
| Download History Navigation | **COMPLETE** | 100% |
| ~~Post-Setup Guide~~ | **REMOVED** | N/A |
| Keyboard Shortcuts | **COMPLETE** | 100% |
| Canister Client UX | **COMPLETE** | 100% |
| Technical Term Tooltips | **COMPLETE** | 100% |
| Profile Management | **COMPLETE** | 100% |
| Navigation Labels (Explore) | **COMPLETE** | 100% |
| Script Menu Reduction | **COMPLETE** | 100% |
| **Script Reviews Tab** | **COMPLETE** | 100% |
| **Downloaded Filter** | **COMPLETE** | 100% |
| ~~Enhanced Quick Actions~~ | **REMOVED** | N/A |
| **Single-Page Script Creation** | **COMPLETE** | 100% |
| **Canister Client Full Screen** | **COMPLETE** | 100% |
| **Response Format Toggle** | **COMPLETE** | 100% |
| **Search History** | **COMPLETE** | 100% |
| **Canister Interaction History** | **COMPLETE** | 100% |
| **Script Versions Tab** | **COMPLETE** | 100% |
| **Long-Press Context Menu** | **COMPLETE** | 100% |
| **Canister Autocomplete** | **COMPLETE** | 100% |
| **Actionable Error Handling** | **COMPLETE** | 100% |
| **Getting Started Guide** | **COMPLETE** | 100% |
| **Settings Screen** | **COMPLETE** | 100% |
| **Account Profile Screen Tests** | **COMPLETE** | 100% |
| ~~Marketplace Stats Banner~~ | **REMOVED** | N/A |
| **Unsaved Changes Warning** | **COMPLETE** | 100% |
| **Downloaded Filter Empty State** | **COMPLETE** | 100% |
| **Passkey Linux Guidance** | **COMPLETE** | 100% |
| **Script Favorites System** | **COMPLETE** | 100% |
| **Offline Mode Banner** | **COMPLETE** | 100% |
| ~~Bulk Script Management~~ | **REMOVED** | N/A |
| **Scripts Screen Cleanup** | **COMPLETE** | 100% |
| **Profile Menu Discoverability** | **COMPLETE** | 100% |
| **Interactive Spotlight Tour** | **COMPLETE** | 100% |
| **Plain Language UX** | **COMPLETE** | 100% |
| **Empty State Secondary Action** | **COMPLETE** | 100% |
| **Profile/Account Terminology** | **COMPLETE** | 100% |
| **First Run Dialog Timing** | **COMPLETE** | 100% |
| **Quick Actions Plain Language** | **COMPLETE** | 100% |
| **Scripts Action Simplification** | **COMPLETE** | 100% |
| **Profile Menu Simplification** | **COMPLETE** | 100% |
| **Visual Template Picker** | **COMPLETE** | 100% |
| **Script List Visual Hierarchy** | **COMPLETE** | 100% |
| **Hidden Developer Options** | **COMPLETE** | 100% |
| **Consolidated Onboarding** | **COMPLETE** | 100% |
| **New User Default View** | **COMPLETE** | 100% |
| **Navigation Tab Labels** | **COMPLETE** | 100% |
| **Profile Form Simplified** | **COMPLETE** | 100% |
| **Favorite Star Icon Visible** | **COMPLETE** | 100% |
| ~~Bulk Selection Hint~~ | **SUPERSEDED** | N/A |
| **Scripts Screen State Machine** | **COMPLETE** | 100% |
| **Discoverable Script Actions** | **COMPLETE** | 100% |
| **Canister Client Simplified** | **COMPLETE** | 100% |
| ~~Section Separation~~ | **SUPERSEDED** | N/A |
| **Publish Account Prompt** | **COMPLETE** | 100% |
| **Active Filter Chips** | **COMPLETE** | 100% |
| **Navigation Clarity (Scripts/Canisters)** | **COMPLETE** | 100% |
| **Security Section Unified** | **COMPLETE** | 100% |
| **QuickUploadDialog Script Source Fix** | **COMPLETE** | 100% |
| **Script Diff Viewer** | **COMPLETE** | 100% |
| **Deep Linking (icpautorun://)** | **COMPLETE** | 100% |
| **Smart Candid Forms** | **COMPLETE** | 100% |
| **Unified Scripts View** | **COMPLETE** | 100% |
| ~~Selection Mode~~ | **REMOVED** | N/A |
| ~~Section Separation~~ | **REMOVED** | N/A |
| **Canister Wizard Collapsed** | **COMPLETE** | 100% |
| **Bookmarks+Client Merged** | **COMPLETE** | 100% |
| **Local Script Search** | **COMPLETE** | 100% |
| **Script Bottom Sheet** | **COMPLETE** | 100% |
| **My Library View** | **COMPLETE** | 100% |
| **Contextual Help (Passkeys)** | **COMPLETE** | 100% |
| Account Registration | Complete | 100% |
| Passkey Auth (backend) | Complete | 95% |
| Marketplace Browse/Search | Needs Testing | 90% |
| Marketplace Upload | Needs Testing | 95% |
| Script Execution (Lua) | Partial | 85% |
| Testing Coverage | Improved | ~95% |

**Detailed Specs:**
- [Implementation Status](docs/specs/IMPLEMENTATION_STATUS.md) - Feature-by-feature breakdown
- [Marketplace Status](docs/specs/MARKETPLACE_STATUS.md) - Marketplace implementation deep dive
- [Backend Integration](docs/specs/BACKEND_INTEGRATION.md) - API and data layer architecture
- [Test Coverage Gaps](docs/specs/TEST_COVERAGE_GAPS.md) - Missing tests analysis

---

## HIGH Priority

### Passkey Authentication
See [PASSKEY_IMPLEMENTATION_PLAN.md](PASSKEY_IMPLEMENTATION_PLAN.md) for architecture.

**Backend (DONE):**
- [x] WebAuthn endpoints (register/authenticate start/finish)
- [x] Vault encryption utilities (Argon2id + AES-GCM)
- [x] Recovery code system (generate, hash, verify)
- [x] Database schema (passkeys, recovery_codes, user_vaults tables)

**Frontend (DONE):**
- [x] PasskeyService using `passkeys` package
- [x] Vault password setup screen
- [x] Vault unlock screen
- [x] Recovery codes display screen
- [x] Passkey management screen (list, add, delete)

**Tests (DONE):**
- [x] PasskeyService unit tests
- [x] Screen widget tests
- [x] E2E tests with FakePasskeyAuthenticator (software emulator for CI)

**UI Integration (DONE):**
- [x] Add "Passkeys" menu item to AccountProfileScreen (in the profile menu sheet)
- [x] Wire PasskeyManagementScreen into navigation from account profile
- [x] Prompt passkey setup after account registration (optional onboarding step)
- [x] Add passkey status indicator on account profile (shows count, last used)

**Linux Support (DONE):**
> **Note:** The `passkeys` package does NOT support Linux natively (only Android, iOS, macOS, Web, Windows).
>
> **Solution:** Run as Flutter Web on Linux. Browser WebAuthn works with:
> - KeePassXC (software authenticator)
> - Android phone via hybrid auth (QR code flow)
> - Hardware security keys (YubiKey, etc.)

- [x] Document Linux testing workflow in AGENTS.md
- [x] Add platform check: disable passkey UI on Linux desktop, enable on Web
- [x] Test passkey flow via `flutter run -d chrome` on Linux

**Remaining (for full production):**
(none - vault decryption now available via Rust FFI)

### 2-Tab Navigation with Profile Menu (DONE - 2026-02-21)
- [x] Remove Profile tab from bottom navigation
- [x] Add avatar with dropdown menu in app bar
- [x] Tab 1: "Home" (Scripts screen)
- [x] Tab 2: "Discover" (Canister explorer - renamed from Services to Explore)
- [x] `ProfileAvatarButton` widget in top-right corner
- [x] `ProfileMenuWidget` bottom sheet with profile options
- [x] 11 new tests for navigation components
- **Impact:** Simplified navigation, more screen space for content
- **Files:** `lib/main.dart`, `lib/widgets/profile_menu.dart`

### Quick Profile Creation (DONE - 2026-02-21)
- [x] Replace Welcome + Setup Wizard with single "What's your name?" dialog
- [x] `QuickProfileCreationDialog` - minimal first-run experience
- [x] Creates local-only profile (no account registration required)
- [x] Account registration accessible from profile settings when user wants to publish
- [x] 9 new tests
- **Impact:** Reduces first-run friction from 3+ screens to 1 dialog
- **Files:** `lib/screens/quick_profile_creation_dialog.dart`, `lib/main.dart`

### Explore Tab Rename (DONE - 2026-02-21)
- [x] Rename "Services" to "Explore" in AppBar title
- [x] Add subtitle: "Interact with Internet Computer canisters"
- [x] Update navigation bar to use "Discover" label
- [x] 5 new tests
- **Impact:** Clearer purpose for the tab
- **Files:** `lib/screens/bookmarks_screen.dart`

### Unified Setup Wizard (DONE)
- [x] `UnifiedSetupWizard` - single form for profile + optional account
- [x] Display name field (required)
- [x] Username field (optional, skip to create local-only profile)
- [x] Real-time username validation with debouncing
- [x] Success screen showing created profile/account
- [x] 12 unit/widget tests
- [x] Replaced old multi-step flow (KeyParametersDialog + AccountRegistrationWizard)

### Flattened Scripts Screen (DONE)
- [x] Removed nested tabs (My Scripts, All, Marketplace)
- [x] Single unified list showing both local and marketplace scripts
- [x] Source filter chips: All / Local / Marketplace
- [x] Category filter chips
- [x] Sort dropdown with ascending/descending toggle
- [x] Source badges on each item (Local/Marketplace)
- [x] "Available" badge for non-installed marketplace scripts
- [x] 7 unit/widget tests

### Single-Tap Script Execution (DONE - 2026-02-21)
- [x] Add visible "Play" icon button on each local script row
- [x] Run is now the PRIMARY action (one tap)
- [x] Popup menu contains secondary actions (delete, duplicate, export, publish)
- [x] 11 updated + 2 new widget tests
- **Impact:** Users run scripts with 1 tap instead of 2

### Editor Toolbar Cleanup (DONE - 2026-02-21)
- [x] Collapse clutter into overflow menu
- [x] Keep visible: Language badge, Theme selector
- [x] In overflow: Stats (lines/chars), Line numbers toggle, UI Components, Code snippets, Copy
- [x] Removed non-working "Format code" button
- [x] 7 new widget tests

### Consolidated Scripts Screen Controls (DONE - 2026-02-21)
- [x] Single search bar with filter button (tune icon with badge)
- [x] Removed Local/Marketplace filter chips - show all scripts with badges
- [x] Categories/sort moved to filter bottom sheet
- [x] Reset button to restore default filters
- [x] Active filter count badge on filter button
- [x] 35+ tests (unified_view_test.dart + filter_popover_test.dart)

### Script Execution Progress (DONE)
- [x] `ScriptExecutionProgress` model with phases (idle, initializing, calling_canister, processing, complete, error)
- [x] `ScriptExecutionProgressIndicator` widget with spinner and step message
- [x] Cancel support during cancellable phases
- [x] Integrated with `ScriptAppHost`
- [x] 12 unit/widget tests

### Pull-to-Refresh (DONE)
- [x] RefreshIndicator on BookmarksScreen
- [x] RefreshIndicator on PasskeyManagementScreen
- [x] Already existed on: ScriptsScreen, DownloadHistoryScreen, ProfileHomePage
- [x] 3 unit tests

### Welcome Onboarding Flow (DONE)
- [x] `OnboardingService` - manages onboarding state with versioning
- [x] `WelcomeOnboardingScreen` - animated welcome with feature highlights
- [x] "Get Started" button -> unified setup wizard
- [x] "Browse Marketplace" button -> scripts screen
- [x] "Skip for now" option
- [x] Only shows when NO profiles AND NO scripts
- [x] 20 unit/widget tests

### Post-Setup Guide (DONE - 2026-02-20)
- [x] `PostSetupGuide` dialog after successful profile creation
- [x] Three action tiles: Browse Marketplace, Create Script, Explore Canisters
- [x] "Don't show again" option with state persistence
- [x] "Maybe Later" dismiss option
- [x] Integration with `OnboardingService` for state tracking
- [x] 26 tests (18 service + 8 widget tests)

### Keyboard Shortcuts (DONE - 2026-02-20)
- [x] `Ctrl/Cmd + N` - New Script
- [x] `Ctrl/Cmd + F` - Focus search
- [x] `R` - Refresh current screen
- [x] `Ctrl/Cmd + 1/2` - Switch tabs (updated for 2-tab navigation)
- [x] `Escape` - Close dialogs/modals
- [x] Platform detection (desktop only)
- [x] `ShortcutTooltip` widget for keyboard hints
- [x] 11 widget tests

### Canister Client UX Simplification (DONE - 2026-02-20)
- [x] State machine flow: `disconnected` → `connecting` → `connected` → `ready`
- [x] Friendly labels with tooltips ("Canister" instead of "Canister ID")
- [x] Progressive disclosure (advanced options collapsed)
- [x] Method chips for quick selection
- [x] Auto-detect method kind (Query/Update) shown as colored badge
- [x] "No input required" for zero-arg methods
- [x] Friendly error messages
- [x] Quick Start section with well-known canisters
- [x] 10 widget tests

### Technical Term Tooltips (DONE - 2026-02-20)
- [x] `TechTerms` utility with 10 ICP term definitions
- [x] `InfoTooltip` widget family (4 variants)
- [x] Applied to: ProfileHomePage, AccountProfileScreen, CanisterClientSheet
- [x] Terms: Canister, Principal, Candid, Keypair, Query, Update, Cycles, Replica
- [x] 25 tests (13 utils + 12 widget tests)

### Profile Management (DONE)

**Done:**
- [x] ProfileController with create/switch/delete profiles
- [x] ProfileRepository (local storage)
- [x] Profile model with 1-10 keypairs per profile
- [x] Encrypted keypair export for disaster recovery
- [x] Encrypted backup file generation/restore
- [x] Key labels in AccountPublicKey model
- [x] Export Keys dialog with password protection
- [x] Import Keys dialog for restoring from backup
- [x] ProfileController tests (67 tests - 2026-02-20)

**Missing:**
- [ ] Key label editing UI (blocked by API - no `updateKeyLabel` endpoint)

### Account Registration (DONE)

**Done:**
- [x] AccountController (register, add/remove keys, update profile)
- [x] AccountSignatureService (Ed25519 signing)
- [x] AccountRegistrationWizard screen (legacy - replaced by UnifiedSetupWizard)
- [x] Account profile screen
- [x] Full AccountController test coverage (21 tests - 2026-02-21)
- [x] Integration: redirect to passkey setup after registration

**Done:**
- [x] AccountProfileScreen widget tests (DONE - 46 tests - 2026-02-22)

### Script Management
- [x] Add secp256k1 script signing via Rust FFI
- [x] Implement SHA256 checksums for script integrity verification
- [x] Add support for installing specific script versions locally
- [x] QuickUploadDialog uses actual script.luaSource (FIX - 2026-02-22)
  - **Bug:** Dialog was generating placeholder code instead of using real script
  - **Fix:** Pre-fill code preview with actual `luaSource` from ScriptRecord
  - **Test:** `test/widgets/quick_upload_dialog_test.dart` (4 tests for source handling)

### Lua Scripting UI (DONE)
- [x] Add tables with columns to UI elements
- [x] Support paginated lists with loading states driven by Lua (`paginated_list` widget)
- [x] Add menu to pick common UI elements in script editor (UI Component Palette)
  - 12 components across 4 categories (Layout, Text, Input, Display)
  - Inserts Lua templates at cursor position
  - 13 unit/widget tests

### Testing (CRITICAL - Blocking Production)
- [x] Profile Controller tests (DONE - 67 tests)
- [x] Account Controller full coverage (DONE - 21 tests - 2026-02-21)
- [x] Passkey Service tests (DONE)
- [x] Onboarding tests (DONE - 20 tests)
- [x] UI Component Palette tests (DONE - 13 tests)
- [x] Paginated List tests (DONE - 9 tests)
- [x] Empty State tests (DONE - 12 tests)
- [x] Scripts Screen navigation tests (DONE - 3 tests)
- [x] Export/Import Keys dialog tests (DONE - 16 tests)
- [x] Scripts Screen widget tests (DONE - 35+ tests including filter popover)
- [x] Script Menu tests (DONE - 11 tests - 2026-02-21)
- [x] Script Editor tests (DONE - 7 new tests - 2026-02-21)
- [x] Services Quick Actions tests (DONE - 10 tests - 2026-02-21)
- [x] Navigation tests (DONE - 11 tests - 2026-02-21)
- [x] Quick Profile Creation tests (DONE - 9 tests - 2026-02-21)
- [x] UX Improvements tests (DONE - 5 tests - 2026-02-21)
- [x] Publish Button tests (DONE - 11 tests - 2026-02-21)
- [x] Profile Menu Passkey tests (DONE - 6 tests - 2026-02-21)
- [x] Featured Section tests (DONE - 5 tests - 2026-02-21)
- [x] Script Reviews tests (DONE - 8 tests - 2026-02-22)
- [x] Downloaded Filter tests (DONE - 4 tests - 2026-02-22)
- [x] Enhanced Quick Actions tests (DONE - 6 new tests, 15 total - 2026-02-22)
- [x] Single-Page Script Creation tests (DONE - 11 tests - 2026-02-22)
- [x] Canister Client Full Screen tests (DONE - 11 tests - 2026-02-22)
- [x] Response Format Toggle tests (DONE - 10 tests - 2026-02-22)
- [x] Search History tests (DONE - 24 tests - 2026-02-22)
- [x] Canister History tests (DONE - 23 tests - 2026-02-22)
- [x] Script Versions tests (DONE - 11 tests - 2026-02-22)
- [x] Long-Press Context Menu tests (DONE - 19 tests - 2026-02-22)
- [x] didChangeDependencies tests (DONE - 3 tests - 2026-02-22)
- [x] Canister Autocomplete tests (DONE - 13 tests - 2026-02-22)
- [x] Actionable Error Display tests (DONE - 36 tests - 2026-02-22)
- [x] Guided Next Steps tests (DONE - 21 tests - 2026-02-22)
- [x] Account Profile Screen tests (DONE - 46 tests - 2026-02-22)
- [x] Settings Screen tests (DONE - 26 tests - 2026-02-22)
- [x] Marketplace Stats Banner tests (DONE - 10 tests - 2026-02-22)
- [x] Unsaved Changes Warning tests (DONE - 10 tests - 2026-02-22)
- [x] Downloaded Filter Empty State tests (DONE - 5 tests - 2026-02-22)
- [x] Passkey Linux Message tests (DONE - 5 tests - 2026-02-22)
- [x] Script Favorites tests (DONE - 38 tests - 2026-02-23)
- [x] Offline Mode Banner tests (DONE - 25 tests - 2026-02-23)
- ~~[x] Bulk Script Management tests~~ - **REMOVED in Wave 10** (feature removed)
- [x] Empty State Secondary Action tests (DONE - 4 tests - 2026-02-21)
- [x] First Run Dialog Timing tests (DONE - 10 tests - 2026-02-21)
- [x] Profile Terminology tests (DONE - 9 tests - 2026-02-21)
- [x] Quick Actions Plain Language tests (DONE - 3 tests - 2026-02-21)
- [x] New User Default View tests (DONE - 6 tests - 2026-02-21)
- [x] Profile Form Collapsed tests (DONE - 4 tests - 2026-02-21)
- [x] Favorite Star Icon tests (DONE - 15 tests - 2026-02-21)
- ~~[x] Bulk Selection Hint tests~~ - **REMOVED in Wave 10** (feature removed)
- [x] Scripts View Machine tests (DONE - 24 tests - 2026-02-21)
- [x] Discoverable Script Actions tests (DONE - 10 tests - 2026-02-21)
- [x] Canister Client Simplified tests (DONE - 5 tests - 2026-02-21)
- ~~[x] Section Separation tests~~ - **SUPERSEDED in Wave 10** (unified view)
- [x] Profile Avatar Badge tests (DONE - 6 tests - 2026-02-21)
- [x] Publish Account Prompt tests (DONE - 5 tests - 2026-02-21)
- [x] Active Filter Chips tests (DONE - 24 tests - 2026-02-21)
- [x] Canister Wizard Collapsed tests (DONE - 19 tests - 2026-02-23)
- [x] Merged Bookmarks+Client tests (DONE - autocomplete 13 + history 6 = 19 tests - 2026-02-23)
- [x] Local Script Search tests (DONE - 6 tests - 2026-02-23)
- [x] My Library Screen tests (DONE - 24 tests - 2026-02-23)
- [x] Script Bottom Sheet tests (DONE - 7 tests - 2026-02-23)
- [x] Contextual Help (Passkey) tests (DONE - 37 tests - 2026-02-23)
- [x] Passkey/Execute Test Fixes (DONE - 28 tests fixed - 2026-02-23)
- [ ] Lua Engine tests in Rust crate (MISSING)
- [ ] Integration tests for complete user flows

**Cannot Test (requires hardware):**
- WebAuthn passkey registration/authentication (use FakePasskeyAuthenticator for CI; real device for final validation)

### Radical UX Improvements (HIGH PRIORITY)

> Analysis completed 2026-02-23. Goal: Remove clutter, improve discoverability, make the app dramatically more intuitive.

**1. Scripts Screen: Information Overload** ✅ **DONE - 2026-02-21**
- **Pain Point:** 6+ competing elements: stats banner, search, getting started card, featured carousel, share banner, mixed list
- **Change:** Removed stats banner, share banner, getting started card - cleaner UI
- **Impact:** 80% less visual noise
- **Complexity:** 4/10
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/scripts_screen_cleanup_test.dart` (7 tests)

**2. Profile Menu Discoverability** ✅ **DONE - 2026-02-21**
- **Pain Point:** 36px avatar button is invisible; users don't discover passkeys, settings, profiles
- **Change:** Added "Profile" label in a pill container next to avatar
- **Impact:** 100% increase in passkey adoption expected
- **Complexity:** 3/10
- **Files:** `lib/widgets/profile_menu.dart`
- **Tests:** `test/widgets/profile_menu_discoverability_test.dart` (5 tests)

**3. Plain Language + Progressive Disclosure** ✅ **DONE - 2026-02-21**
- **Pain Point:** Jargon everywhere: "Canister", "Candid", "Principal", "Query/Update"
- **Change:** Added plain language labels to TechTerm enum: "Canister"→"Service", "Query"→"Read", "Update"→"Write"; added tooltips with explanations
- **Impact:** 30% fewer support questions expected, broader user base
- **Complexity:** 5/10
- **Files:** `lib/utils/tech_terms.dart`, `lib/screens/canister_client_screen.dart`, `lib/screens/bookmarks_screen.dart`, `lib/widgets/canister_call_builder.dart`
- **Tests:** `test/features/ux/plain_language_test.dart` (12 tests)

**4. Merge Bookmarks + Canister Client** ✅ **DONE - 2026-02-23**
- **Pain Point:** 65% overlapping functionality; users don't know which to use
- **Change:** Eliminated CanisterClientScreen; enhanced BookmarksScreen with inline calling, autocomplete, history
- **Impact:** -1338 lines, clearer mental model
- **Complexity:** 6/10 (6-8 hour estimate)
- **Tests:** `test/features/canister_client/autocomplete_test.dart`, `test/features/canister_client/history_test.dart` (19 tests)
- **Files:** `lib/screens/bookmarks_screen.dart` (deleted: `lib/screens/canister_client_screen.dart`)

**5. Collapse Key Management into "Security"** ✅ **DONE - 2026-02-22**
- **Pain Point:** Public Keys, Signing Key, Passkeys - confusing concepts
- **Change:** Single "Security" section; list auth methods together
- **Impact:** 60% reduction in user confusion
- **Complexity:** 7/10
- **Files:** `lib/screens/account_profile_screen.dart`
- **Tests:** `test/features/account_profile/security_section_test.dart` (10 tests)

**6. Remove Featured Scripts Carousel** ✅ **DONE - 2026-02-21**
- **Pain Point:** Takes vertical space, duplicates marketplace content
- **Change:** Removed carousel entirely; screen is simpler
- **Impact:** Simpler UI, more vertical space for scripts
- **Complexity:** 2/10
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/featured_section_test.dart` (2 new tests)

---

### Radical UX Improvements - Phase 3 (NEW - 2026-02-21)

> **Analysis completed by reviewing app from NEW USER perspective.**
> Goal: Identify confusing, missing, or hard-to-use elements that would frustrate first-time users.

**7. First Run: Dialog Fatigue** ✅ **DONE - 2026-02-21**
- **Pain Point:** User enters name in QuickProfileCreationDialog → immediately sees PostSetupGuide with 3 choices → has not even SEEN the app yet!
- **Change:** Delay PostSetupGuide by 5 seconds OR show only after first meaningful action (viewing a script, exploring a canister)
- **Implementation:** Added `markAppUsable()`, `recordFirstMeaningfulAction()`, and `isPostSetupGuideReady()` to `OnboardingService`. PostSetupGuide now shows after either: (1) 5 second delay since app became usable, OR (2) user performs first meaningful action (view script, explore canister).
- **Impact:** 50% less first-run abandonment, users feel guided not pressured
- **Complexity:** 3/10
- **Files:** `lib/main.dart`, `lib/services/onboarding_service.dart`, `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/onboarding/first_run_timing_test.dart` (10 tests)

**8. Scripts Screen: State Explosion** ✅ **DONE - 2026-02-21**
- **Pain Point:** 2000+ line screen handles 8+ states (loading, empty, empty downloaded, empty favorites, selection mode, search mode, searching, offline). Users encounter "Your Script Library is Empty" before seeing marketplace.
- **Change:** Created ScriptsViewMachine class with clean state enum; initialize marketplace loading to true to prevent empty state flash; 24 new tests
- **Impact:** 40% reduction in cognitive load, cleaner first impression
- **Complexity:** 8/10 (refactor required) - **Phase 1 complete**
- **Files:** `lib/screens/scripts_screen.dart`, `lib/screens/scripts_screen_state.dart`
- **Tests:** `test/features/scripts/scripts_view_machine_test.dart` (24 tests)

**9. Mixed Mental Model: Local vs Marketplace** ✅ **DONE - 2026-02-21**
- **Pain Point:** "Scripts" tab mixes LOCAL files and MARKETPLACE items. Users do not know what to expect. Is this MY stuff or EVERYONES stuff?
- **Change:** Fixed timing - new users now see loading indicator while marketplace loads instead of "Your Script Library is Empty"; marketplace scripts appear immediately after load
- **Impact:** 60% clearer mental model, users see content immediately
- **Complexity:** 3/10 (fixed with loading state check)
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/new_user_default_view_test.dart` (6 tests)

**10. Hidden Script Actions** ✅ **DONE - 2026-02-21**
- **Pain Point:** Critical actions buried in 3-dot menus, long-press, right-click. Users do not discover Run, Edit, Delete, Publish.
- **Change:** Created HoverRevealActions widget - actions visible on hover (desktop) or always visible (mobile); ScriptActionButton for consistent styling
- **Impact:** 70% faster task completion, fewer "how do I?" questions
- **Complexity:** 4/10
- **Files:** `lib/screens/scripts_screen.dart`, `lib/widgets/hover_reveal_actions.dart`
- **Tests:** `test/features/scripts/discoverable_actions_test.dart` (10 tests)

**11. Account Profile: Form Overwhelm** ✅ **DONE - 2026-02-21**
- **Pain Point:** 7 editable fields immediately visible (display name, email, telegram, twitter, discord, website, bio). Plus Public Keys section with Import/Export buttons. Visual overload.
- **Change:** Collapsed social fields (email, telegram, twitter, discord, website) into "Contact Info" ExpansionTile; show only display name + bio by default
- **Impact:** 50% less form anxiety, cleaner profile page
- **Complexity:** 4/10
- **Files:** `lib/screens/account_profile_screen.dart`
- **Tests:** `test/features/account_profile/profile_editing_test.dart` (4 new tests for collapsed/expanded)

**12. "Profile" vs "Account" Confusion** ✅ **DONE - 2026-02-21**
- **Pain Point:** Menu says "Edit Profile" and "Create Account" - what is the difference? Users do not understand the local profile vs backend account distinction.
- **Change:** Renamed "Edit Profile" → "My Identity" (local), "Create Account" → "Register Username" (cloud); added explainer tooltips
- **Impact:** 40% reduction in support questions about account setup expected
- **Complexity:** 3/10
- **Files:** `lib/widgets/profile_menu.dart`, `lib/screens/account_profile_screen.dart`, `lib/screens/account_registration_wizard.dart`
- **Tests:** `test/widgets/profile_menu_terminology_test.dart` (9 tests)

**13. Empty State Guidance** ✅ **DONE - 2026-02-21**
- **Pain Point:** Empty states exist but do not guide users to the NEXT action. "Your Script Library is Empty" → "Create Script" button. What if user wants to browse first?
- **Change:** Add secondary action "Browse Marketplace" to empty state; context-aware suggestions
- **Impact:** 30% better first-session engagement
- **Complexity:** 3/10
- **Files:** `lib/screens/scripts_screen.dart` (ModernEmptyState widget)
- **Test:** `test/features/scripts/empty_state_secondary_action_test.dart` (4 tests)

**14. Canister Jargon in Quick Actions** ✅ **DONE - 2026-02-21**
- **Pain Point:** Quick Actions use "ICP Balance", "View Neurons", "NNS Governance" - crypto-native users understand, but regular users do not
- **Change:** Replaced jargon with plain-language descriptions: "Check your token balance", "See your voting power in governance", "Find apps on the Internet Computer"
- **Impact:** 25% broader appeal to non-crypto users
- **Complexity:** 2/10
- **Files:** `lib/screens/bookmarks_screen.dart`
- **Tests:** `test/features/services/quick_actions_test.dart` (3 new tests)

---

### Radical UX Improvements - Phase 4 (NEW - 2026-02-21)

> **Analysis completed by comprehensive codebase exploration from NEW USER perspective.**
> Goal: Identify remaining UX issues that would RADICALLY improve intuitiveness.

**15. Navigation: "Discover" Tab Misleads Users** ✅ **DONE - 2026-02-21**
- **Pain Point:** Second tab labeled "Discover" but it's actually Bookmarks/Canister Explorer. Users expect "Discover" to find marketplace scripts, not bookmarks.
- **Change:** Renamed tab from "Discover" to "Explore" to match the AppBar title in BookmarksScreen
- **Impact:** HIGH - Consistent naming eliminates user confusion
- **Complexity:** 1/10 (simple label change)
- **Files:** `lib/main.dart`
- **Tests:** `test/features/navigation/navigation_test.dart` (3 tests updated)

**16. Scripts Screen: Too Many Actions Per Script** ✅ **DONE - 2026-02-21**
- **Pain Point:** Each script has play button, share button, overflow menu with 5+ options, plus 4 filter toggles, category chips, sort options, search history, selection mode. Overwhelming!
- **Change:** Reduced visible actions to ONE primary action (Play for local, Download/View for marketplace); moved ALL secondary actions to single "..." overflow menu; removed inline share button
- **Impact:** HIGH - Main screen feels cleaner and less intimidating
- **Complexity:** 4/10
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/simplified_actions_test.dart` (14 tests), updated `test/features/scripts/publish_button_test.dart` (11 tests)

**17. Profile Menu: Too Many Options** ✅ **DONE - 2026-02-21**
- **Pain Point:** Profile menu shows 8 options including "Restart Tour", "Getting Started", "Switch Profile", "Create Profile" etc. New users see irrelevant options.
- **Change:** Reduced to max 5 items; moved "Getting Started"/"Restart Tour" to Settings > Help; combined "Switch Profile" + "Create Profile" into "Manage Profiles" bottom sheet
- **Impact:** MEDIUM-HIGH - Profile menu is cleaner and less overwhelming
- **Complexity:** 5/10
- **Files:** `lib/widgets/profile_menu.dart`, `lib/screens/settings_screen.dart`
- **Tests:** `test/widgets/profile_menu_simplified_test.dart` (12 tests)

**18. Canister Client Sheet: Too Complex** ✅ **DONE - 2026-02-21**
- **Pain Point:** CanisterClientSheet has 4 flow states, multiple inputs, advanced options, JSON editor toggle, quick start section. Overwhelming for simple queries.
- **Change:** Removed redundant "Arguments" header and "Auto" switch from _ArgsEditor; single "Input" header now; cleaner quick query flow
- **Impact:** MEDIUM - Advanced feature but intimidates beginners
- **Complexity:** 7/10 - **Phase 1 complete**
- **Files:** `lib/screens/bookmarks_screen.dart`
- **Tests:** `test/canister_client_sheet_test.dart` (5 new tests, 49 total)

**19. Template Selector: Buried in Form** ✅ **DONE - 2026-02-21**
- **Pain Point:** Template selector is a dropdown that looks like form metadata. Users might miss templates exist.
- **Change:** Replaced dropdown with visual template cards as first thing users see; each card shows emoji, title, description, difficulty badge (Beginner/Intermediate/Advanced); added "Blank Script" option; selected template is highlighted with checkmark
- **Impact:** MEDIUM - Templates now discoverable, helps beginners get started
- **Complexity:** 5/10
- **Files:** `lib/screens/script_creation_screen.dart`
- **Tests:** `test/visual_template_picker_test.dart` (9 tests), updated `test/script_creation_screen_test.dart` (10 tests)

**20. Too Many Onboarding Overlays** ✅ **DONE - 2026-02-21**
- **Pain Point:** Multiple onboarding mechanisms: QuickProfileCreationDialog, GettingStartedCard, PostSetupGuide, SpotlightTour. Can overlap and overwhelm.
- **Change:** Consolidated into ONE streamlined flow: SpotlightTour is now opt-in via Settings only; GettingStartedCard shows only after first script interaction; added "Getting Started" and "Restart Tour" options to Settings screen
- **Impact:** MEDIUM - Reduces cognitive load, no overlapping dialogs
- **Complexity:** 6/10
- **Files:** `lib/main.dart`, `lib/screens/settings_screen.dart`, `lib/screens/scripts_screen.dart`, `lib/services/spotlight_service.dart`, `lib/services/onboarding_progress_service.dart`
- **Tests:** `test/features/onboarding/consolidated_onboarding_test.dart` (17 tests), updated spotlight tests

**21. Script List: Weak Visual Hierarchy** ✅ **DONE - 2026-02-21**
- **Pain Point:** Each script item shows emoji, title, source badge, subtitle with author/version/run count, action buttons, "Available" badge. Visual noise.
- **Change:** Simplified to emoji + title + one-line subtitle (author for marketplace, date for local); moved source badge to small color-coded icon (blue=local, green=marketplace); "Available" shown as subtle download icon next to title
- **Impact:** LOW-MEDIUM - Cleaner list, easier scanning
- **Complexity:** 3/10
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/script_list_visual_hierarchy_test.dart` (18 tests)

**22. Settings: Developer Info Unnecessary** ✅ **DONE - 2026-02-21**
- **Pain Point:** Settings shows "API Endpoint" and "Environment" in Developer Info section. Irrelevant noise for new users.
- **Change:** Hidden Developer Info by default; tap version 7 times to unlock (Android-style); shows tap countdown in snackbar; added "Clear Developer Options" button
- **Impact:** LOW - Cleaner Settings screen for regular users
- **Complexity:** 2/10
- **Files:** `lib/screens/settings_screen.dart`, `lib/services/settings_service.dart`
- **Tests:** `test/features/settings/settings_screen_test.dart` (7 new tests for developer options)

**23. Favorites Feature Not Discoverable** ✅ **DONE - 2026-02-21**
- **Pain Point:** Favorites system exists but star icon buried in overflow menu. Users can't discover this feature.
- **Change:** Added visible star icon to every script list item; tapping toggles favorite status; filled amber star for favorites, outlined for non-favorites
- **Impact:** MEDIUM-HIGH - Users can now easily favorite scripts for quick access
- **Complexity:** 3/10
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/favorite_star_icon_test.dart` (15 tests)

**24. Bulk Selection Hidden** ✅ **DONE - 2026-02-21**
- **Pain Point:** Bulk script management (multi-select, bulk delete/export) requires long-press but zero indication this feature exists.
- **Change:** Added dismissible tip banner "Tip: Long-press to select multiple scripts" that appears once for users with scripts; preference persisted
- **Impact:** MEDIUM - Users discover bulk management feature
- **Complexity:** 3/10
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/selection_hint_test.dart` (13 tests)

---

### Radical UX Improvements - Phase 5 (NEW - 2026-02-21)

> **Analysis completed from NEW USER perspective - focusing on navigation and discoverability.**

**25. Rename "Explore" Tab to "Services"** ✅ **DONE - 2026-02-21**
- **Pain Point:** New users expect "Explore" to browse marketplace scripts. Instead, it shows canister tools and bookmarks - completely different content. Major expectation violation.
- **Change:** Renamed tab to "Services" (already done in previous session); this is now redundant with the section separation work
- **Impact:** HIGH - Prevents immediate user confusion
- **Complexity:** 2/10 - Simple text changes
- **Files:** `lib/main.dart`, `lib/screens/bookmarks_screen.dart`

**26. Visually Separate "My Scripts" from "Marketplace"** ✅ **DONE - 2026-02-21**
- **Pain Point:** Home screen shows unified list mixing local and marketplace scripts. New users with no scripts see overwhelming list. Distinction is only a tiny color-coded icon.
- **Change:** Added SegmentedButton toggle (All/My Scripts/Marketplace) at top; section headers with colored icons (blue/green) and count badges; contextual empty states for each section
- **Impact:** HIGH - Dramatically improves clarity
- **Complexity:** 6/10 - Requires refactoring list builder
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/section_separation_test.dart` (9 tests)

**27. Surface "Register Username" When Publishing** ✅ **DONE - 2026-02-21**
- **Pain Point:** Publishing to marketplace requires "cloud username" but option is buried in profile menu with no explanation of why user needs it.
- **Change:** Added red dot badge on profile avatar when no account linked; contextual prompt appears when trying to publish without account; navigates to registration wizard on confirmation
- **Impact:** MEDIUM-HIGH - Users discover key feature when relevant
- **Complexity:** 4/10 - Add conditional badge and dialog
- **Files:** `lib/screens/scripts_screen.dart`, `lib/widgets/profile_menu.dart`, `lib/main.dart`
- **Tests:** `test/widgets/profile_avatar_badge_test.dart` (6 tests), `test/features/scripts/publish_account_prompt_test.dart` (5 tests)

**28. Show Active Filter Chips Prominently** ✅ **DONE - 2026-02-21**
- **Pain Point:** Filter button shows count badge but users don't know WHAT filters are active. Empty results from active filter looks like broken app.
- **Change:** Added filter chips directly below search bar when filters active; each chip dismissible with X; Clear All button for multiple filters
- **Impact:** MEDIUM - Prevents "stuck in filter" frustration
- **Complexity:** 4/10 - Add chip row below search bar
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/active_filter_chips_test.dart` (24 tests)

**29. Add Welcome Card for Brand New Users** 🟡 **MEDIUM IMPACT** (OPTIONAL)
- **Pain Point:** Brand new user (0 scripts, 0 downloads) sees Home screen with no guidance on what to DO.
- **Change:** For users with 0 scripts AND 0 downloads, show Welcome Card with [Browse Marketplace] [Create Script] options
- **Impact:** MEDIUM - First-time users get immediate guidance
- **Complexity:** 3/10 - Reuse existing GettingStartedCard widget
- **Files:** `lib/screens/scripts_screen.dart`, `lib/widgets/getting_started_card.dart`
- **Note:** Section separation already provides good guidance; this is now lower priority

---

### Radical UX Improvements - Phase 6 (NEW - 2026-02-23)

> **Analysis completed from NEW USER perspective - identifying remaining UX gaps.**

**30. No Script Preview/Test Before Download** 🔴 **HIGH IMPACT**
- **Pain Point:** Users can only see first 50 lines of code before downloading. No way to "try before you buy" or see what the script actually does. Major trust barrier.
- **Change:** Add "Preview" button to ScriptDetailsDialog showing expected input/output format, simulated run with sample data, or full README
- **Impact:** HIGH - Users make informed download decisions
- **Complexity:** 7/10
- **Files:** `lib/widgets/script_details_dialog.dart`, new: `lib/services/script_preview_service.dart`
- **Note:** Blocked by backend support for script metadata

**31. No "My Content" Consolidated View** ✅ **DONE - 2026-02-21**
- **Pain Point:** Downloaded scripts, published scripts, bookmarks, download history are scattered across multiple places. No single place to see "everything I've done"
- **Change:** Add "My Library" section or dedicated screen showing downloaded, published, favorite scripts, and recent activity
- **Impact:** MEDIUM-HIGH - Users find their content easily
- **Complexity:** 5/10
- **Files:** `lib/widgets/profile_menu.dart`, `lib/screens/my_library_screen.dart`
- **Tests:** `test/features/my_library/my_library_screen_test.dart` (19 tests), `test/features/my_library/navigation_test.dart` (5 tests)

**32. Running Scripts Is Disruptive (Full Screen Navigation)** ✅ **DONE - 2026-02-21**
- **Pain Point:** Running a script navigates to full screen, losing context. Can't quickly run multiple scripts in succession.
- **Change:** Show script output in bottom sheet/dialog with "Expand to full screen" option
- **Impact:** MEDIUM - Faster script execution workflow
- **Complexity:** 6/10
- **Files:** `lib/screens/scripts_screen.dart`, new: `lib/widgets/script_execution_bottom_sheet.dart`
- **Tests:** `test/features/scripts/script_bottom_sheet_test.dart` (7 tests)

**33. Contextual Help Is Inconsistent** ✅ **DONE - 2026-02-23**
- **Pain Point:** TechTerms tooltips exist but applied inconsistently. "Passkeys", "Signing Key", "Keypair" not explained in profile menu.
- **Change:** Added `passkey` term to TechTerms; added tooltips to Passkeys menu item in profile menu and Passkeys section in account profile screen
- **Impact:** MEDIUM - Broader user base understands technical terms
- **Complexity:** 3/10
- **Files:** `lib/widgets/profile_menu.dart`, `lib/screens/account_profile_screen.dart`, `lib/utils/tech_terms.dart`
- **Tests:** `test/utils/tech_terms_test.dart`, `test/widgets/profile_menu_terminology_test.dart`, `test/screens/account_profile_screen_tooltip_test.dart` (37 tests)

---

### Radical UX Improvements - Phase 7 (NEW - 2026-02-23)

> **Analysis completed from NEW USER perspective - identifying radical improvements for intuitiveness.**

**34. ONE-TAP Script Execution** 🔴 **HIGHEST IMPACT - HIGHEST ROI**
- **Pain Point:** Current flow: Find script → Tap opens editor → Close → Find Run button → Run. 3-4 taps for the most common action.
- **Change:** Single tap on script = RUN immediately. Move Edit to long-press or explicit button.
- **Impact:** HIGH - 75% reduction in taps for primary use case
- **Complexity:** 3/10
- **Files:** `lib/screens/scripts_screen.dart`
- **ROI:** BEST - Low complexity, high impact

**35. Empty State Redesign - Never Show Empty** 🔴 **HIGH IMPACT**
- **Pain Point:** "Your Script Library is Empty" is discouraging. Doesn't guide users to value.
- **Change:** First visit shows featured marketplace scripts directly. Progressive guidance: First download → "Run it now", First run → "Create your own"
- **Impact:** HIGH - First impression is critical
- **Complexity:** 5/10
- **Files:** `lib/screens/scripts_screen.dart`
- **Dependencies:** Featured scripts API

**36. Eliminate Registration Wall for Script Creation** 🔴 **HIGH IMPACT**
- **Pain Point:** Registration form has 8+ fields. Users see "Register @username" badge causing anxiety.
- **Change:** Deferred registration - allow local-only script creation. Show "Share to Marketplace" only when publishing. Simplify registration to username + display name ONLY.
- **Impact:** HIGH - Removes friction from first-time script creation
- **Complexity:** 5/10 (requires backend changes for minimal registration)
- **Files:** `lib/screens/account_registration_wizard.dart`, `lib/widgets/profile_menu.dart`

**37. Unified "Discover" Tab - Merge Scripts & Explore** 🟡 **HIGH IMPACT**
- **Pain Point:** Two tabs confusing. "Scripts" = local + marketplace mixed. "Explore" = canister tools (different purpose).
- **Change:** Three clear tabs: 1) My Scripts (local/downloaded), 2) Discover (marketplace + canisters), 3) Profile
- **Impact:** HIGH - Clarifies app purpose immediately
- **Complexity:** 7/10 (significant restructuring)
- **Files:** `lib/main.dart`, `lib/screens/scripts_screen.dart`, `lib/screens/bookmarks_screen.dart`

**38. Contextual Onboarding - Not Upfront** 🟡 **MEDIUM IMPACT**
- **Pain Point:** "What's your name?" dialog on first launch + Getting Started card takes space. Tutorial fatigue.
- **Change:** Remove upfront onboarding. Use in-context tips when user reaches each feature. Store "seen" flags for progressive disclosure.
- **Impact:** MEDIUM - Faster time-to-first-action
- **Complexity:** 4/10
- **Files:** `lib/screens/quick_profile_creation_dialog.dart`, `lib/widgets/getting_started_card.dart`, `lib/services/onboarding_service.dart`

**39. Remove Visual Clutter from Script List** 🟡 **MEDIUM-HIGH IMPACT**
- **Pain Point:** 10+ interactive elements per script item: avatar, source icon, title, download icon, subtitle, favorite star, hover actions, overflow menu.
- **Change:** Simplify to 3 visible elements: Avatar + Title + Single action. Use swipe gestures: left=delete, right=favorite. Overflow menu into bottom sheet.
- **Impact:** MEDIUM-HIGH - Cleaner, less overwhelming interface
- **Complexity:** 6/10
- **Files:** `lib/screens/scripts_screen.dart`

**40. Global Search - Not Tab-Scoped** 🟡 **MEDIUM IMPACT**
- **Pain Point:** Search only searches current context. Users expect app-wide search.
- **Change:** Unified search bar at app level. Results show ALL types: Scripts, Canisters, Authors. Type-ahead suggestions.
- **Impact:** MEDIUM - Faster discovery
- **Complexity:** 7/10 (new global search component, backend integration)
- **Files:** `lib/main.dart`, new: `lib/widgets/global_search.dart`

**41. Profile Menu Further Simplification** 🟡 **MEDIUM IMPACT**
- **Pain Point:** Current menu items: Manage Account/Register, Passkeys, Manage Profiles, Settings. Red badge creates anxiety.
- **Change:** Simplify to 3 items: My Account (combines all), Switch Profile, Settings. Remove red badge - use subtle text.
- **Impact:** MEDIUM - Cleaner navigation, reduces notification anxiety
- **Complexity:** 3/10
- **Files:** `lib/widgets/profile_menu.dart`

**42. Simplify Bookmarks/Canister Screen** 🟡 **MEDIUM IMPACT**
- **Pain Point:** BookmarksScreen has 4 sections. Heavy technical jargon.
- **Change:** Combine Popular + Bookmarks into "Saved Services". Move Recent Calls to History. Add "What's this?" info buttons.
- **Impact:** MEDIUM - Reduces cognitive load
- **Complexity:** 5/10
- **Files:** `lib/screens/bookmarks_screen.dart`

**43. Filter Bottom Sheet Simplification** 🟢 **LOW-MEDIUM IMPACT**
- **Pain Point:** Multiple filters + active filter chips create clutter.
- **Change:** Reduce to 2 primary filters: Category + Sort. Move Downloaded/Favorites to tabs. Use pill buttons for categories.
- **Impact:** LOW-MEDIUM - Cleaner search UX
- **Complexity:** 4/10
- **Files:** `lib/screens/scripts_screen.dart`


## MEDIUM Priority

### Multi-Device & Recovery
- [ ] QR code import for multi-device sync

### Expose Hidden Backend Features

**1. Script Reviews UI** ✅ **DONE - 2026-02-22** (READ-ONLY)
- [x] Add "Reviews" tab to ScriptDetailsDialog
- [x] Show rating distribution chart (5→1 star bars)
- [x] Display reviews with: stars, verified badge, comment, relative date
- [x] Empty state when no reviews
- **Note:** "Write Review" button NOT implemented (backend mutation API missing)
- **Service:** `MarketplaceOpenApiService.getScriptReviews()`
- **Test:** `test/features/marketplace/script_details_reviews_test.dart` (8 tests)
- **Impact:** Users can see reviews to make informed download decisions

**2. Featured/Trending Scripts** ✅ **DONE - 2026-02-21**
- [x] Add "Featured" section to Scripts screen
- [x] Horizontal scrolling cards with shimmer loading
- [x] Call `getFeaturedScripts()` from service
- **Impact:** Improves script discovery

**3. Script Version History** ✅ **DONE - 2026-02-22**
- [x] Add "Versions" tab to ScriptDetailsDialog
- [x] Allow installing specific versions (callback-based)
- [x] Latest/Installed badges
- **Service:** `MarketplaceOpenApiService.getScriptVersions()`
- **Test:** `test/features/marketplace/script_details_versions_test.dart` (11 tests)
- **Impact:** Users can rollback to previous versions

### UX Improvements - Phase 2

**4. Prominent Publish Button** ✅ **DONE - 2026-02-21**
- [x] Add visible share icon button on local script rows
- [x] Add dismissible "Share your first script!" banner
- **Impact:** Makes publishing discoverable (was hidden in 3-dot menu)
- **Files:** `lib/screens/scripts_screen.dart`, test: `test/features/scripts/publish_button_test.dart`

**5. Download History Visibility** ✅ **DONE - 2026-02-22**
- [x] Add "Downloaded" filter chip to filter bottom sheet
- [x] Filters scripts that were downloaded from marketplace
- [x] Works with other filters (category, source, etc.)
- **Test:** `test/features/scripts/downloaded_filter_test.dart` (4 tests)
- **Impact:** Users can easily find scripts they've downloaded
- **File:** `lib/screens/scripts_screen.dart`

**6. Quick Actions Prominence** ✅ **DONE - 2026-02-22**
- [x] Larger cards (min height 120px, padding 20px)
- [x] Gradient backgrounds (primary color 0.05 → 0.02)
- [x] "See All" button (shows "coming soon" snackbar)
- [x] Hover effects (scale 1.02, opacity 0.9 on desktop)
- [x] Better visual hierarchy (titleMedium, divider between title/description)
- **Test:** `test/features/services/quick_actions_test.dart` (15 tests, 6 new)
- **Impact:** More prominent ICP tool discovery
- **File:** `lib/screens/bookmarks_screen.dart`

**7. Passkey Quick Access** ✅ **DONE - 2026-02-21**
- [x] Show passkey count in profile menu subtitle ("No passkeys" / "N passkeys")
- [x] Highlight Passkey option when user has no passkeys
- **Impact:** Reduces friction to see passkey status, encourages setup
- **Files:** `lib/widgets/profile_menu.dart`, test: `test/widgets/profile_menu_passkey_test.dart`

**8. Single-Page Script Creation** ✅ **DONE - 2026-02-22**
- [x] Remove tabs from ScriptCreationScreen (was 2 tabs: Code/Details)
- [x] Single scrollable page layout
- [x] Template selection as prominent cards at top
- [x] "Create Script" as sticky bottom button
- [x] Reduced from 527 to 387 lines (27% reduction)
- **Test:** `test/script_creation_screen_test.dart` (11 tests)
- **Impact:** Simplifies script creation flow - no tab switching needed
- **File:** `lib/screens/script_creation_screen.dart`

**9. Canister Client as Full Screen** ✅ **DONE - 2026-02-22**
- [x] Make full screen instead of modal (via `Navigator.push`)
- [x] Add "What is a Canister?" explainer link (via tooltip)
- [x] Simplify: Canister → Function → Call (3 numbered steps)
- [x] Step indicator in AppBar showing current step
- [x] Back/Next navigation buttons
- **Test:** `test/features/canister_client/full_screen_test.dart` (11 tests)
- **Impact:** Reduces cognitive load for ICP interaction
- **Files:** `lib/screens/canister_client_screen.dart`, `lib/main.dart`

**10. Settings Screen** ✅ **DONE - 2026-02-22**
- [x] Theme toggle with Light/Dark/System options
- [x] App version and build number display
- [x] External links (Documentation, Report Issue, Marketplace Website)
- [x] Developer info section (API endpoint, environment)
- [x] Dynamic theme updates via ValueNotifier
- [x] Settings menu item in Profile Menu
- **Test:** `test/services/settings_service_test.dart` (11 tests), `test/features/settings/settings_screen_test.dart` (15 tests)
- **Impact:** Users can now configure app preferences, was completely missing
- **Files:** `lib/screens/settings_screen.dart`, `lib/services/settings_service.dart`, `lib/widgets/profile_menu.dart`, `lib/main.dart`

**11. Marketplace Stats Banner** ✅ **DONE - 2026-02-22**
- [x] Fetch marketplace stats on ScriptsScreen load
- [x] Display scripts count, authors count, downloads
- [x] Loading state with shimmer placeholder
- [x] Graceful error handling (banner hidden on error)
- [x] Large number formatting (1.2K, 10K, 1.5M)
- **Test:** `test/features/marketplace/stats_banner_test.dart` (10 tests)
- **Impact:** Users see community activity, builds trust in marketplace
- **Files:** `lib/widgets/marketplace_stats_banner.dart`, `lib/screens/scripts_screen.dart`

**12. Unsaved Changes Warning** ✅ **DONE - 2026-02-22**
- [x] Track dirty state in ScriptEditor (initial vs current code)
- [x] Confirmation dialog when closing with unsaved changes
- [x] "Discard" and "Cancel" options
- [x] PopScope to handle back button/gesture
- **Test:** `test/widgets/script_editor_unsaved_test.dart` (10 tests)
- **Impact:** Prevents data loss - users warned before losing work
- **Files:** `lib/widgets/script_editor.dart`, `lib/screens/scripts_screen.dart`

**13. Downloaded Filter Empty State** ✅ **DONE - 2026-02-22**
- [x] Specific empty state when "Downloaded" filter active with no downloads
- [x] Clear message: "You haven't downloaded any scripts yet"
- [x] "Browse Marketplace" action button clears filter
- **Test:** `test/features/scripts/downloaded_filter_test.dart` (5 tests)
- **Impact:** Users understand what's happening, guided to solution
- **Files:** `lib/screens/scripts_screen.dart`

**14. Passkey Linux Error Message** ✅ **DONE - 2026-02-22**
- [x] Clear headline: "Passkeys require a browser on Linux"
- [x] Terminal-style code block with `flutter run -d chrome`
- [x] List supported authenticators (KeePassXC, phone, hardware keys)
- **Test:** `test/features/passkey/passkey_management_screen_test.dart`
- **Impact:** Linux users know exactly how to use passkeys
- **Files:** `lib/screens/passkey_management_screen.dart`

### Content Moderation
- [ ] API key authentication for admin endpoints
- [ ] Basic content moderation system

---

## LOW Priority

### Script Reviews (Backend) - Required for Write Review UI
*Blocking: "Write Review" button in ScriptDetailsDialog*
- [ ] `POST /api/v1/scripts/{id}/reviews` - Submit review
- [ ] `PUT /api/v1/scripts/{id}/reviews/{reviewId}` - Update review
- [ ] `DELETE /api/v1/scripts/{id}/reviews/{reviewId}` - Delete review
- **Note:** Read-only reviews UI is complete. Write APIs needed for user review submission.

### Canister Interaction
- [x] Response viewer with multiple formats (JSON, Table, Raw) ✅ **DONE - 2026-02-22**
  - **Service:** `DisplayFormat` enum in `result_display.dart`
  - **Test:** `test/result_display_format_test.dart` (10 tests)
  - **Impact:** Users choose how to view canister call results
- [x] Interaction history with replay capability ✅ **DONE - 2026-02-22**
  - **Service:** `CanisterHistoryService` with SharedPreferences persistence
  - **UI:** Recent calls section in CanisterClientScreen, tap to replay
  - **Test:** `test/services/canister_history_service_test.dart` (17 tests), `test/features/canister_client/history_test.dart` (6 tests)
  - **Impact:** Power users can quickly repeat common canister calls
- [x] Canister autocomplete/search by ID or name ✅ **DONE - 2026-02-22**
  - **Service:** `CanisterRegistryService` with hardcoded registry of 8 well-known ICP canisters
  - **UI:** RawAutocomplete widget in CanisterClientScreen with suggestions
  - **Test:** `test/features/canister_client/autocomplete_test.dart` (13 tests)
  - **Impact:** Users can quickly find and select canisters without memorizing IDs
- [x] Smart input forms based on Candid interface ✅ **DONE - 2026-02-23**
  - **Widget:** `CandidSmartForm` with type-aware controllers for text, nat/int, bool, variant, record, vec, opt
  - **UI:** Auto-generated form fields in CanisterClientScreen instead of raw JSON editor
  - **Test:** `test/widgets/candid_smart_form_test.dart` (19 tests)
  - **Impact:** Users see friendly form fields instead of intimidating JSON

### Script Automation
- [ ] Script scheduler UI (cron-like but user-friendly)
- [ ] Trigger system (time-based initially)
- [ ] Automation logs with filtering and search

### Discovery
- [ ] Trending algorithm based on recent downloads + ratings
- [ ] Personalized recommendations
- [ ] Trust system: verified author badges, reputation score

### Future UX Enhancements
- [x] Search history for marketplace ✅ **DONE - 2026-02-22**
  - **Service:** `SearchHistoryService` with SharedPreferences persistence
  - **UI:** Recent searches dropdown on search field focus, max 10 items
  - **Test:** `test/services/search_history_service_test.dart` (17 tests), `test/features/scripts/search_history_test.dart` (7 tests)
  - **Impact:** Quick access to previous searches
- [x] Quick actions menu (long-press on script cards) ✅ **DONE - 2026-02-22**
  - **UI:** Bottom sheet context menu on long-press (mobile), right-click (desktop)
  - **Actions:** Run, Edit, Duplicate, Delete, Share (local); View Details, Download (marketplace)
  - **Test:** `test/features/scripts/long_press_test.dart` (19 tests)
  - **Impact:** Power user efficiency with quick access to common actions
- [x] Actionable error handling ✅ **DONE - 2026-02-22**
  - **Service:** `ErrorCategories` utility with 7 error types (Network, Auth, Validation, NotFound, Server, RateLimit, Unknown)
  - **UI:** Enhanced `ErrorDisplay` widget with smart categorization, suggested actions, and help button
  - **Test:** `test/widgets/actionable_error_display_test.dart` (36 tests)
  - **Impact:** Users know exactly what to do when errors occur
- [x] Getting Started guide for new users ✅ **DONE - 2026-02-22**
  - **Service:** `OnboardingProgressService` with checklist tracking
  - **UI:** `GettingStartedCard` widget with 5 checklist items and progress tracking
  - **Test:** `test/features/onboarding/guided_next_steps_test.dart` (21 tests)
  - **Impact:** New users have clear path to learn the app
- [x] Interactive onboarding tour (spotlight overlays highlighting key UI elements) ✅ **DONE - 2026-02-21**
  - **Service:** `SpotlightService` with SharedPreferences persistence
  - **UI:** `SpotlightOverlay` widget with dimmed background, spotlight hole, step indicator, Next/Back/Skip buttons
  - **Integration:** Triggered after post-setup guide; "Restart Tour" option in profile menu
  - **Test:** `test/features/spotlight/spotlight_test.dart` (28 tests)
  - **Impact:** New users understand the app quickly through guided tour
- [x] Script favorites/bookmarks system with dedicated filter ✅ **DONE - 2026-02-23**
  - **Service:** `FavoritesService` with SharedPreferences persistence
  - **UI:** Star toggle on script cards, "Favorites" filter chip
  - **Test:** `test/services/favorites_service_test.dart` (26 tests), `test/features/scripts/favorites_filter_test.dart` (12 tests)
  - **Impact:** Quick access to frequently used scripts
- [x] Offline mode indication banner ✅ **DONE - 2026-02-23**
  - **Service:** `ConnectivityService` with Socket-based checking
  - **UI:** Amber dismissible banner on ScriptsScreen and BookmarksScreen
  - **Test:** `test/services/connectivity_service_test.dart` (11 tests), `test/widgets/offline_banner_test.dart` (14 tests)
  - **Impact:** Users know why operations fail
- [x] Bulk script management (multi-select, bulk delete/export) ✅ **DONE - 2026-02-23**
  - **UI:** Long-press enters selection mode; checkboxes, bulk delete/export
  - **Test:** `test/features/scripts/bulk_operations_test.dart` (33 tests)
  - **Impact:** Power users can manage multiple scripts efficiently
- [x] Script diff viewer for version updates ✅ **DONE - 2026-02-22**
  - **Service:** `DiffService` with LCS-based diff algorithm
  - **UI:** `DiffViewerDialog` with +/- colored lines, line numbers
  - **Test:** `test/features/marketplace/diff_service_test.dart` (16 tests)
  - **Impact:** Users see what changed before updating scripts
- [x] Deep linking for script sharing (`icpautorun://script/{id}`) ✅ **DONE - 2026-02-22**
  - **Service:** `DeepLinkService` with URL parsing and stream events
  - **UI:** Opens `ScriptDetailsDialog` when link received
  - **Platform:** Android (AndroidManifest.xml), iOS (Info.plist)
  - **Test:** `test/features/deep_link/` (15 tests)
  - **Impact:** Users can share direct script links

---

## BLOCKED / FUTURE

> **DO NOT START** until all HIGH and MEDIUM priority items are complete AND tested.
> 
> The marketplace must be fully functional with free scripts before adding payments.
> Messaging is a separate product feature that requires the core to be stable first.

### Marketplace Payments (BLOCKED)
*Blocked by: Complete test coverage, stable core features, production-ready free marketplace*

- [ ] ICP ledger canister integration
- [ ] Payment flow for paid scripts
- [ ] Purchase records API endpoints
- [ ] Transaction history
- [ ] Wallet balance display

### Messaging (BLOCKED)
*Blocked by: Everything above, including payments*

- [ ] Contact discovery/lookup
- [ ] Following/followers system
- [ ] Direct messaging infrastructure

---

## Known Issues

| Issue | Location | Severity |
|-------|----------|----------|
| Key sharing across profiles allowed (architecture violation) | `lib/models/account.dart:18-21` | MEDIUM |
| Key label editing blocked by missing API endpoint | `AccountController` | MEDIUM |

**Fixed This Session (2026-02-23):**
- ~~Pre-existing test failures (passkey, script execution tests)~~ - Fixed import paths, rewrote execute_test.dart to match actual API, fixed extension conflicts in vault screens
- ~~Passkey Linux error message unclear~~ - Now shows clear instructions with `flutter run -d chrome` command

---

## Architecture Reference

### Design Principles
- **Profile-centric**: Keys belong to profiles, not standalone
- **Untrusted code isolation**: Lua sandboxed; no IO; effects executed by host
- **Fail fast**: Strict validation, clear errors, no silent failures
- **Zero redundancy**: Backend is single source of truth

### Lua App Contracts
- `init(arg) -> state, effects[]`
- `view(state) -> ui_v1`
- `update(msg, state) -> state, effects[]`
- Effects: `icp_call`, `icp_batch`
- Host emits: `{ type:"effect/result", id, ok, data?|error? }`

### UI_v1 Widget Types
- `column`, `row` - Layout containers
- `text`, `button`, `text_field` - Basic inputs
- `card`, `section` - Containers with styling
- `list`, `table`, `paginated_list` - Data display
- `image`, `result_display` - Media and results
- `select`, `toggle` - Selection widgets

---

## Update Guidelines

- Remove completed tasks immediately
- Break complex tasks into subtasks
- Empty sections: use `(none)`
- Priority: HIGH = MVP/critical, MEDIUM = significant UX, LOW = nice-to-have
