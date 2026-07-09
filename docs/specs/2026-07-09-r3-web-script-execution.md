# R-3 — TypeScript/QuickJS Script Execution on Flutter Web

**Status:** Plan (not yet implemented) · **Date:** 2026-07-09 · **Author:** Planner agent
**Tracks:** R-3a (execution — core), R-3b (IC HTTP agent — follow-up, decision-gated)
**Predecessors:** R-1 (conditional-import split ✅), R-2/R-4/R-5 (pure-Dart Web crypto/vault/passkey ✅) — see `docs/BROWSER_SUPPORT.md`

> **Implementer reading order.** Read §0 → §1.1 (the keystone) → §2 → your assigned WU.
> Every claim below is cited to `file:line` or a verified external fact. Assumptions that
> did NOT survive code review are marked ❌ DROPPED in §0.3.

---

## §0 Methodology

### §0.1 What I actually read (grounding)
- `apps/autorun_flutter/lib/rust/native_bridge_web.dart` — the stubs to fill (R-3 methods throw `UnsupportedError`).
- `apps/autorun_flutter/lib/rust/native_bridge_io.dart` — the native FFI shim (method signatures + JSON envelope contracts).
- `apps/autorun_flutter/lib/rust/native_bridge.dart` — the conditional-export facade + shared types.
- `crates/icp_core/src/js_engine.rs` (1477 lines) — public types + `static_analysis` mod + the **golden test suite**.
- `crates/icp_core/src/js_engine/runtime.rs` (432 lines) — **THE reference engine** (the keystone file).
- `crates/icp_core/src/canister_client.rs` (945 lines) — the IC canister client reference (R-3b).
- `crates/icp_core/src/ffi.rs` — FFI symbol contracts + envelope shapes.
- `crates/icp_core/Cargo.toml`, `lib.rs`, `wasm_exports.rs` — build-target gating (proves rquickjs≠wasm).
- `apps/autorun_flutter/lib/services/script_runner.dart` — the Dart host (effect-resolution loop).
- `apps/autorun_flutter/lib/examples/*.js` — real bundles. **`01_hello_world.js:2` is decisive evidence.**
- `apps/autorun_flutter/lib/models/marketplace_script.dart` — the `bundle` field type.
- `pubspec.yaml`, `web/index.html`, `justfile`, `test/features/scripts/` + `test/features/web/`.
- External: `justjake/quickjs-emscripten` (1.7k★) README + API docs (`QuickJSRuntime.setMemoryLimit`/`setInterruptHandler`/`setMaxStackSize`, `QuickJSContext.evalCode`/`getJson`).

### §0.2 Confidence per area
| Area | Confidence | Basis |
|------|-----------|-------|
| Q1 TS handling (keystone) | **10/10** | Direct code citation; bundle files literally `.js`; engine evals strings with no transpiler |
| Engine contract to replicate | **9/10** | `runtime.rs` read in full; JSON envelopes pinned by Rust tests |
| `quickjs-emscripten` choice | **9/10** | Standard library; its API is a near-1:1 mirror of rquickjs (the native engine) |
| Effect loop (host-resolved) | **10/10** | `script_runner.dart:481-517` + `runtime.rs:69-84` |
| Flutter-Web asset/interop mechanics | **6/10** | Needs the WU-1 PoC to retire; this is the honest unknown |
| IC HTTP agent (R-3b) | **4/10** | Deferred; needs a human decision (agent-js wrap vs from-scratch Dart) |

