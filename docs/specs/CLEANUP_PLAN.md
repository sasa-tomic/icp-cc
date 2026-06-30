# ICP-CC Cleanup & Lua Sunset Plan

- **Status:** Authoritative — Ready for Execution
- **Date:** 2026-06-30
- **Scope:** (1) Full Lua sunset → TypeScript/QuickJS-only runtime; (2) Wholesale legacy cruft cleanup
- **Authoritative spec basis:** `docs/specs/SCRIPTING_RUNTIME_MIGRATION.md` Phases 0–2 (done); this plan delivers **Phase 4 (Lua sunset)** + Objective 2 (cruft).
- **Baseline:** `cargo nextest run -p icp_core` → 121/121 pass; `cargo build -p icp_core` → green; Flutter + Dart on PATH; remote `origin` present.

---

## Section 1 — Executive Summary

### What we are doing
1. **Remove the entire Lua runtime** (`mlua` + `lua_engine.rs` + `icp_lua_*` FFI + Dart lua symbols + dual-routing logic + Lua examples + Lua UI scaffolding) so that **TypeScript/QuickJS is the single scripting runtime**.
2. **Rename the misnamed `lua_source`/`luaSource` data field → `bundle`** across the full stack (Rust FFI already uses `js_*`; backend DB column + API + signature payload; Dart models + API client). This is a **coordinated, contract-breaking change**.
3. **Slash legacy cruft**: the 1,224-line historical `TODO.md`, stale root docs, superseded specs, dead/zombie code, and the `ScriptLanguage` abstraction that only existed to support dual runtime.

### Why
- The TS runtime (Phase 2) is hardened, parity-verified, and ships with a real-QuickJS test harness. The Lua runtime is now pure legacy dead weight (~3,500 LOC across Rust + Dart + tests + examples).
- Greenfield project → **no backward compatibility**. Carrying a dual-runtime abstraction (`ScriptLanguage` enum, `detectLanguage`, language toggles, `_injectHelpers`) for a runtime we no longer ship is unacceptable complexity.
- `lua_source` as a field name holding TS bundles is actively misleading and blocks clean AI/human authoring.

### Success criteria
- [ ] `cargo nextest run -p icp_core` green with **zero** Lua references in `crates/`.
- [ ] `cd apps/autorun_flutter && flutter analyze` clean (0 warnings).
- [ ] `cd apps/autorun_flutter && flutter test` green.
- [ ] No `lua`/`Lua`/`mlua`/`lua_source`/`luaSource`/`ScriptLanguage`/`detectLanguage` strings remain in `lib/`, `crates/`, or `backend/` (except inside this plan + migration doc history).
- [ ] `just test-feature scripts` and `just test-feature marketplace` pass end-to-end.
- [ ] A TS bundle can be authored → saved → uploaded → downloaded → executed through the full app flow.
- [ ] `TODO.md` reduced to a focused current-state doc (<150 lines).
- [ ] No dead/zombie code; no stale dated spec docs.

### Key architectural flag (HUMAN DECISION REQUIRED — see Risk Register R-1)
The `lua_source` field is part of the **cryptographic signature payload** (`backend/src/middleware/auth.rs:72`). Renaming it breaks every existing script signature. Greenfield = acceptable, but the rename must be **atomic across backend + client + DB**. If the human prefers to defer the rename and keep `lua_source` as a stable wire name (purely cosmetic debt), **WU-7 can be dropped** and the rest of the plan still stands. **Default plan assumes the rename is wanted** per the task brief.

---

## Section 2 — Work Units

Each WU is independently committable and leaves the build GREEN. Order follows dependency chain.

---

### WU-1 — Rust: Remove Lua engine, `mlua`, `icp_lua_*` FFI, ungate JS FFI
**Complexity:** Medium · **Dependencies:** none · **Risk:** Low

The Lua engine module is entirely `#[cfg(not(target_arch = "wasm32"))]`-gated and self-contained. Removing it is a clean excision.

**Files & exact changes:**

1. **`crates/icp_core/src/lua_engine.rs`** — **DELETE entire file** (2,225 lines; lines 1–80 host code, 1006–2225 inline `mod tests` with ~24 Lua-only tests + helper tests).

2. **`crates/icp_core/src/lib.rs`**:
   - Remove lines 9–11: `#[cfg(not(target_arch = "wasm32"))]` + `pub mod lua_engine;`
   - Remove lines 29–33: the `#[cfg(not(target_arch = "wasm32"))]` + `pub use lua_engine::{execute_lua_json, lint_lua, validate_lua_comprehensive, LuaExecError, ValidationContext, ValidationResult};` block.

3. **`crates/icp_core/src/ffi.rs`**:
   - Line 3: remove `lua_engine,` from the `use crate::{...}` import; line 6: remove `ValidationContext,` (keep `JsValidationContext`).
   - **DELETE lines 310–444** — the entire Lua FFI block: section comment `// ---- Lua scripting FFI ----` (310), `icp_lua_exec` (315–335), `icp_lua_lint` (341–348), `icp_lua_validate_comprehensive` (355–383), `// ---- TEA-style Lua app FFI ----` (385), `icp_lua_app_init` (390–406), `icp_lua_app_view` (412–424), `icp_lua_app_update` (430–444).
   - **Ungate the JS FFI symbols**: remove the `#[cfg(not(target_arch = "wasm32"))]` attribute (line 454) preceding `icp_js_exec`, and the same attribute before `icp_js_lint` (481), `icp_js_validate_comprehensive` (496), `icp_js_app_init` (531), `icp_js_app_view` (554), `icp_js_app_update` (573). Update the section comment at 446–449: the `rquickjs` constraint still holds (it also can't target wasm32), so **keep the `#[cfg(not(target_arch = "wasm32"))]` gates on JS FFI** — only the Lua gates vanish. **Correction:** verify `rquickjs` compiles to wasm32; if not (it doesn't — vendored C), **leave the JS `#[cfg]` gates in place** and just delete the Lua block. The existing comment at 446–449 stays accurate.

4. **`crates/icp_core/Cargo.toml`**:
   - Line 56: remove `mlua = { version = "0.11", features = ["lua54", "vendored", "serde", "send"] }`.
   - Lines 51–55: remove the mlua explanatory comment block (`# Embedded Lua interpreter...` through `- send: ...`).
   - Line 46 comment: trim `# - mlua: vendored Lua 5.4 C source cannot be compiled to wasm32` from the native-only-deps note.

5. **`crates/icp_core/src/wasm_exports.rs`** — lines 8–11: the stale comment `// Lua wasm exports (...) were removed: ... The Lua engine is being sunset.` is now historical. **Delete lines 8–11**; the wasm file is JS-only and self-explanatory.

