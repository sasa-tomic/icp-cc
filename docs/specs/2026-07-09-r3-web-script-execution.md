# R-3 — TypeScript/QuickJS Script Execution on Flutter Web

**Status:** COMPLETE — R-3a (execution ✅) + R-3b (IC HTTP agent ✅), live-verified on mainnet · **Date:** 2026-07-09 · **Author:** Planner agent
**Tracks:** R-3a (execution — core) ✅, R-3b (IC HTTP agent — follow-up) ✅
**Predecessors:** R-1 (conditional-import split ✅), R-2/R-4/R-5 (pure-Dart Web crypto/vault/passkey ✅) — see `docs/BROWSER_SUPPORT.md`

> **Outcome.** Scripts run on Flutter Web with native parity: `jsExec` /
> `jsAppInit`/`View`/`Update`, `jsLint`, `validateJsComprehensive` (R-3a —
> `quickjs-emscripten`, 51 golden vectors), and `fetchCandid`/`parseCandid`/
> `callAnonymous`/`callAuthenticated` (R-3b — `@dfinity/agent@3.4.3` + backend
> byte-relay CORS proxy; ICP ledger `symbol() → "ICP"` proven live). Only
> secp256k1 (alg=1) remains stubbed. Keystones (§1.1) and WU breakdowns below
> remain the design record.

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
- **secp256k1 keypair/signing on Web (R-2 follow-up)** — ~~unrelated; Ed25519 is the ICP-critical path and already done.~~ **DONE (2026-07-09).** secp256k1 now runs on Web at native parity; see `docs/specs/2026-07-09-web-remaining-gaps.md` WU-2.
- **Wasm (`--wasm`) Flutter target** — out of scope; `dart:js_interop`/`package:js` can't compile to Wasm today (`BROWSER_SUPPORT.md:36-40`). JS target only.
- **Per-script persistent state across reloads** — not in the engine contract; `state` is host-managed.
- **Source-map/TS-authoring UX** — bundles are JS; authoring tooling is a separate concern.
- **Full R-3b (live IC canister effect resolution)** — ~~deferred per §2.2/§3 until R-3a is green and the agent approach is decided.~~ **DONE.** R-3b landed (§7); scripts emitting `action:"call"/"batch"` effects now resolve to live IC calls via the `@dfinity/agent` + backend CORS-proxy path.

---

## §6 Items needing a human decision before implementation
1. **WU-1 asset strategy** — vendor `quickjs-emscripten` files into `web/` vs add a JS dependency build step. (Recommend: vendor the singlefile-browser build into `web/vendor/` for reproducibility; confirm in PoC.)
2. **R-3b IC-agent approach** — `agent-js` wrap (B1) vs from-scratch Dart agent (B2). **Block WU-6 on this.** (Recommend B1.)
3. **Headless-Chrome test runner** — accept the new test-tooling dependency (e.g. `integration_test` driven by headless Chrome, or a Node harness) and where it lives in `just`. (Needed by every parity WU; decide at WU-1.)

Everything else in R-3a is unambiguous and within independent-work authorization.

---

## §7 R-3b — IC HTTP agent on Web (agent-js wrap + backend CORS proxy)

**Status:** Plan (decision resolved: **approach (1) — wrap `@dfinity/agent`**) · **Appended:** 2026-07-09 · **Author:** Planner agent · **Base:** HEAD `6b2b1a1a` (R-3a green + committed)
**Predecessors:** R-3a (QuickJS execution ✅), R-2 (pure-Dart Web Ed25519 + principal ✅), R-4 (vault ✅).
**Scope:** implement the 4 IC-agent methods that still throw `UnsupportedError` on Web (`native_bridge_web.dart:349-376`) — `fetchCandid`, `parseCandid`, `callAnonymous`, `callAuthenticated` — at parity with `crates/icp_core/src/canister_client.rs` + `ffi.rs`, so that scripts which emit `action:"call"`/`"batch"` effects (`script_app_host.dart:291-304,406-419`) execute live on Web.

> **Reader's note.** Every claim is cited to `file:line` (repo) or a verified external source. Assumptions that survive review are tagged ✅; the one load-bearing unknown is tagged ⚠️ **PoC-gated**. §7.0 is the methodology; §7.1–§7.6 are the design; §7.7 is the sequenced work; §7.8/§7.9 are risks + decisions.

### §7.0 Methodology