### §0.3 Assumptions that did NOT survive review ❌ DROPPED
- ❌ *"Bundles are TypeScript that the engine transpiles (swc/esbuild) at runtime."* **False.** `runtime.rs:143,281,337,397` eval the script string directly; `HOST_BOOTSTRAP_JS` (`runtime.rs:64-85`) is plain JS; `validate_esm_format` (`js_engine.rs:491-511`) **rejects** ESM import/export. `01_hello_world.js:2`: *"the host runs QuickJS, not a TS compiler."* → §1.1.
- ❌ *"Compile `icp_core`'s own rquickjs to WASM and reuse it."* **Infeasible.** `Cargo.toml:46-48` + `ffi.rs:303-306`: rquickjs's vendored C QuickJS cannot build to `wasm32-unknown-unknown`; the crate already ships a **static-analysis-only** wasm path (`wasm_exports.rs:9-12`). And Flutter Web's default target is JS, not WASM.
- ❌ *"Effects need a synchronous JS→Dart callback channel."* **Not needed.** Host helpers only *build descriptor objects* (`runtime.rs:69-84`); the Dart host resolves them outside QuickJS (`script_runner.dart:497-517`). No bidirectional channel. (This is the biggest simplification of the whole effort.)
- ❌ *"R-3 can be pure Dart like R-2/R-4."* **No.** Script execution requires a real JS engine; there is no pure-Dart QuickJS. The testability model differs from R-2/R-4 (§4.4).

---

## §1 Current state

### §1.1 ★ KEYSTONE — TypeScript handling (Q1)
**The executable artifact is plain JavaScript (ES2015), not TypeScript. The native engine does NOT transpile; the Web port needs NO transpiler either.**

Evidence (read top-to-bottom):
1. `MarketplaceScript.bundle` is `final String bundle` — a JS string, end-to-end (`models/marketplace_script.dart:22`).
2. The reference engine evaluates the bundle string verbatim:
   - `jsExec`: `ctx.eval(script)` (`runtime.rs:143`).
   - `jsAppInit`: `ctx.eval::<(), _>(script)` (`runtime.rs:281`).
   - `jsAppView`: `ctx.eval::<(), _>(script)` (`runtime.rs:337`).
   - `jsAppUpdate`: `ctx.eval::<(), _>(script)` (`runtime.rs:397`).
   There is no swc/esbuild/rquickjs-typescript call anywhere in the crate.
3. The injected host API (`HOST_BOOTSTRAP_JS`, `runtime.rs:64-85`) is hand-written ES5-ish JS (`var`, `function`). No TS.
4. `validate_esm_format` (`js_engine.rs:491-511`) **rejects** top-level `import`/`export` — i.e. the contract forbids module TS.
5. The shipped example bundles are `.js` files using ES2015 (`const`, arrow fns, `...state` spread, `globalThis.x =`):
   - `lib/examples/01_hello_world.js:1-3`: *"Minimal TypeScript/QuickJS bundle … Self-contained IIFE — the host runs QuickJS, not a TS compiler."*
   - `lib/examples/05_typescript_counter.js` — despite the filename, the content is plain JS.
6. A `grep` for `typescript|tsc|esbuild|swc|transpil` across `lib/services` finds **zero** transpilation calls (one unrelated badge comment).

**Bundle shape (the contract every web bundle satisfies):** an IIFE (or top-level function declarations) that, after `eval`, makes `init`/`view`/`update` reachable as globals:
```js
"use strict";
(() => {
  function init(arg)     { return { state: {...}, effects: [] }; }
  function view(state)   { return { type: "column", children: [...] }; }
  function update(msg,state){ return { state: {...}, effects: [...] }; }
  globalThis.init = init; globalThis.view = view; globalThis.update = update;
})();
```
(The Rust golden tests use the alternative — bare top-level `function init(){}` — which hoists to a global. **The web engine must support both**; `quickjs-emscripten` does, identically to rquickjs.)

> **Consequence for the plan:** this is the single most load-bearing finding. It removes an entire category of risk (TS→JS transpilation, source-map fidelity, a bundled compiler) and means **the web engine is a near-mechanical port of `runtime.rs`** onto `quickjs-emscripten`.