6. **`crates/icp_core/tests/parity_vectors.rs`** — **collapse to JS-only**:
   - Line 5: remove `, lua_engine` from `use icp_core::{execute_js_json, lua_engine, SDK_CONTRACT_VERSION};`.
   - Lines 27–30: remove the `expected_lua` and its `#[allow(dead_code)]` field from `struct Case`.
   - **DELETE lines 69–89** (`fn run_helper_in_lua`).
   - Lines 100–129 (`all_helpers_match_golden_vectors`): remove the `expected_lua`/`lua_actual` block (109–114 canonicalize expected_lua, 123–128 lua assert). Keep only the JS assertion path.

7. **`crates/icp_core/benches/runtime.rs`**:
   - Line 3: change `use icp_core::{execute_js_json, execute_lua_json, js_app_init, js_app_update, js_app_view, lua_engine,};` → drop `execute_lua_json` and `lua_engine`.
   - **DELETE `LUA_COUNTER` const** (lines 28–52) and `LUA_ALL_HELPERS` (line 56).
   - In `bench_cold_start` (60–74): delete `lua_execute` benchmark function (70–73).
   - In `bench_helpers_throughput` (76–84): delete `lua_all_16` (81–83).
   - In `bench_lifecycle_roundtrip` (80–110): delete the `lua_init_view_update` benchmark (96–108).

**Verification:**
```bash
cargo build -p icp_core 2>&1 | tail -3          # must finish, no errors
cargo nextest run -p icp_core 2>&1 | tail -5    # was 121 → expect ~96 (Lua inline tests + parity lua half gone)
cargo clippy -p icp_core --all-targets -- -D warnings 2>&1 | tail -3
cargo bench --bench runtime --no-run            # bench compiles
```

**Estimated delta:** −2,225 (lua_engine) −~80 (ffi) −~50 (parity/benches) ≈ **−2,350 lines**.

---

### WU-2 — Dart FFI: Remove `icp_lua_*` symbols, rename shared typedefs
**Complexity:** Medium · **Dependencies:** WU-1 · **Risk:** Medium (FFI symbol mismatch = runtime lookup crash)

**File:** `apps/autorun_flutter/lib/rust/native_bridge.dart`

**Exact changes:**
- `_Symbols` class (lines 15–21): **delete** `luaExec`, `luaLint`, `luaValidateComprehensive`, `luaAppInit`, `luaAppView`, `luaAppUpdate` constants.
- `RustBridgeLoader`:
  - **DELETE** `luaExec` (297–317), `luaLint` (319–337), `validateLuaComprehensive` (339–369), `luaAppInit` (372–393), `luaAppView` (395–415), `luaAppUpdate` (417–441). Also the section comments `// ---- Lua scripting FFI ----` (310) and `// ---- TEA-style Lua app ----` (371).
  - The `jsAppInit`/`jsAppView`/`jsAppUpdate`/`validateJsComprehensive` methods currently **reuse** the `_LuaApp*Native`/`_LuaValidateComprehensiveNative` typedefs (lines 496, 526, 548, 574). **RENAME** those typedefs (not delete) to engine-neutral names since JS uses them.
- `NativeBridge` wrapper class (662–712): **DELETE** `validateLuaComprehensive` (666–679), `luaExec` (682–684), `luaLint` (686–688). Keep `validateJsComprehensive` (690), `jsExec` (705), `jsLint` (709).
- **Typedefs (rename, do not delete — JS still uses them):**
  - `_LuaValidateComprehensiveNative`/`_LuaValidateComprehensiveDart` (744–755) → rename to `_ValidateComprehensiveNative`/`_ValidateComprehensiveDart` (or `_JsValidateComprehensive*`).
  - `_LuaAppInitNative`/`_LuaAppInitDart` (790–795), `_LuaAppViewNative`/`_LuaAppViewDart` (800–805), `_LuaAppUpdateNative`/`_LuaAppUpdateDart` (810–816) → rename to `_AppInit*`/`_AppView*`/`_AppUpdate*`.
  - Update the `lib.lookupFunction<...>` call sites in the JS methods to the new typedef names.
  - Line 789 comment `// Lua app FFI typedefs` → `// App lifecycle FFI typedefs`.

**Verification:**
```bash
cd apps/autorun_flutter && flutter analyze lib/rust/native_bridge.dart
cd apps/autorun_flutter && flutter test test/native_bridge_js_smoke_test.dart
```
Note: this WU leaves callers of the removed lua methods (script_runner, script_editor, script_validation_service) temporarily broken — they are fixed in WU-3/WU-5. To keep this WU independently green, either (a) merge WU-2 into WU-3, or (b) do WU-2 as pure symbol removal and accept that `flutter analyze` on the full `lib/` goes red until WU-3. **Recommended: execute WU-2 + WU-3 + WU-5 as one commit sequence** (the Dart-side engine removal is one cohesive change).

**Estimated delta:** −~200 lines.

---

### WU-3 — Dart runtime: collapse `script_runner.dart`, delete `language_detector.dart`, remove `ScriptLanguage`
**Complexity:** Complex · **Dependencies:** WU-2 · **Risk:** High (touches models, controllers, screens, tests)

TS-only means **no language abstraction at all**. The `ScriptLanguage` enum, `detectLanguage`, `language` fields, dual routing, and `_injectHelpers` (Lua preamble injection) are all dead.

**Files & exact changes:**

1. **`apps/autorun_flutter/lib/services/language_detector.dart`** — **DELETE entire file** (54 lines). It existed solely to route the dual runtime.

