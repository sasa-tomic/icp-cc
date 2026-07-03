# Plan — Example Dapp: Standalone + icp-cc Integration

**Status:** PROPOSED — for human review
**Author:** agent (research-synthesized)
**Date:** 2026-07-03

> Goal: ship ONE reference dapp that (a) builds & runs **standalone** as a real
> Internet Computer dapp (frontend canister + backend canister), and (b) is
> **integrated into icp-cc** so users can drive it from inside the app — through
> the real frontend UI **and/or** directly against the backend canister.

---

## 1. User value (what problem does this solve?)

A new/returning icp-cc user currently learns the platform against **third-party**
canisters (NNS Ledger, Governance) that they cannot modify. They cannot see the
end-to-end story: *a dapp with its own frontend + backend, that icp-cc can host
and drive both ways.* This example makes the integration model concrete and
teachable:

- **New user:** opens the bundled "Counter" dapp, sees a real canister respond,
  and can toggle between *the dapp's own UI* (embedded) and *icp-cc's native UI*
  talking to the same backend. One click, no setup.
- **Returning developer:** sees exactly how a two-canister dapp is structured and
  how icp-cc talks to *both* halves — the template to follow for their own dapps.

This is the single best teaching artifact for "what icp-cc is for."

---

## 2. The dual-path integration model (the core idea)

Every ICP dapp = **frontend canister** (static UI served over HTTP) + **backend
canister** (Wasm logic). icp-cc integrates with **both**, offering the user a
choice for any registered dapp:

| Path | Name | How it works | Renders | Keypair used |
|------|------|--------------|---------|--------------|
| **A** | **Open Dapp** (embedded browser) | Load the frontend canister's real UI in an in-app webview; inject the active profile's keypair as a JS identity *before* the page boots. | The genuine dapp UI | Injected into `@dfinity/agent` in-page (host key → self-auth principal) |
| **B** | **Backend Direct** (icp-cc native) | Run a TS `init`/`view`/`update` bundle that talks to the backend canister via host-mediated `icp_call` effects; render through `UiV1Renderer`. | Native Flutter widgets | Rust `icp_call_authenticated` (host key directly) |

**Path B is icp-cc's existing script-runtime model** — it works *today*, with no
new dependencies, against any real canister. **Path A** adds an embedded browser
for the real dapp experience. The two are complementary, not redundant.

**Why both?** Path A shows the dapp exactly as its author intended (full UI,
wallet flows). Path B is fast, keypair-native, offline-of-the-frontend, and
demonstrates icp-cc's *own* superpower (run a TS app against any backend). Giving
the user both, side by side, is the clearest possible demonstration of value.

---

## 3. On-box findings (verified 2026-07-03)

| Fact | Value | Impact |
|------|-------|--------|
| `dfx` version | **0.29.2** (legacy toolchain: `dfx.json`, port 4943, `@dfinity/agent`) | Use dfx patterns, *not* the newer `icp-cli`/`@icp-sdk` shown on current web docs |
| `dfx ping ic` | **healthy** (mainnet reachable) | Can talk to **real mainnet canisters** with zero deployment; can deploy our own backend to mainnet later |
| Flutter | 3.38.3 (≥3.32 required by the webview plugin) | OK |
| WPE WebKit / webkit2gtk libs | **MISSING** on dev box | Path A needs `apt-get install` (sudo) of WPE libs + a beta plugin — the one real friction point |
| icp-cc Rust FFI | `icp_call_anonymous`, `icp_call_authenticated`, `icp_fetch_candid`, `icp_parse_candid` all present | Path B foundation already exists |
| TS app contract | `init`/`view`/`update`; canister calls are **host-mediated effects only** (no in-bundle network) | Path B bundles emit `effects:[{kind:"icp_call",...}]` |
| Human-expectations doc | none exists | Will add (see §9) |

---

## 4. The reference dapp — "icp-cc Counter"

A **per-principal counter** — the canonical read/write/caller-identity example,
and the smallest thing that exercises everything we care about.