### §1.2 What the native engine does (the reference contract) — `runtime.rs`
| Concern | Native behaviour | Citation |
|---|---|---|
| Sandbox creation | `Runtime::new()`; `set_memory_limit(64 MiB)`; `set_max_stack_size(512 KiB)`; interrupt = `Instant::now() > deadline` | `runtime.rs:7-8,18-28` |
| Context stdlib | `Context::full` (JSON, Math, etc.) | `runtime.rs:26` |
| Arg injection | `globalThis.arg = JSON.parse(jsonArg)` (or `null`) | `runtime.rs:39-62` |
| Host bootstrap | `__icp_messages=[]`; `icp_log`; `get_arg`; `icp_call/batch/message/ui_list/result_display/searchable_list/section/table`; `icp_format_number/icp/timestamp/bytes`; `icp_truncate`; `icp_filter_items/sort_items/group_by` | `runtime.rs:64-85` |
| Safety | Neutralise `eval` & `Function` to throw | `runtime.rs:87-90` |
| `jsExec` envelope | `{"ok":true,"result":<eval value as JSON>,"messages":[...]}`; last-expression value `JSON.stringify`'d | `runtime.rs:122-167` |
| `jsAppInit` | calls `init(arg)`; result `{state,effects}` (missing → `null`/`[]`); envelope `{"ok":true,"state":...,"effects":...}` | `runtime.rs:269-314` |
| `jsAppView` | sets `globalThis.__icp_state__`; calls `view(state)`; envelope `{"ok":true,"ui":...}` | `runtime.rs:316-364` |
| `jsAppUpdate` | sets `__icp_msg__`+`__icp_state__`; calls `update(msg,state)`; envelope `{"ok":true,"state":...,"effects":...}` | `runtime.rs:366-432` |
| Timeout | if `Instant::now() > deadline` after failure → `{"ok":false,"error":"execution timeout"}` | `runtime.rs:306-311,356-361,423-429` |
| Bad JSON | `jsAppView`: `"invalid state JSON: …"`; `jsAppUpdate`: `"invalid msg JSON: …"` / `"invalid state JSON: …"` | `runtime.rs:328,378-380` |
| `lint_js` | wraps `validate_js_comprehensive` → `{"ok","errors":[{message}],"warnings":[],"line_count","character_count"}` | `runtime.rs:257-267` |
| `validate_js_comprehensive` | static-analysis stages (pure Rust) → if valid, parse-check via eval → re-eval → verify `init`/`view`/`update` exist as globals | `js_engine.rs:25-635`, `runtime.rs:188-255` |

### §1.3 The host helpers' effect contract (Q3, confirmed)
Inside QuickJS, `icp_call`/`icp_batch`/etc. **only build descriptor objects** (`runtime.rs:69-74`), e.g. `{action:"call",canister,method,...}` or `{action:"batch",calls:[...]}`. They do **not** execute canister calls. The Dart host inspects the returned `result`/`effects` for `action:"call"|"batch"` and resolves them via `_bridge.callAnonymous/callAuthenticated` **outside** QuickJS (`script_runner.dart:481-517`). Therefore the web engine needs **no JS→Dart callback channel** — the only boundary traffic is Dart→JS (strings) and JS→Dart (one JSON result string). This holds identically on Web.

### §1.4 What is currently stubbed on Web (`native_bridge_web.dart`)
The 6 R-3 methods + 2 shims throw a loud `UnsupportedError(_stagedReason)`:
`jsExec` (`:360`), `jsLint` (`:364`), `validateJsComprehensive` (`:368`), `jsAppInit` (`:377`), `jsAppView` (`:381`), `jsAppUpdate` (`:385`), `NativeBridge.{validateJsComprehensive,jsExec,jsLint}` (`:475-491`). IC-agent stubs: `fetchCandid`/`parseCandid`/`callAnonymous`/`callAuthenticated` (`:331-358`).

### §1.5 Build/test workflow (from `justfile`)
`just test-feature scripts` runs `flutter test test/features/scripts/` (VM, uses `MockCanisterBridge`). `just test` = Rust `nextest` + Flutter suite. `flutter build web` is the Web build gate. **There is no headless-browser Dart test runner today** — a new capability R-3 must introduce (§4.4).

---

## §2 Approach

### §2.1 Execution engine — **`quickjs-emscripten`** (chosen)
Load **`quickjs-emscripten`** (the `@jitl/quickjs-singlefile-browser` or `quickjs-emscripten-core` variant) as a Flutter Web asset (a `.js` loader + its `.wasm`), and drive it from Dart via `dart:js_interop` / `dart:js_interop_unsafe`. A thin Dart class `WebQuickJsEngine` ports `runtime.rs` method-for-method.