2. **`apps/autorun_flutter/lib/services/script_runner.dart`** (910 lines):
   - **DELETE** `enum ScriptLanguage { lua, typescript }` (line 9).
   - `IntegrationInfo` (11–23): field comment `final String example; // Minimal Lua snippet example` → `// Minimal TypeScript snippet`. (Examples rewritten to TS in WU-4.)
   - `CanisterCallSpec` (25–59): comment line 38 `/// Logical name to expose this call's JSON output under in the Lua arg` → `... under the bundle arg`. Comment line 49 `/// 2. privateKeyB64: ... (legacy)` — note "legacy" stays accurate.
   - `ScriptRunPlan` (61–77): **rename** field `luaSource` → `bundle` (field 69 + constructor param 64); **delete** `language` field (76) + constructor default `this.language = ScriptLanguage.lua` (66). (Field rename rides WU-7's coordinated rename; if WU-7 deferred, keep `luaSource` here and document. **Default: rename in lockstep with WU-7 — sequence this WU immediately before WU-7.**)
   - `ScriptBridge` abstract (87–129): **DELETE** all lua methods: `luaExec` (105), `luaLint` (106), `luaAppInit` (109), `luaAppView` (110–112), `luaAppUpdate` (113–116). Delete the comment `// TEA-style app` (108) and `// QuickJS (TypeScript) equivalents — self-contained bundles (no helper injection).` (118) → just `// Script app lifecycle (TS/QuickJS bundles).`
   - `RustScriptBridge` (131–241): **DELETE** the 6 `@override` lua method impls (168–203).
   - `ScriptRunner.run` (380–631): at lines 434–448, **remove the dual routing** — `isTypescript` branching, `_injectHelpers(plan.luaSource)` injection, the `luaExec`/`jsExec` ternary. The TS bundle is self-contained (no helper injection — that's the whole point of QuickJS bundles). Body becomes: validate `bundle` non-empty → call `_bridge.jsExec(script: plan.bundle, jsonArg: jsonArg)`. Update error strings ("Lua execution returned empty" → "JS execution returned empty", line 456 "Lua error" → "Script error", line 628 "Invalid Lua output" → "Invalid script output"). Update comment line 378 `/// Execute the plan: call canisters in order, build arg, run Lua.` → `... run the TS bundle.`
   - **DELETE** `_injectHelpers` method entirely (796–816) — Lua-only preamble, obsolete.
   - `ScriptAppRuntime` (835–909): **delete** `language` field (838) + constructor param `this.language = ScriptLanguage.lua` (836). In `init`/`view`/`update` (845–908): **delete the lua/js ternaries** — call `_bridge.jsAppInit/View/Update` directly. Comment line 834 `/// Runtime host for TEA-style Lua app` → `/// Runtime host for TS app (init/view/update + effects).`
   - `integrationCatalog` (252–332): examples are Lua strings — rewritten to TS in WU-4. Field comment line 250 `/// Catalog of integrations available to Lua scripts.` → `... available to TS scripts.`

3. **`apps/autorun_flutter/lib/models/script_record.dart`**:
   - Remove `import '../services/language_detector.dart';` (line 3).
   - Constructor (7–20): **delete** `this.language = ScriptLanguage.lua,` (line 18) + the `language` field declaration (line 32).
   - Field `luaSource` (12, 26) → `bundle` (coordinated with WU-7). JSON keys `'luaSource'` (52, 68) → `'bundle'`. **Note:** this is the LOCAL storage serialization — safe to rename independently of backend.
   - `copyWith` (88–112): drop `language` param (97, 110), rename `luaSource` param.

4. **`apps/autorun_flutter/lib/models/marketplace_script.dart`**:
   - Remove `import '../services/language_detector.dart';` (line 3).
   - Field `luaSource` (23) → `bundle`. Field `language` (33) → **delete**.
   - Constructor: drop `this.language = ScriptLanguage.lua` default (62), rename `required this.luaSource` (52) → `required this.bundle`.
   - `fromJson`: `json['luaSource'] ?? json['lua_source']` (134–135) → `json['bundle']` (single key, post-WU-7). Delete `language: scriptLanguageFromJson(json['language'])` (156).
   - `toJson`: `'luaSource': luaSource` (175) → `'bundle': bundle`. Delete `'language': scriptLanguageToJson(language)` (185).
   - `copyWith`: drop `language` param (213, 239), rename `luaSource`.
   - **API contract note:** `lua_source`/`luaSource` are the BACKEND WIRE names — changing them here must match WU-7's backend rename. Sequence together.

5. **`apps/autorun_flutter/lib/models/script_template.dart`** (241 lines):
   - Remove `import '../services/script_runner.dart';` (line 5) — only used for `ScriptLanguage`.
   - Field `_filePath` comment (14) `// Path to the actual Lua file` → `// Path to the bundle asset`. Field `_initialLuaSource` (18) → `_initialBundle`; `_cachedLuaSource` (19) → `_cachedBundle`.
   - Constructor (21–37): rename `preloadedLuaSource` param → `preloadedBundle`; delete `this.language = ScriptLanguage.lua` (31); update the `assert` (34–37).
   - Getter `luaSource` (41–50) → `bundle`; update error message text "Lua source for template" → "Bundle for template".
   - `load` (53–80): rename `_cachedLuaSource`/`_initialLuaSource` refs; update error messages ("Lua source loaded from" → "Bundle loaded from").
   - `operator ==` / `hashCode` (82–109): drop `language` from comparison/hash; rename `_initialLuaSource`.
   - `ScriptTemplates._loadTemplates` (133–196): **DELETE the 4 Lua template entries** (`hello_world` 135, `data_management` 146, `icp_demo` 157, `advanced_ui` 168). **KEEP + EXPAND** the `typescript_counter` entry (179) and add new TS templates (WU-4 supplies new `.js` asset files). All template descriptions currently say "Lua" — rewrite.

**Verification:**
```bash
cd apps/autorun_flutter && flutter analyze
cd apps/autorun_flutter && flutter test test/script_runner_js_path_test.dart test/script_record_test.dart
```

**Estimated delta:** −~250 lines net (enum, detector file, helper injection, dual-routing branches).

---

### WU-4 — Dart content: Lua examples → TS, rewrite `kDefaultSampleLua`, fix UI scaffolding
**Complexity:** Medium · **Dependencies:** WU-3 · **Risk:** Medium (lost example coverage)

**Files & exact changes:**

1. **`apps/autorun_flutter/lib/examples/`**:
   - **DELETE** `01_hello_world.lua`, `02_simple_data.lua`, `03_simple_icp_demo.lua`, `04_advanced_ui_refactored.lua` (the 4 Lua assets).
   - **KEEP** `05_typescript_counter.js`.
   - **ADD** TS-authored replacements that produce IIFE bundles: `01_hello_world.js`, `02_data_management.js`, `03_icp_demo.js`, `04_advanced_ui.js` (port the Lua demos to the SDK `register({...})` pattern used by `05_typescript_counter.js` + `packages/marketplace-sdk/samples/pilot-sample.ts`). These must be **pre-bundled IIFE** (matching the runtime contract — bundles are self-contained). Verify each loads via `js_app_init`.

2. **`apps/autorun_flutter/lib/controllers/script_controller.dart`**:
   - **DELETE the `kDefaultSampleLua` const** (lines 13–160, ~148 lines of Lua source). **REPLACE** with a TS default bundle — port the same UI demo (counter, name/email form, toggle, select, image, load_sample batch) to a TS IIFE. Name it `kDefaultSampleBundle`. Comment line 11 → "Default sample TS app demonstrating UI widgets, forms, and canister calls."
   - `createScript` (206–255): rename `luaSourceOverride` param → `bundleOverride` (210, 231–233, 242); delete `language` param (212) + `final ScriptLanguage lang = language ?? detectLanguage(defaultLua);` (234–235) + `language: lang` (246).
   - `updateSource` (263–281): rename `luaSource` param → `bundle` (264, 274).

3. **`apps/autorun_flutter/lib/widgets/ui_component_palette.dart`** (408 lines):
   - Field `luaTemplate` (13, 20) → `template` (or `bundleSnippet`). Every component's `luaTemplate:` value is a Lua table literal — **rewrite all to TS object literals** matching the SDK UI node schema (e.g. `{ type: "column", children: [...] }`). This is a full pass through all ~20 `UiComponent` entries (25–408).

4. **`apps/autorun_flutter/lib/widgets/canister_call_builder.dart`**:
   - Method `_generateLuaCode` (153) → `_generateBundle` (or `_generateSnippet`); rewrite body to emit TS instead of Lua (line 8 doc comment "generate Lua code" → "generate a TS code snippet"). Update call sites (212–213, 489, 505–512): rename + update SnackBar text `'Lua code copied to clipboard!'` → `'Snippet copied to clipboard!'` (216), button `'Copy Lua'` → `'Copy Snippet'` (506), `'Insert Lua Code'` → `'Insert Snippet'` (510), preview header `// Generated Lua code preview` (476) → `// Generated TS snippet preview`.

5. **`apps/autorun_flutter/lib/widgets/integrations_help.dart`**:
   - Line 39 title `'Lua Helper Functions'` → `'SDK Helper Functions'`. Lines 26–32 local var `luaCode` → `snippet` (26, 30, 31, 32).

6. **`apps/autorun_flutter/lib/widgets/quick_upload_dialog.dart`**:
   - Line 113 string `'A Lua script with ${contentLines.length} main functions: ...'` → `'A TS script with ...'`.
   - Line 118 `'A Lua script for automation and utility tasks.'` → `'A TS script for automation and utility tasks.'`.
   - Line 127 `_tagsController.text = 'lua, script';` → `'typescript, script';`.
   - Method `_getLuaSource` (133) → `_getBundle`; rename `luaSource` locals (135, 239, 240, 242, 245, 247, 248, 281, 301, 607, 630, 638).
   - Line 630 `'This is the Lua code that will be uploaded...'` → `'This is the TS bundle...'`.
   - Line 640–642 `detectLanguage(luaSource) == ScriptLanguage.typescript ? 'typescript' : 'lua'` → just `'typescript'` (delete language detection; WU-3 already removed `detectLanguage`).

7. **`apps/autorun_flutter/lib/widgets/script_details_dialog.dart`**:
   - Lines 105–108: rename local `luaSource` → `bundle`.
   - Lines 431, 814: literal `'Lua'` labels (language badges) → **delete the badge entirely** (TS-only, no language to badge) or replace with a neutral `'TypeScript'` label.

8. **`apps/autorun_flutter/lib/screens/welcome_onboarding_screen.dart`**:
   - Line 208 `'Create and run Lua scripts that interact with ICP canisters'` → `'Create and run TypeScript scripts that interact with ICP canisters'`.
   - Line 244 `description: 'Create Lua scripts with our editor'` → `'Create TypeScript scripts with our editor'`.

9. **`apps/autorun_flutter/lib/services/spotlight_service.dart`**:
   - Line 44 `'Create, edit, and run Lua scripts here. ...'` → `'Create, edit, and run TypeScript scripts here. ...'`.

10. **`apps/autorun_flutter/lib/services/contextual_tip_service.dart`**:
    - Line 56 `'Write Lua code here and tap Run to execute. ...'` → `'Write TypeScript here and tap Run to execute. ...'`.

11. **`apps/autorun_flutter/lib/screens/script_creation_screen.dart`**:
    - Line 18: `preloadedLuaSource: '''-- Blank Script\n...` → a TS blank bundle.
    - Line 60: **DELETE** `ScriptLanguage _selectedLanguage = ScriptLanguage.lua;` field.
    - Lines 94, 113–114: `_selectedTemplate.luaSource` → `.bundle`; delete `_selectedLanguage = template.language;` (114).
    - Line 129 `_showError('Lua source cannot be empty');` → `'Bundle cannot be empty'`.
    - Lines 149–150: `luaSourceOverride: _currentCode, language: _selectedLanguage,` → `bundleOverride: _currentCode,`.
    - **DELETE the language dropdown** (lines 426–441, `DropdownButtonFormField<ScriptLanguage>` with Lua/TypeScript items) and the surrounding form row.
    - Lines 500–518: the `'TypeScript Source' : 'Lua Source'` ternary and `language:` param → fixed `'TypeScript Source'` label; delete `language:` arg.

12. **`apps/autorun_flutter/lib/screens/script_upload_screen.dart`**:
    - Lines 12, 16: `final String luaSource;` + `required this.luaSource,` → `bundle`.
    - Lines 215–256: the `defaultLuaSource` fallback that generates a `-- Default Script` Lua block → generate a TS default bundle. Lines 256, 272 `luaSource:` → `bundle:`.

13. **`apps/autorun_flutter/lib/screens/scripts_screen.dart`**:
    - Line 14: remove `import '../services/language_detector.dart';`.
    - Line 53: `ScriptAppRuntime(_bridge, language: r.language)` → `ScriptAppRuntime(_bridge)` (WU-3 removed the `language` param).
    - Lines 376–392: the `luaSource`/`detectLanguage`/`script.language == ScriptLanguage.typescript` block → use `record.bundle` directly; delete the language detection fallback.
    - Lines 477, 511, 683, 715, 1993, 2012, 2147, 2176, 2178, 2221: rename `luaSource` → `bundle`.
    - Lines 2149–2151: delete the `language: ... == typescript ? 'typescript' : 'lua'` arg.
    - Line 2450: `'Select a template to get started with your Lua script'` → `... TypeScript script'`.

**Verification:**
```bash
cd apps/autorun_flutter && flutter analyze
cd apps/autorun_flutter && flutter test test/features/scripts/ test/script_creation_screen_test.dart
just test-feature scripts
# Manually: launch app, create script from each template, execute → verify UI renders.
```

**Estimated delta:** −~160 (Lua const + Lua examples) +~200 (TS replacements) ≈ net small but high-touch.

---

### WU-5 — Dart validation: rewrite `script_validation_service.dart` + `script_editor` linter for TS
**Complexity:** Medium · **Dependencies:** WU-2 · **Risk:** Medium

**Files & exact changes:**

1. **`apps/autorun_flutter/lib/services/script_validation_service.dart`** (142 lines) — **near-total rewrite**:
   - Line 49 comment `// Use Rust validation only (mlua)` → `// Use Rust validation (rquickjs)`.
   - `_validateWithRust` (71–96): replace `rustBridge.validateLuaComprehensive(...)` (80) → `rustBridge.validateJsComprehensive(...)` (the JS wrapper already exists on `NativeBridge` at line 690 of native_bridge.dart). All Lua context detection stays structural (regexes for example/test comments — those are language-agnostic-ish, but the `--` Lua comment marker at 74–75 should become `//`).
   - `quickValidate` (100–141) — **currently pure Lua heuristics**. Rewrite for TS:
     - `loadstring(` (118) and `dofile(` (122) checks → **delete** (not JS concepts).
     - `while true do` + `break`/`return` loop check (127–131) → JS equivalent (`while (true)` without `break`/`return`).
     - `function $func` (110–114) for init/view/update → for TS bundles, the contract is the `register({...})` pattern or exported `init`/`view`/`update`. Update the check to match the TS bundle contract (consult `packages/marketplace-sdk/samples/pilot-sample.ts` + `05_typescript_counter.js`).

2. **`apps/autorun_flutter/lib/widgets/script_editor.dart`**:
   - Line 9: `import 'package:highlight/languages/lua.dart';` → **delete** (lua highlighter gone). Ensure `javascript` import exists (line 98 uses it).
   - Line 98: `language: widget.language == 'typescript' ? javascript : lua,` → `language: javascript,` (TS-only).
   - Line 142: `final String? out = (const RustBridgeLoader()).luaLint(script: code);` → `.jsLint(script: code);`. Verify `RustBridgeLoader.jsLint` exists (it does — native_bridge.dart line 466).
   - The `widget.language` field (the `'lua'|'typescript'` string param) on `ScriptEditor` — all call sites pass it; in WU-4 those become hardcoded `'typescript'`. **Delete the `language` field** from `ScriptEditor` entirely and remove the param from all constructors (search `language:` in screens/widgets that instantiate `ScriptEditor`).

**Verification:**
```bash
cd apps/autorun_flutter && flutter test test/services/ test/script_editor_test.dart test/widgets/syntax_highlighting_test.dart
```

**Estimated delta:** −~40 lines.

---

### WU-6 — Tests: drop Lua-only tests, fix dual-runtime tests, add TS coverage
**Complexity:** Medium · **Dependencies:** WU-3, WU-4, WU-5 · **Risk:** Low (test-only)

**DROP entirely (Lua-only / superseded):**
- `apps/autorun_flutter/test/lua_helpers_test.dart` — tests the Lua `_injectHelpers` preamble (deleted in WU-3). **DELETE.**
- `apps/autorun_flutter/test/services/language_detector_test.dart` — tests deleted `detectLanguage`. **DELETE.**

**REWRITE (dual-runtime → TS-only):**
- `test/script_runner_js_path_test.dart` — currently a `_RecordingBridge` that asserts lua-vs-js routing. Strip all `lua*` method stubs + the `isTypescript` branching assertions; keep JS-path coverage. Rename → `test/script_runner_test.dart` (collapses with existing file if overlapping — verify no duplication with `test/script_runner_test.dart` first; if overlapping, **merge and dedupe**).
- `test/features/scripts/execute_test.dart` (54 lua refs) — rewrite fixtures from Lua `function init/view/update` to TS bundles; remove language-detection assertions.
- `test/controllers/script_controller_language_test.dart` (17 refs) — the whole test exists to verify language detection/routing. **DELETE or repurpose** to verify the TS default bundle is created when no override given.
- `test/script_template_test.dart`, `test/script_template_loading_test.dart`, `test/script_template_syntax_test.dart`, `test/visual_template_picker_test.dart` (+ `.mocks.dart`) — update for the new TS-only template list (4 Lua templates removed in WU-4).
- `test/models/marketplace_script_test.dart`, `test/models/script_record_integrity_test.dart`, `test/script_record_test.dart` — drop `language` field assertions; rename `luaSource` → `bundle` (WU-7 lockstep).
- `test/services/script_signature_service_test.dart`, `test/services/marketplace_open_api_service_test.dart`, `test/services/script_integrity_service_test.dart` — rename `luaSource`/`lua_source` → `bundle` (WU-7 lockstep).
- `test/test_helpers/*.dart` (especially `unified_test_builder.dart`, `advanced_test_helpers.dart`, `mock_marketplace_service.dart`, `poem_script_repository.dart`, `poem_test_helper.dart`) — these embed Lua sample sources as test fixtures. Port to TS bundles OR replace with the `pilot-sample` bundle fixture (`crates/icp_core/tests/fixtures/pilot_sample.bundle.js` — copy into a Dart test asset). The "poem" test helper theme appears Lua-based; verify and port.
- `test/integration/script_upload_api_test.dart`, `test/integration/script_repository_api_test.dart` — update API body key `lua_source` → `bundle` (WU-7).
- Sweep all remaining files in the grep list (Section 2 research): ~95 test files match "lua". Most are incidental (use `luaSource` param name or "poem" Lua fixtures). Batch-rename `luaSource` → `bundle`; replace Lua fixture bodies with TS bundles.

**ADD (coverage gaps — see Section 4):**
- `test/features/scripts/ts_bundle_lifecycle_test.dart` — full init→view→update→effects roundtrip on a real TS bundle via `ScriptAppRuntime`.
- `test/features/scripts/ts_validation_negative_test.dart` — `eval`/`Function`/`import`/`Intl.*` rejection through `ScriptValidationService`.
- Extend `test/native_bridge_js_smoke_test.dart` — cover `jsAppInit`/`jsAppView`/`jsAppUpdate`/`validateJsComprehensive`/`jsLint` smoke paths (currently only 1 lua ref = the smoke test calls the wrong validator).

**Verification:**
```bash
cd apps/autorun_flutter && flutter test --concurrency=$(nproc) --timeout=360s
just test
```

**Estimated delta:** −~400 (Lua tests + helpers) +~250 (TS coverage) ≈ **−150 lines net**, test count rebalanced.

---

### WU-7 — Coordinated `lua_source` → `bundle` rename (BACKEND CONTRACT — HIGH RISK)
**Complexity:** Complex · **Dependencies:** WU-3 (Dart models staged) · **Risk:** HIGH (crypto signature + DB + API)

> ⚠️ **This is the single riskiest WU.** `lua_source` is: (a) a DB column, (b) the API JSON key, (c) **the field inside the Ed25519/secp256k1 signature payload**. Renaming breaks all pre-existing signatures (acceptable: greenfield, no backward compat) and requires the backend + client to ship together.

**Files & exact changes:**

**Backend (Rust):**
1. **`backend/migrations/`** — **ADD** `002_rename_lua_source_to_bundle.sql` (postgres) + `002_rename_lua_source_to_bundle_sqlite.sql`:
   ```sql
   ALTER TABLE scripts RENAME COLUMN lua_source TO bundle;
   ```
   (Greenfield: alternatively, edit `001_*` in place since no prod data. **Decision flag F-1**: edit-in-place vs additive migration — see Risk Register.)

2. **`backend/src/models.rs`**:
   - Field `pub lua_source: String` (line 13) → `pub bundle: String`.
   - `CreateScriptRequest.lua_source` (62) → `bundle`.
   - `UpdateScriptRequest.lua_source` (82) → `bundle`.
   - `SCRIPT_COLUMNS_WITH_ACCOUNT` (162): replace `scripts.lua_source` → `scripts.bundle`.

3. **`backend/src/repositories/script_repository.rs`**:
   - Lines 77, 91, 103, 126, 145–146, 175: rename param `lua_source` → `bundle`; SQL column `lua_source` → `bundle`.

4. **`backend/src/services/script_service.rs`**:
   - Lines 71, 108: `&req.lua_source` → `&req.bundle`; `req.lua_source.as_deref()` → `req.bundle.as_deref()`.
   - Lines 237, 320, 340, 352: test fixtures `lua_source: "..."` → `bundle: "..."`; assertions `updated.lua_source` → `updated.bundle`.

5. **`backend/src/middleware/auth.rs`** — **SIGNATURE PAYLOAD**:
   - Line 72: `"lua_source": &req.lua_source,` → `"bundle": &req.bundle,` inside the `serde_json::json!({...})` payload.
   - Line 179: `insert_optional_string("lua_source", &req.lua_source, &mut payload);` → `insert_optional_string("bundle", &req.bundle, &mut payload);`.

6. **`backend/src/db.rs`** — line 157: schema `lua_source TEXT NOT NULL,` → `bundle TEXT NOT NULL,`.

7. **`backend/src/main.rs`** — sweep ~15 fixture sites: lines 227, 277, 1796, 1829, 1845, 1861, 1888, 1898, 1905, 2005, 2052 — all `"lua_source":` JSON keys and `lua_source:` struct literals → `bundle`.

8. **`backend/scripts/dev-setup.sh`** (line 43), **`backend/scripts/add-sample-data.sh`** (line 53): SQL seed column lists `lua_source` → `bundle`.

9. **`backend/README.md`** (line 96): schema doc `lua_source TEXT NOT NULL,` → `bundle TEXT NOT NULL,`.

**Dart (API client layer — must ship with backend):**
10. **`apps/autorun_flutter/lib/services/marketplace_open_api_service.dart`**:
    - `uploadScript` param `luaSource` (487) → `bundle`; request body key `'lua_source': luaSource` (506) → `'bundle': bundle`; response constructor `luaSource: luaSource` (599) → `bundle: bundle`.
    - Line 671/687: `updateScript` param + body key `'lua_source'` → `'bundle'`.
    - Line 336: `return script.luaSource;` → `return script.bundle;`.
11. **`apps/autorun_flutter/lib/services/script_signature_service.dart`**:
    - Param `luaSource` (19, 87) → `bundle`; payload key `'lua_source': luaSource` (100) → `'bundle': bundle`; `_sanitizeUpdateFields` allowed-key `'lua_source'` (206) → `'bundle'`.

**Verification:**
```bash
cd backend && cargo test 2>&1 | tail -10
cd backend && cargo run &  # start server
curl -s -X POST localhost:8080/scripts -H 'Content-Type: application/json' \
  -d '{"slug":"t","title":"T","description":"d","category":"c","bundle":"(function(){return{}})()","version":"1.0.0"}'
curl -s localhost:8080/scripts | python3 -m json.tool  # verify "bundle" key in response
cd apps/autorun_flutter && flutter test test/integration/script_upload_api_test.dart test/services/marketplace_open_api_service_test.dart
# E2E: upload a signed TS bundle from the app → download → execute.
```

**Estimated delta:** ~+40 lines (migration files) net; high-churn rename across ~12 files.

---

### WU-8 — `parity/` simplification + SDK cleanup
**Complexity:** Simple · **Dependencies:** WU-1 · **Risk:** Low

1. **`parity/vectors.json`** (224 lines):
   - Remove the top-level `notes` dual-runtime framing (line 4: "...across the QuickJS and Lua runtimes..."). Replace with: "Authoritative helper-output vectors for the TS/QuickJS runtime."
   - **DELETE every `expectedLua` field** from all cases (e.g. line 23, 30, etc.). The `Case.expected_lua` field is already removed from the Rust test struct in WU-1.
2. **`parity/README.md`** (66 lines): rewrite to drop "both engines"/dual-runtime language; describe single-engine parity contract.
3. **`packages/marketplace-sdk/`**: verify `samples/pilot-sample.ts` is the canonical sample (it is). No Lua references in the SDK package (confirmed: grep clean). No changes needed unless SDK samples reference `lua_source` — they don't.

**Verification:**
```bash
cargo nextest run -p icp_core parity_vectors   # JS-only parity passes
```

**Estimated delta:** −~30 lines.

---

### WU-9 — Docs cruft slash
**Complexity:** Simple · **Dependencies:** none (independent) · **Risk:** Low

1. **`TODO.md`** (1,224 lines) — **slash to <150 lines**. Current structure is ~80% historical "DONE" wave notes (Radical UX Improvements Phases 3–7, DONE items from 2026-02). **Keep only:**
   - A current "Active Work" section (Lua sunset reference to this plan; any genuinely-open items).
   - A "Known Issues" section (verify still valid).
   - The "Architecture Reference" → "Lua App Contracts" (1202) and "UI_v1 Widget Types" (1209) sections — **rename** "Lua App Contracts" → "TS App Contracts" and verify the widget-type list matches the runtime.
   - Delete: all `### ... (DONE - DATE)` sections (lines 309–925 region), `## Implementation Summary` (155–264), stale wave notes, `### Lua Scripting UI (DONE)` (474), the 28 REMOVED/Wave markers.
   - **Result target:** a focused current-state backlog + architecture reference.

2. **Root docs:**
   - **`CLAUDE.md`** (320 bytes) — **DELETE**. It's a 1-line pointer to AGENTS.md; redundant ("Note: this project uses AGENTS.md files" then `@AGENTS.md`). Any Claude-Code-specific guidance belongs in AGENTS.md.
   - **`PASSKEY_IMPLEMENTATION_PLAN.md`** (5 KB, root) — **DELETE**. Superseded by the implemented passkey feature (`lib/screens/passkey_management_screen.dart` exists and works). If it contains non-obvious design rationale, fold a 5-line summary into `docs/` first; otherwise delete.

3. **`docs/specs/` freshness triage** (all dated 2025-02 = stale):
   - `IMPLEMENTATION_STATUS.md` ("Last Updated: 2025-02-15") — **DELETE or rewrite**. 4-month-stale status doc is misleading.
   - `MARKETPLACE_STATUS.md` ("2025-02-15") — **DELETE or rewrite**.
   - `TEST_COVERAGE_GAPS.md` ("2025-02-15") — **DELETE**; coverage gaps belong as TODO entries or are addressed by WU-6.
   - `BACKEND_INTEGRATION.md` — verify accuracy post-WU-7; update `lua_source` references → `bundle`.
   - `SCRIPTING_RUNTIME_MIGRATION.md` — **UPDATE**: mark Phase 4 (Lua sunset) as DONE with a date; add a closing note that the dual-runtime deprecation timeline (§G5) was collapsed (greenfield → direct sunset).

4. **`ARCHITECTURE.md`**, **`LOCAL_DEVELOPMENT.md`**, **`README.md`** (root): grep for `lua`/`Lua`/`lua_source`; update any references to reflect TS-only + `bundle`.

**Verification:** `grep -rin "lua" TODO.md docs/ *.md` returns only intentional historical context.

**Estimated delta:** −~1,300 lines (mostly TODO.md + deleted specs).

---

### WU-10 — General cruft sweep
**Complexity:** Medium · **Dependencies:** best after WU-1..WU-7 (so cruft is visible) · **Risk:** Low

1. **`vendors/` (536 MB, gitignored, 0 tracked files):** vendored reference repos (`ic`, `ic-auth`, `ic4j`, `quill`, `sdk`). Verify nothing in `Cargo.toml`/`pubspec.yaml`/build scripts references `vendors/*` paths (grep `vendors/` in `Cargo.toml`, `justfile`, `scripts/`). If unreferenced → **document as safe-to-delete locally** (it's already gitignored, so no repo change; just note in README/LOCAL_DEVELOPMENT that it's optional). If referenced → leave + document.
2. **`.tmp/` (492 KB), `.just-tmp/`:** gitignored test/build artifacts. Add to a cleanup target in `justfile` (e.g. `just clean-tmp`). No repo change.
3. **`agent/` (6 tracked files, 44 KB):** dockerized dev-container tooling (Dockerfile, docker-compose, entrypoint, git-hooks). **Keep** — intentional, not cruft. Verify `agent/Dockerfile` doesn't reference Lua (grep).
4. **TODO/FIXME/HACK markers:** only 4 in `lib/` + `crates/` (low). Review each; resolve or convert to TODO.md entries.
5. **Dead/zombie code sweep** (post-Lua-removal): run `flutter analyze` with unused-elements detection; `cargo clippy` (already enforced). Remove any imports/functions left dangling by WU-1..WU-7.
6. **Commented-out code:** grep `^\s*//` blocks in `lib/` for disabled logic → delete (greenfield, no dead code).
7. **`scripts/` dir:** `bootstrap.sh`, `build_*.sh`, `common.sh`, `dynamic-just-help.sh`, `run_android_emulator.sh`, `validation/` — verify each is referenced by `justfile`/docs; remove unreferenced. `check-deps-allowlist.mjs` + `deps-allowlist.json` are wired to `npm run check:deps` — keep.
8. **Duplicate/overlapping screens:** audit `lib/screens/` for superseded screens (the TODO "Radical UX" waves suggest `profile_menu_simplified` + `profile_menu_simplified_v2` may coexist — check `test/widgets/profile_menu_simplified_test.dart` AND `profile_menu_simplified_v2_test.dart`). If v2 supersedes v1, **delete v1 + its test**. Verify navigation (`scripts_screen.dart`, `main.dart`) only references the survivor.

**Verification:**
```bash
cd apps/autorun_flutter && flutter analyze 2>&1 | grep -i "unused\|dead" 
cargo clippy --workspace --all-targets -- -D warnings 2>&1 | tail -3
grep -rL "" apps/autorun_flutter/lib/**/*  # orphan-file check (files imported nowhere)
```

**Estimated delta:** variable; target −200..−500 lines of dead code.

---

## Section 3 — Tech Debt Reduction Targets

Concrete DRY/KISS/YAGNI opportunities discovered during research:

| ID | Location | Debt | Fix |
|----|----------|------|-----|
| TD-1 | `script_runner.dart` `ScriptRunner.run` (460–615) + `performAction` (635–793) | **Duplicated** call/batch/CanisterCallSpec construction in 3 places (run follow-up, performAction call, performAction batch). Each rebuilds a `tempSpec` + resolves keypair + calls anon/auth + decodes. | Extract `_executeCanisterCall(CanisterCallSpec)` and `_executeBatch(List<...>)` helpers; call from all 3 sites. **~150 lines dedupable.** |
| TD-2 | `ffi.rs` `icp_lua_app_*` vs `icp_js_app_*` | Each FFI fn repeats the same 15-line CStr→String→exec→CString pattern. | After WU-1 (lua gone), the JS FFI still has 6 near-identical wrappers. Consider a `ffi_helper` macro/closure. Optional; weigh against readability. |
| TD-3 | `native_bridge.dart` loader methods | Each method re-opens `_open()` lib + re-looks-up `_Symbols.free` inside try/finally. | Cache the `DynamicLibrary` + the `free` function once (lazy `static`). **~60 lines dedupable + perf win.** |
| TD-4 | `ScriptLanguage` enum (WU-3) | Abstraction with 1 possible value post-sunset = pure over-engineering. | Deleted in WU-3. |
| TD-5 | `language_detector.dart` (WU-3) | 54-line heuristic for a decision that's now constant. | Deleted in WU-3. |
| TD-6 | `_injectHelpers` Lua preamble (WU-3) | Host-injected Lua stdlib duplicated the Rust-side `install_helper_functions` in `lua_engine.rs`. TS bundles are self-contained — both copies are dead post-sunset. | Both deleted (WU-1 + WU-3). |
| TD-7 | `models.rs` `SCRIPT_COLUMNS_WITH_ACCOUNT` (162) | Hardcoded SQL column list string — must be hand-edited on every schema change (the WU-7 rename is painful because of it). | Generate from struct metadata, or at least keep a single source. Flag for future. |
| TD-8 | `script_validation_service.dart` `quickValidate` | Lua-regex heuristics (`loadstring(`, `while true do`) duplicate what the Rust validator already does authoritatively. | Post-WU-5, consider deleting `quickValidate` entirely (YAGNI) and trusting the Rust gate; or keep as a pure "is-empty / has-init" check. |

---

## Section 4 — Test Strategy

### Tests to DROP (low-signal / superseded)
- `test/lua_helpers_test.dart` — Lua preamble injection (deleted code).
- `test/services/language_detector_test.dart` — deleted heuristic.
- `test/controllers/script_controller_language_test.dart` — language routing no longer exists.
- Any test whose sole purpose is asserting the `language` field round-trips or that `detectLanguage` classifies Lua vs TS.
- Rust `lua_engine.rs` inline tests (24 tests, ~1,219 lines) — deleted with the module in WU-1.
- Rust `parity_vectors.rs` Lua-half assertions — collapsed in WU-1.
- Rust `benches/runtime.rs` Lua benchmarks — deleted in WU-1.

### Tests to FOLD / DEDUPE
- `test/script_runner_js_path_test.dart` + `test/script_runner_test.dart` + `test/script_runner_unit_test.dart` + `test/script_runner_followup_test.dart` — **4 overlapping runner tests**. Post-sunset, fold into ≤2 files: one for `ScriptRunner.run` (exec + follow-up call + batch + UI passthrough), one for `ScriptAppRuntime` lifecycle. Remove the "js path" framing — there's only one path.
- `test/widgets/profile_menu_simplified_test.dart` + `profile_menu_simplified_v2_test.dart` — if v2 supersedes v1 (WU-10), keep only v2's test.

### Coverage GAPS to FILL (TS positive/negative/edge)
- **TS bundle full lifecycle** — `ScriptAppRuntime` init→view→update→effects roundtrip on a real bundle (currently only Rust-side `pilot_e2e.rs` covers this; no Dart E2E).
- **Validation negative paths through the Dart service** — `eval`, `Function`, `import 'fs'`, `Intl.*` rejection must be verified at the `ScriptValidationService` layer (not just Rust `sandbox_adversarial.rs`).
- **NativeBridge JS smoke** — `jsAppInit`/`jsAppView`/`jsAppUpdate`/`validateJsComprehensive`/`jsLint` are barely covered on the Dart side (`native_bridge_js_smoke_test.dart` has 1 lua ref = it called the wrong validator pre-WU-5).
- **Marketplace round-trip with `bundle` key** — upload → GET → download → execute, asserting the new `bundle` wire field end-to-end (post-WU-7).
- **Sandbox adversarial via FFI** — port 1–2 of the Rust `sandbox_adversarial.rs` cases to Dart to catch FFI-wiring regressions (the FFI boundary can reintroduce globals if mis-wired).

---

## Section 5 — Risk Register

| ID | Risk | Severity | Detection | Mitigation |
|----|------|----------|-----------|------------|
| **R-1** | `lua_source` → `bundle` rename breaks the **signature payload** (`auth.rs:72`). Existing signed scripts become unverifiable. | **HIGH** | Backend signature-verification tests fail; `curl` upload with old signatures 401s. | Greenfield = no prod signatures to preserve. Ship backend + client atomically (WU-7). Add a backend test that signs with the new `bundle` key and verifies. **Flag F-1** below. |
| **R-2** | Missed `lua`/`mlua` reference → build break or runtime FFI lookup crash (`lookupFunction` throws on missing symbol). | **HIGH** | `cargo build` / `flutter analyze` red; runtime `Invalid argument(s): Failed to lookup symbol`. | The `grep -rl "lua\|Lua\|mlua\|lua_source\|luaSource"` list (Section 2 research) is the exhaustive hit-list (~95 Dart files + Rust + backend). After each WU, re-run `grep -rin "lua" crates/ apps/autorun_flutter/lib/ backend/src/` and require zero hits. |
| **R-3** | Shared FFI typedefs (`_LuaValidateComprehensiveNative` etc.) deleted instead of renamed → JS FFI breaks (they're shared). | **MEDIUM** | `flutter analyze` + `native_bridge_js_smoke_test.dart` red. | WU-2 explicitly says RENAME not delete; typedefs are used by JS methods (native_bridge.dart lines 496, 526, 548, 574). |
| **R-4** | TS example bundles (WU-4) don't match the runtime contract (must be pre-bundled IIFE, not raw TS source — the host runs QuickJS, not a TS compiler). | **MEDIUM** | App fails to execute templates at runtime ("JS execution returned empty" or parse error). | Author examples by porting `05_typescript_counter.js` pattern; verify each via `js_app_init` in a Dart smoke test before committing. Use `packages/marketplace-sdk` build to produce bundles from `.ts` if needed. |
| **R-5** | DB migration `lua_source` → `bundle` applied to a non-empty dev DB loses alignment with old row data. | **LOW** | Query returns null/empty `bundle`. | Greenfield: edit `001_create_scripts*.sql` in place (no migration needed) OR add `002_*_rename`. **Decision flag F-1.** Dev DB reset is acceptable (`backend/data/` is dev-only). |
| **R-6** | `vendors/` deletion (WU-10) breaks an undocumented build dependency. | **LOW** | Build failure referencing `vendors/...` path. | Grep before deleting; it's gitignored so no git history loss — can always re-clone. |
| **R-7** | `kDefaultSampleLua` → TS port (WU-4) loses UI feature coverage (the Lua demo exercises text_field/toggle/select/image/section/list — a rich widget regression surface). | **MEDIUM** | UI rendering regressions not caught by tests. | Port feature-for-feature; add a golden/structure test asserting the default bundle's `view` output contains each widget type. |
| **R-8** | Test "poem" helper theme (`test/test_helpers/poem_*.dart`) is deeply Lua-coupled and widely used → porting cost is high. | **MEDIUM** | Many feature tests fail to compile after WU-3. | Assess early in WU-6; if porting is large, replace poem fixtures with the `pilot-sample` bundle (single canonical fixture). |

### Decision Flags (require human input — do NOT auto-resolve)
- **F-1** (WU-7): Edit `001_*` migrations in place (true greenfield, no migration file) **vs.** add `002_*_rename` migration (preserves history). Recommend in-place given greenfield mandate, but DB-rule in AGENTS.md says "Never delete DB or tables" — **ASK**.
- **F-2** (WU-7): Keep `lua_source` as a stable wire name (defer rename, accept cosmetic debt) **vs.** full rename. Default plan assumes rename; confirm.
- **F-3** (WU-4): Are the 4 deleted Lua example demos worth re-implementing in TS, or is the single `05_typescript_counter.js` + pilot-sample sufficient for v1? (Affects scope.)

---

## Section 6 — Baseline Verification (captured 2026-06-30)

| Check | Command | Result |
|-------|---------|--------|
| Rust tests | `cargo nextest run -p icp_core` | **121/121 pass** (13.0s). Lua-inline + parity-lua tests included (will drop in WU-1). |
| Rust build | `cargo build -p icp_core` | **Green** (14.4s, fresh deps download). |
| Rust clippy | `cargo clippy -p icp_core --all-targets -- -D warnings` | Green (per spec §12 N1: `clippy::all` deny-on-warning enforced). |
| Rust fmt | `cargo fmt --all --check` | Green (per spec §12). |
| Flutter SDK | `which flutter` | `/home/ubuntu/flutter/bin/flutter` ✓ |
| Dart SDK | `which dart` | `/home/ubuntu/flutter/bin/dart` ✓ |
| Flutter app dir | `apps/autorun_flutter/` | Present (`autorun_flutter` is the single app). |
| Git remote | `git remote -v` | `origin git@github_sasa-tomic:sasa-tomic/icp-cc.git` (fetch+push) ✓ |
| Test helpers | `just test-feature <name>` | Available (`justfile:152`). |
| Loc tally | Lua touch surface | Rust −2,225 (engine) −~150 (ffi/parity/benches); Dart ~95 files; backend ~12 files. |

**Starting LOC to remove/rename:** ~2,400 Rust + ~1,500 Dart + ~300 backend + ~1,300 docs = **~5,500 lines** net reduction (plus ~3,500 lines of test churn).

---

## Section 7 — Recommended Execution Order

```
WU-1  (Rust engine removal)          ──┐
WU-8  (parity/SDK simplification)    ──┤  independent Rust-side
                                      │
WU-2  (Dart FFI symbols)             ──┐
WU-3  (runtime collapse + enum kill) ──┤  Dart engine removal
WU-5  (validation rewrite)           ──┤
WU-4  (content: examples/UI copy)    ──┘
                                      │
WU-7  (coordinated lua_source→bundle)─┤  HIGH RISK — backend+client atomic
                                      │
WU-6  (test cleanup + coverage)      ──┘  last; runs against final surface
                                      │
WU-9  (docs cruft slash)             ──┐  independent
WU-10 (general cruft sweep)          ──┘  last; benefits from clean surface
```

**Commit cadence:** one commit per WU (or per WU-cluster for WU-2/3/5 which share the Dart engine-removal boundary). Each commit message: `refactor(scripting): WU-N <title>`. Final commit: `docs(specs): mark Lua sunset (Phase 4) complete`.

**Definition of Done for the whole plan:** all 5 Section-1 success-criteria checkboxes ticked, all F-* flags resolved, `grep -rin "lua\|mlua\|lua_source\|luaSource\|ScriptLanguage\|detectLanguage" crates/ apps/autorun_flutter/lib/ backend/src/ docs/ *.md` returns **zero unintentional hits**.