### 4.1 Backend canister (Motoko)
```
service : {
  whoami   : () -> (text) query;     // returns msg.caller — proves identity wiring
  getCount : () -> (nat) query;      // total across all callers
  inc      : () -> (nat);            // update: bump THIS caller's counter, return new value
}
```
- Stable `Map<Principal, Nat>` so counts survive an upgrade.
- `< 50 lines` Motoko. Uses `mo:base` (dfx 0.29.x bundled `moc`).

### 4.2 Frontend canister (assets + vite)
- Vanilla TS, `@dfinity/agent` + `@dfinity/identity`.
- **Dual identity mode**: if `window.__ICPCC_IDENTITY` is present (injected by
  icp-cc's webview), build `Ed25519KeyIdentity.fromSecretKey(...)` from it — no
  Internet Identity popup. Otherwise (standalone browser) fall back to a local
  random identity / optional `@dfinity/auth-client` (II).
- UI: shows "your principal", the global count, and an **Increment** button.

### 4.3 Standalone usage (no icp-cc)
```bash
cd examples/icp_counter_dapp
dfx start --background --clean      # local replica (port 4943)
npm install                          # frontend deps
dfx deploy                           # build + install both canisters
# open the printed frontend URL, e.g. http://<frontend-id>.localhost:4943
```
Optional mainnet: `dfx deploy --network ic` (needs cycles wallet).

### 4.4 Directory layout (new top-level `examples/`)
```
examples/icp_counter_dapp/
  dfx.json
  package.json                      # workspace: vite + @dfinity/agent + @dfinity/identity
  src/
    backend/main.mo                 # per-principal counter
    frontend/
      index.html
      src/index.ts                  # agent + actor; dual identity mode
      vite.config.ts
      tsconfig.json
  README.md                         # standalone run instructions + canister ids
  canister_ids.local.json           # (gitignored) produced by dfx deploy
```

---

## 5. Path B — Backend Direct (icp-cc native) — **HIGH confidence**

This is the robust, immediately-workable path. It uses only icp-cc's **existing**
runtime; the dapp backend is the only new external thing.

### 5.1 New example bundle: `lib/examples/06_icp_counter.js`
A `init`/`view`/`update` bundle that, on a button press, emits an `icp_call`
effect to `whoami`/`getCount`/`inc` on the deployed backend, then renders the
result via `UiV1Renderer`. Skeleton (grounded in `script_app_host.dart` +
`02_canister_query.js`):
```js
"use strict";
(() => {
  const BACKEND = "<<deployed-canister-id>>";  // single constant, injected at build
  function init(arg){ return { state:{principal:"",count:0,loading:false}, effects:[] }; }
  function view(s){
    return { type:"column", children:[
      { type:"text", props:{ text:"Principal: "+(s.principal||"—") } },
      { type:"text", props:{ text:"Global count: "+s.count } },
      { type:"button", props:{ label:"whoami (query)",  on_press:{type:"call",method:"whoami"} } },
      { type:"button", props:{ label:"getCount (query)",on_press:{type:"call",method:"getCount"} } },
      { type:"button", props:{ label:"inc (update)",    on_press:{type:"call",method:"inc"} } },
    ]};
  }
  function update(msg,s){
    if(msg.type==="call") return {state:s, effects:[{kind:"icp_call",id:"c",
        canister_id:BACKEND, method:msg.method, mode: msg.method==="inc"?1:0, args:"()"}]};
    if(msg.type==="effect/result" && msg.id==="c"){
      if(!msg.ok) return {state:{...s,loading:false}, effects:[]};
      const d=msg.data; const m=msg.method||"";
      if(typeof d==="string") return {state:{...s,principal:d,loading:false},effects:[]};
      if(typeof d==="number"||typeof d==="bigint") return {state:{...s,count:Number(d),loading:false},effects:[]};
      return {state:{...s,loading:false},effects:[]};
    }
    return {state:s,effects:[]};
  }
  globalThis.init=init; globalThis.view=view; globalThis.update=update;
})();
```

### 5.2 Prerequisites / known icp-cc bugs to fix first (so Path B is clean)
Found while documenting the contract (confidence in each finding ≥8/10):
1. **Button handler field name mismatch.** `05_typescript_counter.js` uses
   `action`; the renderer reads `on_press` (`ui_v1_renderer.dart:150`). Existing
   example buttons are silently dead. Fix the example to `on_press` (or teach the
   renderer both). **Confidence 9/10.**
2. **Static-analysis allowlist is stale.** `js_engine.rs:548-560` allowlist omits
   `paginated_list`, `result_display`, `table` (renderable) and lists `input`
   (no renderer case). Currently warn-only, not blocking, but misleading.
   Reconcile allowlist ↔ renderer. **Confidence 9/10.**
3. **`kind` vs `mode` field overloading.** Effect items use `kind:"icp_call"` at
   the effect level but `mode:0|1|2` for the call mode; some examples write
   `kind:0` (silently ignored). Standardize on `mode` for call mode in docs +
   examples. **Confidence 8/10.**

These are small, isolated fixes; they make *all* examples honest, not just ours.

### 5.3 Backend canister id sourcing (DRY, single constant)
The backend canister id is needed in (a) the standalone frontend, (b) the Path B
bundle, (c) icp-cc's dapp registry. **One source of truth:**
`examples/icp_counter_dapp/canister_ids.local.json` (dfx output) → read at
build/dev time. The bundle and registry reference a **symbolic name**
(`EXAMPLE_COUNTER_BACKEND`), resolved to the real id from one place. For mainnet
runs, a mainnet id constant is read instead. (Matches the project rule: a single
constant value defined in one place.)

---

## 6. Path A — Open Dapp (embedded webview) — **MEDIUM confidence (needs decision)**

### 6.1 Plugin & risk
- **`flutter_inappwebview` 6.2.0-beta.3** is the *only* single API covering
  Android **and** Linux desktop **and** macOS/Windows. Linux backend = **WPE
  WebKit** (not webkit2gtk), which is **beta and packaging-fragile** (known bugs
  #2807 hardcoded lib paths, #2798 `keepAlive`+`loadData`). Plugin needs Flutter
  ≥3.32 (we have 3.38.3 ✓).
- **Dev box currently lacks WPE libs** (`wpe-webkit-2.0`, `wpe-1.0` MISSING) →
  needs `sudo apt-get install libwpe-1.0-dev libWPEWebKit-dev wpebackend-fdo`
  (exact names per distro). This is the friction that makes this path a
  checkpoint rather than a slam-dunk.
- `webview_flutter` has no official Linux impl; `desktop_webview_window` opens a
  *separate* window (not inline) and no Android. So `flutter_inappwebview` is the
  only inline, cross-platform option.

### 6.2 How it works
1. **`DappBrowserScreen`** hosts an `InAppWebView` pointed at the frontend
   canister URL (`http://<id>.localhost:4943` local, `https://<id>.icp0.io`
   mainnet).
2. **Pre-page identity injection** via a `UserScript` at `AT_DOCUMENT_START`:
   defines `window.__ICPCC_IDENTITY = { secretKeyB64: "<active profile's Ed25519
   key>", principal: "..." }` **before** the page's own scripts run.
3. The frontend's `index.ts` checks for `window.__ICPCC_IDENTITY` and, if present,
   builds `Ed25519KeyIdentity.fromSecretKey(...)` — so the dapp signs as the
   user's principal **with no Internet Identity popup**. (Confirmed supported by
   `@dfinity/identity`; confidence 9/10.)
4. **JS↔Dart bridge** (`addJavaScriptHandler` / `window.flutter_inappwebview
   .callHandler`) for any host-mediated operations the dapp requests (optional —
   the injected identity makes the dapp self-sufficient).
5. **Secure context:** `http://127.0.0.1` and `http://*.localhost` are
   trustworthy origins in WebKit → `@dfinity/agent`'s WebCrypto works locally.
   No mixed-content issue on an all-http local replica.

### 6.3 Mitigation if the webview proves unbuildable on Linux
- Path A remains available on **Android/macOS/Windows** (stable plugin there).
- On Linux, fall back to **opening the frontend URL in the system browser**
  (`url_launcher`) — still "Path A" semantically (the real dapp UI), just not
  embedded. This is a safe degradation, not a mock.

---

## 7. icp-cc UI surface (user access)

Per project rules, backend-only changes are forbidden — users must *access* this.

- **New nav entry: "Dapps"** (or fold into the existing Canisters tab as a
  curated section). Lists registered example dapps.
- **Dapp detail sheet:** shows the dapp's backend Candid, and two primary
  actions: **"Open dapp"** (Path A, embedded/system browser) and **"Backend
  direct"** (Path B, runs the TS bundle in the existing runner screen).
- The example Counter dapp is pre-registered with sensible defaults so a **new
  user reaches a working demo in one click.**

---

## 8. Phased delivery

| Phase | Scope | Confidence | Depends on |
|-------|-------|------------|------------|
| **0 — Plan** | This doc, committed | — | human review |
| **1 — Standalone dapp + Path B** | `examples/icp_counter_dapp/` (backend+frontend); `dfx deploy` verified locally; `06_icp_counter.js` Path B bundle talking to the deployed backend; fix the 3 contract bugs (§5.2); Dapps UI entry; tests | **9/10** | dfx local replica works (will verify) |
| **2 — Path A webview** | `flutter_inappwebview` dep; `DappBrowserScreen`; identity injection; JS bridge | **6/10** (Linux) / 8/10 (other targets) | **human OK on system deps + beta plugin** |
| **3 — Polish & verify** | UX review (screenshots), full `just test`, alignment verification, human-expectations doc | 9/10 | Phases 1–2 |

**Recommendation:** execute **Phase 1 fully now** (it proves "talks with a real
canister" with near-zero risk), then checkpoint with you before Phase 2 (the
webview is the only part carrying real risk and needs your call on system deps).

---

## 9. Verification strategy (PoC-first, per AGENTS.md)

For each phase, prove it works as a user *before* writing tests:
1. **Standalone dapp:** `dfx deploy` → open frontend URL in a real browser →
   increment → count rises; `whoami` shows a principal.
2. **Path B:** in icp-cc, run `06_icp_counter.js` against the deployed backend →
   native UI shows principal/count, buttons trigger real query/update calls,
   results render. Verified by driving the app (tmux/chrome-cli), not just tests.
3. **Path A (if approved):** DappBrowserScreen loads the frontend → counter works
   → identity injected (no II popup) → principal matches the active profile.
4. **Error paths:** bad canister id, replica down, unauthenticated `inc` → loud,
   debuggable errors (no silent `null` returns; per project rules).
Then codify with tests (positive + negative + edge), run `just test-feature scripts`,
and the full `just test`.

---

## 10. Decisions requested from human (only the genuinely uncertain ones)

1. **Path A webview** — OK to (a) `apt-get install` WPE webkit libs on the dev box
   and (b) take a **beta** Flutter plugin (`flutter_inappwebview` 6.2.0-beta.3)?
   *Confidence this is the best available approach: 8/10. Confidence Linux will
   be smooth: 6/10.* If you'd rather not, Path A degrades to system-browser
   `url_launcher` (still real dapp UI, not embedded) — 9/10 safe.
2. **Mainnet vs local replica** for the demo target: local replica (ephemeral,
   free, full control) is the default; mainnet deployment needs a cycles wallet.
   Ship local-first, mainnet-ready. Agree?
3. Anything you'd add/cut in the dapp scope (counter vs guestbook vs poll)?

Everything else (Phase 1 in particular) I'll proceed with on approval, per
"iterate until done."

---

## 11. Confidence summary

| Item | Correct approach | Safe (no new problems) |
|------|:---:|:---:|
| Dual-path model (A embedded UI + B native TS) | 9/10 | 8/10 |
| Per-principal counter as the example | 9/10 | 9/10 |
| Path B (host-mediated `icp_call` + UiV1) | 9/10 | 9/10 |
| Identity injection via `Ed25519KeyIdentity.fromSecretKey` (no II) | 9/10 | 8/10 |
| `flutter_inappwebview` for Path A | 8/10 | 6/10 (Linux) |
| Phase-1 scope & sequencing | 9/10 | 9/10 |