**Why (vs alternatives):**
| Option | Verdict |
|---|---|
| **A. `quickjs-emscripten` (justjake)** ✅ | The standard QuickJS-WASM library (1.7k★, active). Its runtime API is a **near-1:1 mirror of rquickjs** (the native engine): `QuickJSRuntime.setMemoryLimit`/`setInterruptHandler`/`setMaxStackSize` ↔ `rt.set_memory_limit`/`set_max_stack_size`/`set_interrupt_handler` (`runtime.rs:23-25`); `QuickJSContext.evalCode`/`getJson` ↔ `ctx.eval`/`js_value_to_json_string`. Supports most of ES2023 (covers our ES2015 bundles). Loads WASM into host-JS memory as a TypedArray. **Parity is tractable and faithful.** |
| B. Compile `icp_core`'s rquickjs to WASM | ❌ Infeasible — `Cargo.toml:46-48`, `ffi.rs:303-306`: vendored C QuickJS won't build to `wasm32-unknown-unknown`; existing wasm path is static-analysis-only (`wasm_exports.rs:9-12`). |
| C. `quickjs-emscripten-sync` (reearth) | ❌ Adds object-state-syncing magic we don't need; violates KISS. Our host helpers are stateless descriptor builders. |
| D. Pure-Dart JS interpreter | ❌ None exist that match QuickJS semantics; cross-parity impossible; contradicts the "no mocks" rule by faking an engine. |
| E. `JS-V8`/`isolated-vm`/`quickjs-ng` | ❌ Not browser-targetable (Node/native) or non-standard. |

**Interop shape (Dart side):** a `@JS()` facade over the quickjs-emscripten module (`newQuickJSWASMModule`, `module.newContext`, `context.runtime.*`, `context.evalCode`, `context.getJson`, `context.global.get/set`, `context.dispose`) with `extension type` JS interop. All cross-boundary payloads are **strings** (script text, JSON args, JSON results) — no shared-object lifetime juggling, because we always re-enter QuickJS afresh per call (matching `runtime.rs` creating a fresh `Runtime`/`Context` per call). `budgetMs` → interrupt handler that throws after the wall-clock budget.

### §2.2 IC canister HTTP agent (R-3b) — follow-up, decision-gated
Native uses the Rust `ic-agent` crate (`canister_client.rs:530,576,653`; mainnet `https://ic0.app`). The HTTP shape is the **IC HTTP gateway**: `/api/v2/canister/<id-encoded>/read_state` (for `candid:service` certified metadata → `fetchCandid`) and `/api/v2/.../query` + `/api/v2/.../submit` (→ `callAnonymous`/`callAuthenticated`), plus CBOR + bls12-381 signature verification for certified responses. `agent-js` is the reference client.

**Two options, both substantial — needs a human decision before WU-6:**
- **B1: wrap `@dfinity/agent` (agent-js) via `dart:js_interop`.** Reuses audited Candid encode/decode + request-id + signature logic. Cost: a large JS dep in the Web bundle; canister calls become browser-bound.
- **B2: build a minimal Dart IC agent** (CBOR + request-id + Ed25519→DER→self-auth principal already in pure Dart from R-2; add `read_state`/`query`/`submit` over `package:http`). Cost: re-implementing certified-response verification; high parity risk.