**§7.0.1 — What I read (grounding).**
- `native_bridge_web.dart` (the 4 stubs at `:349-376`; `_stagedReason` at `:70-72`) + `native_bridge_io.dart` (FFI contract — same 4 methods at `:197-294`) + `native_bridge.dart` (conditional-export facade).
- `crates/icp_core/src/canister_client.rs` (945 lines, the parity source of truth) + `ffi.rs` (envelope + `kind` discriminator at `:56-95`) + `Cargo.toml:55` (`ic-agent = "0.44.2"`).
- `script_runner.dart:82-98` (the `ScriptBridge` interface — sync `String?`) + `script_app_host.dart:270-420` (the async effect-resolution loop that calls the bridge) + `candid_service.dart:101-170` (the *separate* Dart-side candid registry fetch over `package:http`) + `widgets/canister_client_sheet.dart:198-321` (UI consumer).
- The R-3a vendor + interop pattern, in full: `web/index.html:35-42`, `web/vendor/quickjs/quickjs_entry.mjs`, `lib/rust/web/quickjs_engine.dart:55-126`, `lib/rust/web/quickjs_engine_web_access.dart`, `lib/rust/web/quickjs_engine_vm_stub.dart`, the justfile harness `:254-311`.
- Backend: `backend/src/main.rs:327` (global `Cors::new()`), `:136-326` (route map), `backend/Cargo.toml` (`poem = "3.0"`, `ic-agent = "0.44"`), `Cargo.lock:1953` (`ic-agent 0.44.2`) + `:3387` (`reqwest` — transitively available). `lib/config/app_config.dart:5-29` (single source for the API base URL).
- **External (verified, not assumed):** the `@dfinity/agent@3.4.3` npm `package.json` (esm `module` field + the maintainers' own `bundle` script); the `dfinity/icp-js-core` repo source for `HttpAgent` (`packages/core/src/agent/agent/http/index.ts`), `fetchCandid` (`…/agent/fetch_candid.ts`), the `Agent` interface (`…/agent/agent/api.ts`), `Ed25519KeyIdentity` (`…/identity/identity/ed25519.ts`), and the candid module (`…/candid/index.ts`); the DFINITY forum CORS thread (`forum.dfinity.org/t/access-control-allow-origin-cors-error/20023`).

**§7.0.2 — Confidence per area.**
| Area | Conf. | Basis |
|---|---|---|
| Native parity contract (the 4 methods + envelopes) | **10/10** | `canister_client.rs` + `ffi.rs` read in full; envelopes pinned by Rust tests (`ffi.rs:584-621`) |
| CORS makes a proxy mandatory | **10/10** | Forum thread + structural proof: agent-js `fetch`es `ic0.app`/`icp-api.io`, which send no `Access-Control-Allow-Origin` |
| agent-js host-override + custom-fetch passthrough | **10/10** | `HttpAgentOptions.host`/`.fetch` + `new URL('api/v…', this.host)` read in source |
| agent-js Ed25519 identity from 32-byte seed | **10/10** | `Ed25519KeyIdentity.fromSecretKey(secretKey)` reads the seed directly |
| esbuild singlefile browser vendoring (mirror R-3a) | **9/10** | package.json `bundle` script = `esbuild --bundle … --platform=browser`; size/CLI flags ⚠️ PoC-confirmed |
| ⚠️ did-text → IDL-types arg encoding on Web | **4/10** | `@dfinity/candid@3.4.3` ships **no** `.did` parser (only `IDL.encode/decode`); the typed-JSON-args path needs a PoC decision (§7.5) |

**§7.0.3 — Assumptions that did NOT survive review ❌ DROPPED.**
- ❌ *"ic0.app sends CORS headers for `/api/v2/*`."* **False.** Non-ICP frontends using `@dfinity/agent` hit CORS errors (DFINITY forum thread above). The native client is unaffected only because it is a native HTTP client. → proxy is mandatory (§7.2).
- ❌ *"agent-js needs secp256k1 to authenticate."* **False.** `Ed25519KeyIdentity.fromSecretKey(seed)` (`identity/ed25519.ts`) takes the 32-byte Ed25519 seed directly — exact parity with native `BasicIdentity::from_raw_key` (`canister_client.rs:674`). The R-2 secp256k1 Web gap is **not** triggered by R-3b.
- ❌ *"`@dfinity/candid` can parse a `.did` string into IDL types."* **False.** `candid/index.ts` exports only the `IDL` encode/decode runtime + UI helpers — no grammar/`IDLProg`/`fromText`. Native gets this from `candid_parser` (Rust). → typed-JSON-args encoding is the one open design question (§7.5).

### §7.1 The native parity contract (source of truth) — `canister_client.rs` + `ffi.rs`

| Method | Native impl | FFI envelope (`ffi.rs`) | Dart sig (`native_bridge_web.dart`) |
|---|---|---|---|
| **`fetchCandid`** | `Agent::builder().with_url(host).build()` → `agent.fetch_root_key()` → `agent.read_state_canister_metadata(canister, "candid:service")` (`canister_client.rs:530-567`); default host `https://ic0.app` (`:533`); 30 s timeout (`:25-32`) | raw candid **text** on success, **empty string** on error (`null_c_string`, `ffi.rs:228`) — *not* a `{ok,…}` envelope | `Future<String?> fetchCandid({canisterId, host})` (`:349`) — **already async** ✅ |
| **`parseCandid`** | `parse_candid_interface(did)` (`canister_client.rs:161-201`) — `IDLProg::parse` + `check_prog` → `MethodInfo{name,kind,args,rets}`; **pure compute, no network** | `serde_json::to_string(&ParsedInterface)` = `{"methods":[{"name","kind","args","rets"}]}`, **empty** on error (`ffi.rs:243-247`) | `String? parseCandid({candidText})` (`:353`) — **sync, pure** ✅ |
| **`callAnonymous`** | JSON/textual/`base64:` arg → `build_args_from_json`/`parse_idl_args_bytes` (`:432-522`) → `agent.query` (mode 0/2) or `agent.update().call_and_wait()` (mode 1) (`:604-623`) → decode via `try_decode_with_types` (fetches candid) ⟶ fallback `IDLArgs::from_bytes` (`:639-645`) | `{"ok":true,"result":<json>}` success / `{"ok":false,"kind":"<invalid_canister_id\|net\|candid>","error":"…"}` error (`canister_err_ptr`, `ffi.rs:78-87,271`) | `String? callAnonymous({canisterId,method,mode,args='()',host})` (`:357`) — **sync → must widen to `Future`** |
| **`callAuthenticated`** | identical to above but `Agent` built with `BasicIdentity::from_raw_key(&[u8;32])` from the Ed25519 seed (`canister_client.rs:662-680`) | same envelope as `callAnonymous` | `String? callAuthenticated({…,privateKeyB64,args='()',host})` (`:367`) — **sync → must widen to `Future`** |

**`mode` int** (`ffi.rs:89-95`): `0`=Query, `1`=Update, `2`=CompositeQuery.

**`args` formats** the native contract already accepts (`canister_client.rs:586-602, 501-522`):
1. JSON (`{…}` / `[…]` / scalar: `null`,`true`,`false`,`"…"`, number) → `build_args_from_json` (fetches candid to type the encode).
2. Textual candid `(42, "hi")` → `parse_idl_args_bytes` (parses arg expressions).
3. `base64:`-prefixed raw bytes → **passthrough, no parse** (`:508-513`).
4. `()` / empty → empty args (`:503-506`).

Formats 1 & 2 both lean on a candid grammar parser; format 3 leans on nothing. **This distinction is load-bearing for §7.5.**

### §7.2 The CORS reality → proxy is MANDATORY

The native client hits `https://ic0.app/api/v2/…` directly with a native HTTP client — no CORS concern. **In a browser the same calls are cross-origin and blocked**: `ic0.app`/`icp-api.io` send no `Access-Control-Allow-Origin` for `/api/v2/*` / `/api/v3/*` / `/api/v4/*` (empirically confirmed — non-ICP frontends using `@dfinity/agent` get CORS errors, DFINITY forum thread `…/20023`). **Therefore a backend proxy is a first-class part of R-3b, not an afterthought.**

The proxy is cheap because (a) the backend already mounts a permissive global `Cors::new()` (`main.rs:327`); (b) `ic-agent 0.44` is already a backend dep (`Cargo.toml`) → `reqwest` is transitively available (`Cargo.lock:3387`); (c) agent-js supports a **host override + custom `fetch`**, so the proxy can be a **dumb byte-for-byte relay** — it need not know anything about IC/CBOR/Candid (§7.3.1).

> Note: `candid_service.dart:134-170` (the *separate* Dart-side registry fetch over `package:http` to `https://icp-api.io/api/v2/canister/…/candid`) is ALSO cross-origin and CORS-blocked on Web. R-3b consolidates this: on Web, `CandidService` delegates to `RustBridgeLoader.fetchCandid` (the agent-js path) so **one proxy** serves every IC-bound call.

### §7.3 Approach — wrap `@dfinity/agent` via `dart:js_interop` (the chosen path)

Confirmed feasible by reading the agent-js v3 source. It mirrors the R-3a quickjs vendoring **exactly** (same esbuild singlefile-browser bundle → `<script type=module>` → `globalThis.__…` → `dart:js_interop` facade → conditional-import access module to keep `native_bridge_web.dart` VM-compilable).

#### §7.3.1 The CORS-evading design — host-override + transparent passthrough ✅ VERIFIED
`HttpAgent` (`agent/http/index.ts`) builds every URL relative to `this.host`:
```ts
new URL(`api/v4/canister/${id}/call`,       this.host)   // sync update
new URL(`api/v2/canister/${id}/call`,       this.host)   // async update
new URL(`api/v3/canister/${id}/query`,      this.host)   // query
new URL(`api/v3/canister/${id}/read_state`, this.host)   // read_state (→ fetchCandid)
```
and issues them all via `this.#fetch(url, {…body: cbor.encode(…)})`. Both `host` and `fetch` are public `HttpAgentOptions` (`host?: string`, `fetch?: typeof fetch`). So the clean design is:

- Set the agent's **`host`** to the proxy: `${AppConfig.apiEndpoint}/api/v1/ic` (single source, `app_config.dart:5-29`). The agent appends its `api/v{2,3,4}/…` suffix; the proxy strips the `/api/v1/ic` prefix and forwards the remainder verbatim to `${IC_GATEWAY_HOST}` (default `https://ic0.app`).
- (Optional, not required) pass a custom `fetch` only if we ever need to inject tracing/abort-signals — the default `globalThis.fetch` already works once the URL is same-origin to the proxy.

The agent keeps doing **all** CBOR encode/decode, request-id, signing, nonce, retry/backoff (`retryTimes`, default 3), ingress-expiry, **and certificate/bls verification** (`Certificate.create` with the **hardcoded mainnet `IC_ROOT_KEY`**, `agent/http/index.ts`). For mainnet, `fetchRootKey()` is a no-op (key baked in) — simpler than native, which calls it defensively (`canister_client.rs:542,606,701`). The proxy is provably protocol-blind.

#### §7.3.2 agent-js browser bundling ✅ (size ⚠️ PoC-measured)
- **Packages to bundle** (resolved from `@dfinity/agent@3.4.3/package.json`): `@dfinity/agent` + `@dfinity/identity` (devDep of agent; needed for `Ed25519KeyIdentity`) + peers `@dfinity/candid`, `@dfinity/principal` + deps `@dfinity/cbor`, `@noble/curves`, `@noble/hashes`. esbuild `--bundle` pulls them all into **one** file.
- **The vendoring recipe is the maintainers' own**: `@dfinity/agent`'s `package.json` `bundle` script = `esbuild --bundle src/index.ts --outfile=dist/index.js --platform=browser`. We mirror `web/vendor/quickjs/quickjs_entry.mjs`: a small `web/vendor/ic_agent/ic_agent_entry.mjs` that imports `{ HttpAgent }`, `{ fetchCandid }`, `{ Ed25519KeyIdentity }` and installs `globalThis.__icpCcAgent = { createAgent, fetchCandid, fromSecretKey, encode, decode, version }`, bundled via the same esbuild invocation used for quickjs (singlefile, minified). There is **no WASM** to inline here (agent-js is pure JS, unlike quickjs) — so the bundle is plain JS, no base64/.wasm asset.
- **Approx size**: ⚠️ **PoC-measured** (`ls -la` on the produced bundle; budget the `flutter build web` size delta). The noble-curves + cbor + candid runtime is expected in the low-hundreds-of-KB range (no heavy WASM), but the number must be reported in the WU-PoC before committing.
- **`<script type=module>`** in `web/index.html` next to the quickjs one, lazy-kicked-off (agent is only needed when a script emits a call/batch effect — load it lazily, behind the readiness gate, §7.6).

#### §7.3.3 The Dart↔JS interop surface (the methods we actually call)
Mirroring `quickjs_engine.dart`'s `@JS()` extension-type facade. All cross-boundary payloads are **strings + `Uint8List`** (no shared-JS-handle lifetimes — same discipline as R-3a).

| Native method | agent-js call(s) | Notes |
|---|---|---|
| `fetchCandid` | `fetchCandid(canisterId, agent)` (`fetch_candid.ts`) → `CanisterStatus.request({agent, canisterId, paths:['candid']})` (read_state) → fallback `__get_candid_interface_tmp_hack` query. Returns the did **string**. | Exact parity with `read_state_canister_metadata(canister,"candid:service")` (`canister_client.rs:545`). Also matches the `__get_candid_interface_tmp` fallback already in `candid_service.dart:101-130`. |
| `callAnonymous` | `const a = await HttpAgent.create({host, identity:new AnonymousIdentity()});` then `a.query(canisterId,{methodName, arg})` (mode 0/2) or `a.update(canisterId,{methodName, arg})` (mode 1). `arg` is the **encoded `Uint8Array`** (§7.5). Decode `reply.arg` (replied) or map `reject_code`/`reject_message` (rejected) → the native `{ok,result}` / `{ok,kind,error}` envelope. | `query` returns `ApiQueryResponse` (`api.ts`); `update` returns `UpdateResult` with certified `reply` bytes. |
| `callAuthenticated` | identical, but `identity = Ed25519KeyIdentity.fromSecretKey(base64Decode(privateKeyB64))` (the 32-byte seed, `identity/ed25519.ts`). | The seed is the SAME bytes R-2 derives on Web — no new key material. |
| `parseCandid` | **Two viable options** (decide in WU-PoC): (a) call into agent-js's `IDL` (already bundled) to walk the service; or (b) pure-Dart port of `parse_candid_interface` (`canister_client.rs:161-201`) like WU-5's static-analysis port — VM-testable, no JS round-trip. | **Recommend (b)** for parity+testability + to drop the candid-parser gap (§7.5); the did text is already in hand from `fetchCandid`. |

**Ed25519 identity — confirmed, no secp256k1 needed.** `Ed25519KeyIdentity.fromSecretKey(secretKey: Uint8Array)` (`identity/ed25519.ts`) derives the public key via `ed25519.getPublicKey` and signs via noble `ed25519.sign` — a pure-JS, browser-safe path. This is byte-parity with native `BasicIdentity::from_raw_key` (Ed25519 seed, `canister_client.rs:674`). The R-2 secp256k1-Web gap is **not** in scope for R-3b.

### §7.4 The backend CORS proxy (Rust / poem) — the keystone of §7.2

A single catch-all route that is a **protocol-blind byte relay** (per §7.3.1 the agent does all CBOR/signing/cert work):

- **Route:** `POST /api/v1/ic/*<rest>` (poem wildcard), where `<rest>` = `api/v2/canister/<id>/call` etc. Registered in `main.rs` alongside the existing routes (`.at("/api/v1/ic/*rest", post(handlers::ic_proxy))`), inheriting the global `Cors::new()` (`main.rs:327`). Supports `POST` (the only verb the agent uses for `call`/`query`/`read_state`) and `GET` (for the `status` endpoint + `candid` registry, used by `candid_service.dart` consolidation).
- **Behaviour:**
  1. Read the **raw request body bytes** (`poem::Request` — same pattern as `handlers/payments/mod.rs:189`) + forward `Content-Type: application/cbor` (and any other headers the agent set).
  2. `reqwest::Client` (rustls; already transitively present — **add an explicit `reqwest` dep** to `backend/Cargo.toml` for single-source clarity, matching the AGENTS.md "fail-fast, no transitive magic" ethos) → `POST ${IC_GATEWAY_HOST}/${rest}` with the verbatim body. `IC_GATEWAY_HOST` env var, default `https://ic0.app` (the native default, `canister_client.rs:533`).
  3. **Timeout:** every hop bounded — `reqwest` `.timeout(Duration::from_secs(IC_PROXY_TIMEOUT_SECS))`, default **30 s** (matches native `canister_call_timeout`, `canister_client.rs:26`). Configurable via env (the native `ICPCC_CANISTER_TIMEOUT_SECS` already exists — reuse the same name so tests can shrink it, mirroring `call_anonymous_timeout_fires_against_blackhole` at `canister_client.rs:900-944`).
  4. Return the **upstream body + status verbatim** (200/202 for call/read_state, 200 for query); do NOT interpret CBOR. The global `Cors` adds `Access-Control-Allow-Origin`. Handle the CORS **preflight** `OPTIONS` (poem's `Cors` middleware does this automatically — already proven by the marketplace API).
- **Anonymous + authenticated both pass through unchanged** — the auth is the agent-js-signed CBOR body itself; the proxy carries it opaquely. The proxy never sees a private key (zero-knowledge, end-to-end — consistent with the vault model).
- **No new CORS headers to invent** — the existing `Cors::new()` already permits the marketplace frontend's origin; the proxy is same-origin from the browser's POV (the agent points at `${apiEndpoint}/api/v1/ic`).
- **`fetchCandid`** needs no separate proxy path — it is a `read_state` (`/api/v3/canister/<id>/read_state`) routed through the **same** `/api/v1/ic/*` catch-all.
- **The `candid_service.dart` registry GET** (`https://icp-api.io/api/v2/canister/<id>/candid`, `:136`) is rerouted through `RustBridgeLoader.fetchCandid` on Web (§7.2 consolidation) — so this third cross-origin call also vanishes behind the single proxy.

### §7.5 The args-encoding gap ⚠️ (the one honest open question)

Native `build_args_from_json` (`canister_client.rs:432-499`) and `parse_idl_args_bytes` (`:501-522`) lean on `candid_parser` (Rust) to turn the did text + the caller's JSON/textual args into typed CBOR. **`@dfinity/candid@3.4.3` ships NO `.did` text parser** (`candid/index.ts` exports only `IDL.encode/decode` + UI helpers — confirmed). So on Web the typed-JSON/textual-candid arg path needs a did-text→IDL-types converter that agent-js does not provide out of the box.

**Resolution options (the WU-PoC picks one — listed best-first):**
- **(α) Pure-Dart did-text parser (recommended).** Port a minimal subset of `candid_parser`'s grammar (the shapes our marketplace scripts emit: records, variants, vec, opt, the fixed ints/nats, text, principal) to Dart, producing IDL types we feed to `IDL.encode` over the interop boundary. Pure-Dart → VM-testable (like WU-5's `js_static_analysis.dart`), runs on Web unchanged. Smallest dep footprint; highest parity; most test surface.
- **(β) Add a runtime did-parser JS dep** (e.g. legacy `candid` package or `@icp-sdk/bindgen` if runtime-usable). To be validated in PoC — may not exist as a clean browser-bundleable runtime today.
- **(γ) Ship v1 supporting only `base64:` raw-bytes args + `()` empty args** (`canister_client.rs:508-513,503-506`), which need NO parser; defer JSON/textual args to a follow-up. Documented scope reduction (not a silent gap) — callers pre-encode args.

**Until (α)/(β) land, Web calls accept `base64:`-prefixed raw bytes** — which the native contract already honours — so end-to-end canister calls work from day one; only the JSON-arg convenience path is gated. This is the single item moved to §7.9 for a human check (recommendation: approve (α)).

### §7.6 Signature widening (sync → Future) + readiness gate

- The agent-js calls are **inherently async** (network). `callAnonymous`/`callAuthenticated` return `String?` synchronously today (`native_bridge_web.dart:357,367`; `ScriptBridge`, `script_runner.dart:82-98`). **Widen `ScriptBridge.callAnonymous`/`callAuthenticated` to `Future<String?>`** and `await` them at the two effect-loop call sites (`script_app_host.dart:291-304,406-419` — already inside an `async` block). Native (`native_bridge_io.dart:238,266`) returns `Future.value(<sync FFI result>)` — greenfield-acceptable per AGENTS.md "no backward-compat". This realises the §4.6 risk noted in R-3a; it is local and mechanical. (`fetchCandid` is already `Future<String?>` on both targets; `parseCandid` stays sync.)
- **Readiness gate (mirror `SecureStorageReadiness`/`probeQuickJsReadiness`).** A `probeIcAgentReadiness()` loads the agent-js bundle once (lazily — only when a script emits a call/batch effect or the canister-client UI opens) and verifies the proxy is reachable (a cheap `agent.status()` round-trip, or a HEAD on `/api/v1/ic/`). If unavailable (offline backend / bundle failed), surface a loud `IcAgentUnavailable` panel — never a silent degrade. Until the gate is passed, call/batch effects resolve to a typed `"IC agent not available on Web"` descriptor (the R-3a §5 graceful-degrade posture, now made real).
- **Conditional-import access module** (the hard-won R-3a constraint): the agent-js interop lives in `lib/rust/web/ic_agent_engine_web_access.dart` (Web) with a `ic_agent_engine_vm_stub.dart` (`dart.library.io`) throwing stub, imported into `native_bridge_web.dart` via `import … if (dart.library.io) …`. This keeps `native_bridge_web.dart` VM-compilable so the R-2/R-4 web-crypto VM tests keep importing it directly — **identical** to the `quickjs_engine_web_access.dart`/`_vm_stub.dart` split (`native_bridge_web.dart:48-55`).

### §7.7 Work units (sequenced, PoC-first, one commit each)

> Frontend WUs **depend on the proxy (WU-1)** being live to test against `ic0.app`. PoC (WU-0) is the gate — if agent-js won't bundle or the host-override proxy round-trip fails, STOP and surface the blocker (fall back to approach (2), from-scratch Dart agent, only if (1) is proven infeasible).

**R-3b-WU-0 — PoC: bundle agent-js + one anonymous query through the proxy.** · P0 · Medium · Deps: WU-1.
- Files: `web/vendor/ic_agent/` (entry `.mjs` + produced `ic_agent.bundle.js`), `web/index.html` (`<script type=module>`), throwaway `lib/rust/web/ic_agent_engine.dart` (`@JS('__icpCcAgent')` facade), `scripts/ic_agent_web_probe/verify.js` (Playwright, mirrors `scripts/quickjs_web_probe/`).
- Bar: `HttpAgent.create({host: '<proxy>'})` → `agent.query('ryjl3-tyaaa-aaaaa-aaaba-cai', {methodName:'symbol', arg: empty})` returns `'ICP'` through Dart interop. Report bundle size + the `flutter build web` delta. Confidence ≥8/10 or raise the blocker.

**R-3b-WU-1 — Backend CORS proxy.** · P0 · Medium · Deps: none (unblocks WU-0).
- Files: `backend/src/handlers/ic_proxy.rs` (+ `handlers/mod.rs` export, `main.rs` route), `backend/Cargo.toml` (explicit `reqwest`), env `IC_GATEWAY_HOST`/`IC_PROXY_TIMEOUT_SECS`.
- Bar: `curl -X POST $API/api/v1/ic/api/v3/canister/<id>/read_state …` relays bytes to `ic0.app` and returns the upstream status+body with CORS headers; a blackhole upstream is killed by the 30 s (shrinkable) timeout — mirror the `call_anonymous_timeout_fires_against_blackhole` test (`canister_client.rs:900-944`) as a Rust unit test against a local blackhole listener.

**R-3b-WU-2 — `fetchCandid` + `parseCandid`.** · P1 · Medium · Deps: WU-0, WU-1.
- Files: `lib/rust/web/ic_agent_engine.dart` (+ access/stub split), `native_bridge_web.dart:349-355` (replace the 2 stubs), pure-Dart `parse_candid_interface` port (`canister_client.rs:161-201`) — option (α) of §7.5.
- Bar (golden vectors, captured from native `canister_client.rs` tests): `fetchCandid` against a stable public canister returns byte-identical did text; `parseCandid` of that did returns the identical `{methods:[…]}` JSON shape; `_fetchCandidFromRegistry` in `candid_service.dart` now delegates to `fetchCandid` on Web (parity + the CORS consolidation of §7.2).

**R-3b-WU-3 — `callAnonymous`.** · P1 · Medium-Hard · Deps: WU-2 + the §7.5 decision.
- Files: `ic_agent_engine.dart` (`query`/`update` wrappers + reply decode → native `{ok,result}`/`{ok,kind,error}` envelope), `native_bridge_web.dart:357-365`.
- Bar: a query (`mode 0`) and an update (`mode 1`) against a public canister produce JSON-identical `result` to native; a bad canister id → `{ok:false,kind:"invalid_canister_id",…}`; a blackhole → `{ok:false,kind:"net",…}` (the typed `kind` parity, `ffi.rs:68-74`).

**R-3b-WU-4 — `callAuthenticated` + signature widening.** · P2 · Medium · Deps: WU-3.
- Files: `ic_agent_engine.dart` (`Ed25519KeyIdentity.fromSecretKey` wiring), `native_bridge_web.dart:367-376`, `script_runner.dart:82-98` (`ScriptBridge` → `Future<String?>`), `native_bridge_io.dart:238,266` (`Future.value`), `script_app_host.dart:291-304,406-419` (`await`), `MockCanisterBridge` + any fakes.
- Bar: an authenticated query/update signed by a known seed produces the same `result` as native `call_authenticated`; the effect loop (`icp_call`/`icp_batch`) executes a real call end-to-end on Web.

**R-3b-WU-5 — Readiness gate + headless-Chromium parity verification.** · P2 · Medium · Deps: WU-4.
- Files: `lib/services/ic_agent_readiness.dart` (mirror `SecureStorageReadiness`), wire into `script_app_host` boot, `scripts/ic_agent_web_probe/verify_agent.js` + `lib/web_probe_agent_main.dart`, a new `just verify-ic-agent-web` target (extend the `verify-quickjs-web*` recipes, `justfile:254-311`).
- Bar: golden-vector parity (the WU-2/3/4 captures) passes in headless Chromium; the readiness panel renders when the proxy is unreachable; `flutter analyze` + `just test` clean; the shipped `01_hello_world.js`-style sample that emits an `icp_call` effect runs live on Web.

**Recommended order:** **WU-1 (proxy) ‖ WU-0 (PoC) → WU-2 → WU-3 → WU-4 → WU-5.** WU-1 and WU-0 can proceed in parallel (proxy needs no frontend; PoC can stub the proxy locally until WU-1 lands). The §7.5 args-encoding decision is made inside WU-0/WU-2 — block WU-3 on it.

### §7.8 Risks + unknowns (R-3b only; R-3a's at §4)

| # | Risk / unknown | Severity | Mitigation |
|---|---|---|---|
| **7.8.1** | **Bundle size / load latency.** agent-js + noble-curves + cbor adds to the Web bundle; loading it eagerly would bloat first paint. | Med | Lazy-load only when a call/batch effect is first emitted (behind the readiness gate, §7.6). Measure in WU-0; it is pure JS (no WASM inlined, unlike quickjs) so expected low-hundreds-of-KB. |
| **7.8.2** | **The §7.5 args-encoding gap.** Without a did-text→IDL-types converter, only `base64:`/empty args work on Web. | Med | WU-0/WU-2 pick option (α) pure-Dart parser (recommended) / (β) JS dep / (γ) scope-cut. `base64:` raw bytes ship from day one regardless (`canister_client.rs:508-513`). |
| **7.8.3** | **`api/v4` sync-call proxy semantics.** agent-js v3 prefers `api/v4/.../call` (sync) and falls back to `api/v2` (async+poll). The proxy is verb/path-blind so both pass, but verify both round-trip in WU-0. | Low | The catch-all `*<rest>` relay forwards any `api/v*` path; WU-0 asserts a sync `update` resolves. |
| **7.8.4** | **Query-signature verification overhead.** agent-js default `verifyQuerySignatures:true` fetches subnet node keys (extra `read_state`) per subnet (cached in IndexedDB). Native (ic-agent) does its own verification; parity is preserved but with more round-trips. | Low | Keep default (security parity). If latency hurts, expose `verifyQuerySignatures:false` behind an explicit opt-in (document the trade-off). |
| **7.8.5** | **Proxy as a new trust surface / abuse vector.** An open relay to `ic0.app` could be abused. | Med | Proxy forwards ONLY to `${IC_GATEWAY_HOST}` (default ic0.app) — never to an arbitrary host (the `host` arg from scripts is honoured **inside agent-js by routing**, but the proxy itself is single-upstream). Add a size + rate cap (poem middleware) — same posture as the marketplace API. |
| **7.8.6** | **`ed25519` between agent-js (noble) and our R-2 keys.** Both must produce identical signatures/principals for the same seed. | Low | R-2 already proved Dart `ed25519_edwards` ≡ Rust `ed25519_dalek`. noble/`@noble/curves` is the JS reference; add a cross-check golden in WU-4 (sign a known blob with both, assert equal). |

### §7.9 Items needing a human decision (R-3b only)
1. **§7.5 args-encoding approach** — (α) pure-Dart did-text parser **[recommended]** vs (β) a JS parser dep vs (γ) ship `base64:`-only for v1. **Block WU-3 on this.**
2. **Proxy scope** — confirm the proxy is single-upstream to `ic0.app` only (§7.8.5), and whether a per-tenant rate/size cap is wanted now or deferred. (Recommend: ship the single-upstream relay + a generous size cap now; rate-limit later if abused.)
3. **`verifyQuerySignatures` default** — keep agent-js's secure default (extra `read_state` per subnet, cached), or ship with it off for latency. (Recommend: keep ON for parity; revisit only if profiling shows pain.)

Everything else in R-3b is unambiguous, empirically grounded above, and within independent-work authorisation. The agent-js wrap is **feasible and recommended**; approach (2) (from-scratch Dart agent) is not needed unless WU-0 proves (1) infeasible.