There is **no production-grade Dart IC-agent package today**. Recommendation: **B1** for parity with lower risk; defer until R-3a is green. `parseCandid` (textual→IDL, `canister_client.rs:161-201`) can be lifted into pure Dart early if needed (it's pure compute).

### §2.3 Testability model (differs from R-2/R-4 — read this)
R-2/R-4 are pure Dart → unit-tested in `flutter test` (VM) and "the same code ships to Web." **R-3 cannot be:** the engine is a browser WASM/JS artifact. So:
- **Pure-Dart logic** (JSON-envelope assembly, error-string mapping, the `HOST_BOOTSTRAP_JS`/`NEUTRALIZE_EVAL_JS` string constants, the `static_analysis` port in WU-5) → unit-tested in VM by injecting a fake `eval`.
- **Execution parity** (the golden vectors) → requires a real browser. Add a **Chrome headless** integration-test path (`flutter test` does not launch Chrome; use `integration_test/` + a headless-Chrome driver, or a Node-driven harness that loads the engine the same way the app does). Same constraint as passkeys (`BROWSER_SUPPORT.md` "WebAuthn E2E needs a real browser session").

---

## §3 Work units (sequenced, PoC-first, one commit each)

> Implement serially (shared repo — parallel edits race). Each WU lists **priority**, **files**, **approach**, **verification bar**, **deps**.

### WU-1 — PoC: load quickjs-emscripten in Flutter Web, eval a constant
- **Priority:** P0 · **Complexity:** Medium · **Deps:** none (this is the gate)
- **Files:** `web/` (add `vendor/quickjs-emscripten.*.{js,wasm}` + `<script>`/fetch wiring in `web/index.html` or a bootstrap asset), new `lib/rust/web/quickjs_engine.dart` (dart:js_interop `@JS()` facade + `WebQuickJsEngine.bootstrap()`), `pubspec.yaml` (declare the asset dir), new `test/features/web/quickjs_smoke_test.dart` (Chrome integration test).
- **Approach:** Smallest end-to-end proof. Load the WASM module, create a context, `setMemoryLimit`+`setMaxStackSize`+`setInterruptHandler`, `evalCode("1 + 2")` → `3`. No app integration, no envelopes yet. Establishes the asset-loading + interop pattern that everything else depends on (retires the §2.3 / §4.2 unknowns). **If this PoC fails, STOP and surface the blocker** (do not proceed to WU-2).
- **Verification bar:** a headless-Chrome test asserts `evalCode("1+2")` returns `3`; `setInterruptHandler` fires on `while(true){}`; an OOM alloc is aborted by `setMemoryLimit`. `flutter build web` exit 0.
- **Confidence gate:** ≥8/10 before WU-2, else raise the blocker.

### WU-2 — `jsExec` parity (the `execute_js_json` port)
- **Priority:** P0 · **Complexity:** Medium · **Deps:** WU-1
- **Files:** `lib/rust/web/quickjs_engine.dart` (add `executeJsJson(script, jsonArg)`), new `test/features/web/js_exec_parity_test.dart`.
- **Approach:** Port `runtime.rs:122-167` exactly: fresh context; inject arg global (`runtime.rs:39-62`); eval `HOST_BOOTSTRAP_JS` (`runtime.rs:64-85`) + `NEUTRALIZE_EVAL_JS` (`runtime.rs:87-90`); eval user script; marshal result via `JSON.stringify`; collect `__icp_messages`; return `{"ok":true,"result":...,"messages":...}`. Errors → `{"ok":false,"error":...}` (match `JsExecError::Js`/`Json`).
- **Verification bar (golden vectors, copy from `js_engine.rs` tests):** `simple_math` (`:740`), `with_arg_roundtrip` (`:749`), `json_helpers` (`:756`), `execute_returns_err_on_syntax_error` (`:767`), `execute_returns_json_error_on_bad_arg` (`:779`), and every `helper_icp_*` test (`:792-944`: call/batch/message/ui_list/result_display/searchable_list/section/table/format_*/truncate/filter_items/sort_items/group_by) must produce **identical JSON** on Web.

### WU-3 — `jsAppInit`/`jsAppView`/`jsAppUpdate` parity
- **Priority:** P1 · **Complexity:** Medium · **Deps:** WU-2
- **Files:** `lib/rust/web/quickjs_engine.dart`, new `test/features/web/js_app_lifecycle_parity_test.dart`.
- **Approach:** Port `runtime.rs:269-432` verbatim. Per-call `Runtime`/`Context`; `budgetMs→deadline→setInterruptHandler`; the exact globals (`__icp_state__`, `__icp_msg__`), envelopes (`{ok,state,effects}`/`{ok,ui}`), and error strings (`"execution timeout"`, `"invalid state JSON: …"`, `"invalid msg JSON: …"`, `"Required function 'init'/'view'/'update' not found"`).
- **Verification bar (golden vectors):** `app_init_view_update_roundtrip` (`:947`), `app_init_timeout` (`:985`, proves interrupt fires for `while(true)`), `app_view_invalid_state_json` (`:1007`), `app_update_invalid_msg_json` (`:1019`), `sample_app_default_works` (`:1033`, incl. the `icp_batch` effect descriptor in `effects`), and running the shipped `lib/examples/01_hello_world.js` init→view→update producing the same UI tree as native.

### WU-4 — Wire into `native_bridge_web.dart` + readiness gate
- **Priority:** P1 · **Complexity:** Medium · **Deps:** WU-3
- **Files:** `lib/rust/native_bridge_web.dart` (replace the 6 stubs + `NativeBridge` shims), new `lib/services/web_quickjs_readiness.dart` (mirror `SecureStorageReadiness` pattern: probe the engine on entry; if not loadable, render a blocking actionable panel — never a raw exception), the screen that hosts script execution (`script_runner` consumers).
- **Approach:** Lazy-load the engine once; route `jsExec/jsAppInit/jsAppView/jsAppUpdate` to `WebQuickJsEngine`. Because these are now genuinely async (WASM load + eval), reconcile with the synchronous `String?` signatures: run inside the existing async host (`ScriptRunner.run` is already `Future`; `ScriptAppRuntime.init/view/update` are `Future`) — the `RustScriptBridge`/`ScriptBridge` interface may need `Future` widening (note any native-side signature change is greenfield-acceptable per AGENTS.md "no backward-compat").
- **Verification bar:** `flutter build web` clean; a Web integration test drives `ScriptAppHost` with `01_hello_world.js` and renders the counter, presses Increment, asserts the view updates. Stubs removed; `flutter analyze` clean.

### WU-5 — `jsLint` + `validateJsComprehensive` (static port + runtime check)
- **Priority:** P2 · **Complexity:** Complex (mechanical but large) · **Deps:** WU-3
- **Files:** new `lib/rust/web/js_static_analysis.dart`, `lib/rust/web/quickjs_engine.dart` (runtime syntax+export check), `native_bridge_web.dart` (`jsLint`/`validateJsComprehensive`).
- **Approach:** Port `js_engine.rs:25-635` (`static_analysis` mod) to **pure Dart** so it runs in VM *and* ships to Web (mirrors how `wasm_exports.rs` does static-only today, but now in Dart and with the runtime stage restored). Then restore the runtime stage (`runtime.rs:188-255`): parse-check via `evalCode`; re-eval; verify `init`/`view`/`update` exist as globals. `validate_js_comprehensive` JSON shape per `ffi.rs:366-373`.
- **Verification bar (golden vectors):** `validate_valid_production_script`, `validate_blocks_eval`, `validate_blocks_function_constructor_and_require`, `validate_accepts_benign_function_substring_identifiers` (`:1160`), `validate_rejects_*` (`:1183-1216`), `validate_blocks_top_level_import/export` (`:1237-1277`), `validate_blocks_intl` (`:1332`), `validate_ui_node_*` (`:1280-1430`), `validate_missing_required_functions` (`:1374`), `lint_js_returns_json_shape` (`:1433`). Split this WU into sub-commits if it exceeds ~600 net lines.

### R-3b (deferred — sequenced after R-3a green, decision-gated)
- **WU-6 (P2):** IC-agent **approach decision** (§2.2 B1 vs B2) — *needs human input.* Then `parseCandid` (pure-Dart lift of `canister_client.rs:161-201`) + `fetchCandid` (`read_state` `candid:service` metadata). Parity vs `canister_client.rs:529-567`.
- **WU-7 (P3):** `callAnonymous`/`callAuthenticated` (query + submit/update, `canister_client.rs:569-746`) incl. JSON↔IDL args mapping (`build_args_from_json`/`json_to_idl_value`) and certified-response verification. Wire into `native_bridge_web.dart` stubs.

### Recommended order
**WU-1 → WU-2 → WU-3 → WU-4 → (parity milestone: R-3a done) → WU-5 → [decision] → WU-6 → WU-7.**
R-3a (WU-1..4) is the valuable core: it makes user scripts *run and render* on Web (effects that need live IC calls still resolve to descriptors; full canister effect resolution lands in R-3b).

---

## §4 Risks + unknowns

| # | Risk / unknown | Severity | Mitigation |
|---|---|---|---|
| **4.1** | **Asset loading + bundle size.** `quickjs-emscripten` WASM is ~1–3 MB; must lazy-load (only when a script is first run), and load correctly under Flutter Web's base-href/asset paths. | High | WU-1 PoC retires this. Lazy-gate behind the readiness panel (WU-4). Measure `build/web/` size delta; consider the singlefile-browser variant to avoid fetch-path complexity. |
| **4.2** | **`dart:js_interop` marshalling fidelity.** String round-trips are safe; the risk is the async-loading lifecycle (the engine is a `Promise`) and keeping `evalCode` synchronous to user code. | Med | WU-1 proves the sync-after-bootstrap path. Keep payloads as JSON strings (no shared `JSValue` lifetimes) — matches `runtime.rs`. |
| **4.3** | **Timeouts in single-threaded browser JS.** `setInterruptHandler` is polled by QuickJS between bytecode ops (same as native); a tight WASM loop can't be preempted by Dart. | Low | Identical to native's interrupt model (`runtime.rs:25`); `app_init_timeout` golden covers it. Document that *native* JS-of-WASM overhead exists but bounded by budgetMs. |
| **4.4** | **Headless parity testing.** `flutter test` (VM) cannot run the browser engine; no headless-Chrome Dart harness exists in-repo today. | High | Introduce a Chrome integration-test path in WU-1 (reused by all parity WUs). Pure-Dart logic still VM-tested via injected fakes. Mirror the passkey testing posture (`BROWSER_SUPPORT.md`). |
| **4.5** | **`intl`/ICU parity.** Native rejects `Intl.*` (`js_engine.rs:513-521`) and ships locale-free `icp_format_*` helpers. `quickjs-emscripten`'s QuickJS has no ICU by default → matches. | Low | Confirm the chosen build variant lacks ICU (a feature, not a bug). Keep `validate_intl` port in WU-5. |
| **4.6** | **Signature widening (sync `String?` → `Future`).** The engine is async on Web; `ScriptBridge` may need `Future` return types, touching the native side too. | Low | Greenfield/no-backcompat permitted (AGENTS.md). Keep native sync via `Future.value` if widening is needed. |
| **4.7** | **`eval`/`Function` neutralisation parity.** Native sets `globalThis.eval`/`Function` to throwing stubs (`runtime.rs:87-90`). Must replicate so `validate_security_patterns` defence-in-depth holds. | Low | Trivial: same JS string in the web bootstrap. Covered by a parity test. |
| **4.8** | **CORS for IC gateway (R-3b).** `ic0.app` does **not** send browser-friendly CORS headers for `/api/v2/*` — a Web agent may need a proxy. | Med (R-3b) | Investigate in WU-6; likely a backend proxy route (the backend already has permissive CORS, `BROWSER_SUPPORT.md:99-112`). Decision-gated. |

---

## §5 Out of scope / deferred
- **secp256k1 keypair/signing on Web (R-2 follow-up)** — unrelated; Ed25519 is the ICP-critical path and already done.
- **Wasm (`--wasm`) Flutter target** — out of scope; `dart:js_interop`/`package:js` can't compile to Wasm today (`BROWSER_SUPPORT.md:36-40`). JS target only.
- **Per-script persistent state across reloads** — not in the engine contract; `state` is host-managed.
- **Source-map/TS-authoring UX** — bundles are JS; authoring tooling is a separate concern.
- **Full R-3b (live IC canister effect resolution)** — deferred per §2.2/§3 until R-3a is green and the agent approach is decided. Until then, scripts that emit `action:"call"/"batch"` effects run but those effects surface as "IC agent not yet available on Web" rather than executing.

---

## §6 Items needing a human decision before implementation
1. **WU-1 asset strategy** — vendor `quickjs-emscripten` files into `web/` vs add a JS dependency build step. (Recommend: vendor the singlefile-browser build into `web/vendor/` for reproducibility; confirm in PoC.)
2. **R-3b IC-agent approach** — `agent-js` wrap (B1) vs from-scratch Dart agent (B2). **Block WU-6 on this.** (Recommend B1.)
3. **Headless-Chrome test runner** — accept the new test-tooling dependency (e.g. `integration_test` driven by headless Chrome, or a Node harness) and where it lives in `just`. (Needed by every parity WU; decide at WU-1.)

Everything else in R-3a is unambiguous and within independent-work authorization.
