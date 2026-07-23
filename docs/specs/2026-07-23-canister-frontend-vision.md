# 2026-07-23 — Canister Web Frontends + Custom User Frontends: Feasibility Spike + Roadmap

**Status:** FEASIBILITY SPIKE COMPLETE — vision **VIABLE** (A-read-only + B + D verified; C + A-interactive feasible-with-risk). Plan ready for human approval of phase order. · **Date:** 2026-07-23 · **Author:** Planner agent (read-only spike)
**Read-only:** No app code changed. The only artifact is this file. Evidence is cited to `file:line`, canister IDs, and headless-Chromium screenshots.

> **Outcome.** icp-cc can support BOTH models of a canister dapp — (1) rendering a real IC
> canister web frontend **in-app** (a webview) and (2) the existing native declarative
> renderer (`ui_v1_renderer`) driven by a JS bundle. The four sub-capabilities probe cleanly:
> **(B)** auto-discovering a backend canister ID from a frontend's served assets works at
> **~100% hit rate** (7/7 dapps); **(A)** read-only IC frontends **render headlessly** and are
> usable; **(D)** a Candid-driven scaffold for arbitrary backends is **the most feasible** piece
> (every component already exists); **(C)** Greasemonkey-style user scripts and **(A)**
> interactive wallet injection are **feasible-with-risk**, and the make-or-break question — *can
> a raw Ed25519 profile key act as the IC agent identity without Internet Identity delegation?* —
> is answered **YES, by the app's own existing live code** (`ic_agent_engine.dart:76-81` already
> signs mainnet update calls with `Ed25519KeyIdentity.fromSecretKey`).

---

## §0 Methodology (what was actually verified)

### §0.1 Grounding — code read
- `apps/autorun_flutter/lib/config/example_dapps.dart` — `DappDescriptor`/`DappPath` (`backendDirect`/`frontendBrowser`); already ships `frontendUrl` + `hasFrontendBrowser`.
- `apps/autorun_flutter/lib/screens/dapp_runner_screen.dart:594-599` — Path A today is *open in system browser* (`url_launcher`); **no in-app webview exists yet**.
- `apps/autorun_flutter/lib/widgets/ui_v1_renderer.dart` — native declarative renderer (node types: `column`/`row`/`section`/`text`/`button`/`select`/`text_field`/`toggle`/`list`/`paginated_list`/`table`/`image`).
- `apps/autorun_flutter/lib/widgets/script_app_host.dart` — host: `init`/`view`/`update` + `icp_call`/`icp_batch` effects, permission gate, `authenticatedKeypair` sign-as-me.
- `apps/autorun_flutter/lib/widgets/canister_call_builder.dart:167-217,338-358` — **arbitrary user canisters already supported**; calls `CandidService.fetchCanisterMethods(canisterId)` and emits `icp_call` snippets.
- `apps/autorun_flutter/lib/services/candid_service.dart:122-167` — probes `__get_candid_interface_tmp` then falls back to `icp-api.io/api/v2/canister/<id>/candid`.
- `crates/icp_core/src/canister_client.rs:572-600` + `crates/icp_core/src/ffi.rs:220-226` — **robust native candid path**: certified `read_state_canister_metadata(canister, "candid:service")`.
- `apps/autorun_flutter/lib/rust/web/ic_agent_engine.dart:76-81,195-203` — web agent-js `fetchCandid` (read_state candid:service) + `createAuthenticatedAgent` via `Ed25519KeyIdentity.fromSecretKey`.
- `apps/autorun_flutter/lib/config/well_known_canisters.dart` — canonical canister catalog (incl. `637g5…` ICLighthouse, `74iy7…` Kinic, `cusyh…` Canistergeek, `n7ib3…` Cyql, `k7gat…` Canlista).

### §0.2 Grounding — network (real mainnet probes, 2026-07-23)
- Gateway reality check: `.icp0.app` **does not resolve** (DNS NXDOMAIN). The serving gateways are **`.icp0.io`** and **`ic0.app`** (both → `boundary.dfinity.network`). Every probe below uses `.icp0.io` / vanity domains.
- `icp-api.io/api/v2/canister/<id>/candid` GET → **HTTP 404 for ALL tested canisters** (ICP Ledger `ryjl3…`, II `rdmx6…`, SNS-1 `qoctq…`, OpenChat SNS `2jvtu…`). `icp0.io` variant also 404. The registry GET endpoint the Flutter `candid_service.dart` falls back to is **defunct** — see §5 Risk R-3.
- 7 frontend canisters probed for embedded backend IDs (HTML + first JS bundle) — see §2.

### §0.3 Confidence per area
| Area | Confidence | Basis |
|------|-----------|-------|
| B — backend discovery from frontend assets | **9/10** | 7/7 dapps embed backend IDs in served HTML/JS; method is mechanical |
| A — read-only webview render | **8/10** | 3/4 dapps rendered usable headlessly; webview-embedding mechanics well-trodden |
| D — Candid→declarative scaffold | **9/10** | every component exists; only a generator is new (~S effort) |
| C — user-script injection | **7/10** | standard webview JS-injection; risk is CSP `default-src 'none'` on IC frontends |
| A — interactive wallet/provider injection | **6/10** | raw-Ed25519-as-agent VERIFIED in-app; risk is II-hard dapps + CSP `connect-src` whitelists |

### §0.4 The two-frontend-model framing (the direction)
icp-cc renders a dapp through exactly one of two models, and they **share the profile keypair + permission gate**:
1. **Native declarative renderer** (`ui_v1_renderer`) — a JS bundle (`init`/`view`/`update` + `icp_call` effects) drives Flutter widgets. Today's only model. Best for: curated dapps, custom user frontends, marketplace scripts, offline-tolerant UI.
2. **Real web frontend in a webview** — load `<canister-id>.icp0.io` (or vanity domain) in an embedded browser. Best for: rendering an existing canister's actual frontend verbatim, and as the host for Greasemonkey-style user scripts + the injected wallet provider.

The vision unifies them: a dapp card can offer *both* paths (the descriptor's `DappPath` already models this); user-scripts (C) and wallet injection (A-interactive) **bridge** a webview back to the native profile/bridge.

---

## §1 PROBE B — Auto-discover the backend canister ID from a frontend canister

**Verdict: READY. ~100% hit rate (7/7).**

Per-dapp results (frontend canister → backend ID discovery):

| # | Dapp | Frontend source | Discovery method | Found backend ID(s) | Hit? |
|---|------|-----------------|------------------|---------------------|------|
| 1 | NNS dapp (old) | `nns.ic0.app` HTML | `canister-id=` HTML attrs | `rrkah-fqaaa-…-cai` (NNS Governance) + 12 more | ✅ |
| 1b | NNS dapp (new) | CSP `connect-src`/`img-src` | CSP lists `3r4gx-…-cai.icp0.io` etc. | self + governance/ledger | ✅ |
| 2 | NNS frontend canister | `3r4gx-…-cai.icp0.io` HTML | inline canister IDs | `fmkjf-bqaaa-…-cai`, `uly3p-…-cai` (NNS backend) | ✅ |
| 3 | ICLighthouse | `637g5-…-cai.icp0.io` JS | JS bundle grep | `ryjl3-…-cai` (ICP ledger) + its backend | ✅ |
| 4 | Kinic | `74iy7-…-cai.icp0.io` JS | JS bundle grep | 11 IDs incl `73j6l-2iaaa-…-cai` (Kinic backend) | ✅ |
| 5 | Canistergeek | `cusyh-…-cai.icp0.io` JS | JS bundle grep | `3vhcz-…`, `r5m4o-…` (CG backends) + ledger | ✅ |
| 6 | Cyql | `n7ib3-…-cai.icp0.io` JS | JS bundle grep | 13 IDs incl `mxzaz-…`, SNS-1 `qhbym-…` | ✅ |
| 7 | Canlista | `k7gat-…-cai.icp0.io` JS | JS bundle grep | 10 system canisters (governance/ledger/registry/II) | ✅ |

**Discovery methods (mechanical, ordered):**
1. Grep served **HTML** for textual canister IDs: regex `[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{5}-cai`.
2. Parse `canister-id="…"` **HTML attributes** (NNS prerenders these).
3. Parse the `Content-Security-Policy` header (`connect-src`/`default-src`/`img-src`) for `*.icp0.io` / `*.raw.ic0.app` subdomains — a whitelist of every canister the frontend talks to.
4. Grep the JS bundles (entry `main.js` → follow `src=` to immutable chunks) for the same regex + config keys (`canisterId`, `CANISTER_ID`, `process.env.CANISTER_*`).

**The honest caveat — "discovery" yields a *candidate set*, not a single ID.** Every frontend embeds **system canisters** (ICP Ledger `ryjl3-…`, II `rdmx6-…`, SNS-1) as false positives, plus occasional placeholders (`xxxxx-xxxxx-xxxxx-xxxxx-cai` appeared literally in Cyql). Disambiguation to THE backend is a ranking problem, not a lookup:
- filter out a curated set of known system canisters (`WellKnownCanister.all` + NNS/II suite);
- prefer the ID that appears most frequently / in a config-keyed position (`canisterId:` / `createActor`);
- present the surviving candidate list to the user to confirm (1-tap), defaulting to the top-ranked.

This is sufficient to power a "paste a frontend canister/URL → we auto-fill the backend" UX with a confirm step.

**Gateway gotcha:** vanity domains (OpenChat `oc.app`, DSCVR `dscvr.one`) are served via Cloudflare / Google Frontend, **not** a direct IC frontend canister. Discovery from a vanity URL requires following the asset chain to find the frontend canister (or asking the user to paste the `…-cai` id directly). DSCVR has "largely left the IC" (forum signal) — exclude from the canonical sample.

---

## §2 PROBE A — In-app webview rendering of real frontends

**Verdict: READY for read-only; wallet-gated dapps render but break at auth.**

Headless Chromium (Playwright `chromium.launch`, `--no-sandbox`) loaded 4 real frontend URLs; screenshots analyzed via `zai-vision`:

| Dapp | URL | Render verdict |
|------|-----|----------------|
| NNS dapp | `nns.ic0.app` | ✅ UI renders (sidebar Portfolio/Tokens/Neuron Staking/Voting/Launchpad) but **modal-gated** ("Meet the new NNS governance app" + "Session expired"); needs auth to proceed |
| ICLighthouse | `637g5-…-cai.icp0.io` | ✅ **Full explorer UI** — nav, search bar, "Latest Transactions" list. **Read-only USABLE, no wallet gate** |
| Kinic | `74iy7-…-cai.icp0.io` | ✅ **Full search UI** — logo, search box, category nav. **Read-only USABLE**, LOGIN present but non-blocking |
| Canistergeek | `cusyh-…-cai.icp0.io` | ⚠️ Landing page only; dashboard needs login |

**Conclusion: a real browser engine renders IC frontend canisters headlessly, and read-only dapps (explorers, search) are usable without a wallet.** Interactive/session-dependent dapps hit auth gates — which is exactly what PROBE 3 (wallet/provider injection) addresses.

**Flutter embedding options** (no in-app webview exists yet — `dapp_runner_screen.dart:594` is `url_launcher` → system browser):
- **Mobile:** `webview_flutter` (official) — `WebViewController.runJavaScript` / `runJavaScriptReturningResult` for user-script + provider injection.
- **Desktop (Linux/macOS/Windows):** `flutter_inappwebview` (WebKitGTK/macOS WKWebView/Edge WebView2) — the only Flutter webview with cross-desktop JS-injection + DOM access. `webview_windows` is Windows-only.
- **Web:** an `<iframe>` via `dart:html`/`HtmlElementView`; same-origin CSP will constrain injection (the iframe is cross-origin to icp-cc, so parent↔iframe messaging must go through `postMessage`).

**Gotchas to design around (all flagged as risks §5):**
- **CSP `default-src 'none'`** on IC frontends (NNS sets this) — blocks injected `<script>`s unless `script-src` allows them. User-scripts/provider may need to inject via the webview's privileged `runJavaScript` (evaluates in the page's world, bypassing CSP for the injected string) rather than DOM `<script>` insertion.
- **CSP `connect-src` whitelist** — a frontend only fetches from its own canister list; if our injected provider fetches to a different origin, it's blocked. Solution: route provider calls through icp-cc's native bridge (not the page's `fetch`).
- **Service workers** — some IC frontends register SWs; webviews must support them (InAppWebView does; iframe-on-Web may not).
- **`.icp0.app` is dead** — always construct frontend URLs with `.icp0.io` or the canister's vanity domain.

---

## §3 PROBE A-interactive — Wallet/provider injection surface

**Verdict: FEASIBLE-WITH-RISK. The make-or-break question is answered FAVORABLE (raw Ed25519 works as the agent identity).**

### §3.1 The IC wallet-provider standard (Plug — the de-facto `window.ic`)
From `docs.plugwallet.ooo/developer-guides/connect-to-plug/`:
- `window.ic.plug.requestConnect({ whitelist: [canisterId], host, timeout }) → Promise<PublicKey>`
- `window.ic.plug.isConnected() → Promise<bool>` · `disconnect()` · `onExternalDisconnect(cb)` · `onLockStateChange(cb)`
- session data: `window.ic.plug.agent` (the **HttpAgent**), `.principalId`, `.accountId`, `.isWalletLocked`
- transactions: `requestBalance()`, `requestTransfer()`
- actor model: `window.ic.plug.createActor(idlFactory, canisterId, { agent })` (or `window.ic.plug.actor` for whitelisted canisters).

A dapp that "works with Plug" calls `requestConnect` then `createActor` and treats `window.ic.plug.agent` as its signing HttpAgent. **To impersonate Plug we inject a `window.ic.plug` shim with the same method set.**

### §3.2 ★ Make-or-break: raw Ed25519 as the agent identity (no II delegation)
**Question:** Does the IC agent model demand an Internet Identity `DelegationChain`, or can a raw Ed25519 keypair be the agent identity?
**Answer: a raw Ed25519 identity is sufficient.** Evidence — the app **already does this live on mainnet**:
- `ic_agent_engine.dart:76-81` — `createAuthenticatedAgent(proxyOrigin, privateKeyB64)` builds the agent-js `HttpAgent` with `Ed25519KeyIdentity.fromSecretKey(...)` (byte-parity with native `BasicIdentity::from_raw_key`, `canister_client.rs:674`).
- `script_app_host.dart:322-330` — `bridge.callAuthenticated(privateKeyB64: widget.authenticatedKeypair.privateKey)` signs real update calls (e.g. NNS `manage_neuron RegisterVote` — verified live, `2026-07-21-alpha-vote-dapp.md` §10.2).
- The IC boundary nodes accept update calls signed by **any** valid Ed25519/ECDSA identity; II is merely one identity *provider*. The canister sees the caller's principal (derived from the pubkey).

**Implication for the injected provider:** we do NOT need to re-implement agent-js signing in JS. We inject a `window.ic` / `window.ic.plug` shim whose methods (`createActor`, `requestTransfer`, …) **delegate to icp-cc's host bridge** — reusing the exact `callAuthenticated` path that already signs with the profile key. The webview becomes a thin view; signing + canister I/O happen natively, the profile private key never enters the page's JS world (zero-knowledge, parity with the existing host model).

### §3.3 Minimal provider method set to implement
`requestConnect` (resolve immediately with the profile principal) · `isConnected` · `disconnect` · `getPrincipal`/`principalId` · `createActor(idl, canisterId)` (returns a Proxy whose every method → host `icp_call`, signed as the active profile) · `requestBalance`/`requestTransfer` (sugar over `createActor` on the ledger). `verifyExport`/sign is out of scope unless a dapp demands it.

### §3.4 Risk
- **II-hard dapps:** a minority of dapps check the caller is anchored to Internet Identity (or consume II delegation fields). Those won't accept a raw-Ed25519 principal. Mitigation: surface a clear "this dapp requires Internet Identity" fallback (open in browser) rather than silently failing.
- **CSP:** the injected shim must run via the webview's privileged `runJavaScript` (not a CSP-governed `<script>`), and must NOT use the page's `fetch` (route through the host bridge).
- **IDL availability:** `createActor` needs the canister's Candid interface; the shim fetches it via the host's robust `fetch_candid` (read_state `candid:service`) — not from the page.

---

## §4 PROBE D — Custom-frontend scaffold from Candid

**Verdict: MOST FEASIBLE. Every component exists; only a generator is new.**

### §4.1 Current candid path (verified)
- **Arbitrary canisters are already supported** — `CanisterCallBuilderDialog` (`canister_call_builder.dart:338-358`) lets the user type any canister id and calls `CandidService.fetchCanisterMethods` which renders a method picker.
- **Robust native fetch:** Rust `fetch_candid` (`canister_client.rs:572-600`) does certified `read_state_canister_metadata(canister, "candid:service")` + `__get_candid_interface_tmp` fallback; exposed via FFI `icp_fetch_candid` (`ffi.rs:220-226`).
- **Robust web fetch:** agent-js `fetchCandid` (`ic_agent_engine.dart:195-203`) — same read_state + hack-fallback.
- **Flutter `CandidService`:** probes `__get_candid_interface_tmp` (`candid_service.dart:138-167`), then falls back to the **defunct** `icp-api.io` GET (R-3).

### §4.2 The scaffold flow (the new work — SMALL)
Pick a canister → fetch Candid (via the robust `read_state` path) → **generate a starter `ui_v1_renderer` bundle** → drop into the script editor → run in `ScriptAppHost`. Concretely, a generator that walks `List<CanisterMethod>` and emits:
```
init(arg)   → state { canister_id, host, results: {} }
view(state) → column [ text(title); for each QUERY method: button(label=name, on_press={type:'call', method:name}); result_display(results[name]) ]
update(msg) → on 'call': emit icp_call({canister_id, method, mode:0, args:'()'}) ; stash reply in results
```
- Reuse `CanisterCallBuilderDialog.generateBundle` (`canister_call_builder.dart:32-75`) which already emits correct `icp_call` literals.
- The `CanisterMethod` model (`canister_method.dart`) + `ui_v1_renderer` node types are sufficient — no renderer changes.
- `ScriptAppHost` already runs any JS string via `init`/`view`/`update` + `icp_call` effects with the permission gate + sign-as-me.

**Effort: S (≈1 session).** The generator is ~200-300 lines of Dart string-building + a "Scaffold frontend from canister" entry point in the Canisters/Scripts screen. Estimated 85% lands in one pass; remaining 15% = nicer defaults (pick the top-N query methods, render lists for vec returns).

---

## §5 Risks / unknowns

- **R-1 (A/C/A-int) — CSP on IC frontends.** `default-src 'none'` + a `connect-src` whitelist (NNS is the prototype) can block naive DOM `<script>` injection and provider `fetch`. **Mitigation:** inject via the webview's privileged `runJavaScript` channel; route provider I/O through the host bridge, never the page `fetch`. Needs a per-dapp CSP-read on first load to classify.
- **R-2 (A-int) — II-hard dapps.** Some dapps hard-require Internet Identity (anchored principal / delegation fields). Raw Ed25519 won't satisfy them. **Mitigation:** detect + fall back to "open in browser"; never silently degrade.
- **R-3 (D + existing) — `icp-api.io` candid registry is defunct (404).** `candid_service.dart:171-207` falls back to a GET that now 404s for every canister. The robust `read_state candid:service` path (native + web) is unaffected and is what `callAuthenticated` actually uses — but the Flutter `CandidService` method-discovery path should be **rewired to the FFI `icp_fetch_candid`** (read_state) instead of the dead registry. (This is a latent bug independent of this vision — worth filing separately.)
- **R-4 (A) — webview fragmentation.** Mobile = `webview_flutter`; Desktop = `flutter_inappwebview` (WebKitGTK on Linux needs `webkit2gtk-4.1`); Web = iframe with `postMessage` (CSP-constrained). Three code paths to keep parity. **Mitigation:** define a single `DappWebviewController` abstraction with per-platform impls.
- **R-5 (B) — vanity-domain dapps (oc.app, dscvr.one) hide the frontend canister behind Cloudflare.** Auto-discovery works from the `…-cai` id, not from the vanity URL. **Mitigation:** accept canister-id input directly; for vanity URLs, follow redirects / parse the served HTML for embedded `…-cai` ids (works for most).
- **R-6 (C) — user-script security model.** Injected user scripts can exfiltrate the page's state. **Mitigation:** run user scripts in an isolated JS world (webview-isolated-world where supported); surface a trust prompt mirroring the existing per-dapp `DappTrustStore` gate.
- **R-7 (B) — `.icp0.app` direct subdomain is dead (NXDOMAIN).** Always use `.icp0.io` / `ic0.app` / vanity. Documented in §0.2.

---

## §6 Phased roadmap

> Effort: **S** ≈ 1 session, **M** ≈ 2-3 sessions, **L** ≈ 4+ sessions. A "session" ≈ a focused orchestrator-implementer unit (cf. `2026-07-21-alpha-vote-dapp.md`, 1-2 wall-clock days). Each phase is independently shippable.

### Phase 1 — D: Candid-driven custom-frontend scaffold  *(do first — highest confidence, lowest risk)*
**Scope:** "Scaffold a frontend from any canister" entry point → fetch Candid (robust read_state path) → generate a starter `ui_v1_renderer` bundle (one button per query method, result_display per reply) → open in `ScriptAppHost` / editor.
- **Files (new):** `lib/services/frontend_scaffold_generator.dart` (the generator) + a "Scaffold from canister" action in the Scripts or Canisters screen.
- **Files (touch):** `candid_service.dart` (rewire method-discovery to FFI `icp_fetch_candid` read_state — fixes R-3 as a bonus); reuse `CanisterCallBuilderDialog.generateBundle`.
- **Effort:** **S.** Risk: **Low.** Dependencies: none.
- **Acceptance:** (1) paste any canister id → Candid loads (incl. ICP Ledger, which has no `__get_candid_interface_tmp` — proves R-3 fix); (2) a runnable bundle is generated and opens rendering the query methods' outputs; (3) `just test-feature scripts` green + new scaffold tests.

### Phase 2 — B + A-read-only: auto-discovery + in-app webview (read-only)
**Scope:** (B) "paste a frontend canister/URL → we discover the backend(s)" with a candidate-list confirm; (A) a `DappWebviewScreen` that loads `<canister>.icp0.io` in-app (read-only), with the discovered backend surfaced alongside.
- **Files (new):** `lib/services/backend_discovery_service.dart` (HTML+JS+CSP grep + candidate ranking); `lib/screens/dapp_webview_screen.dart` + `lib/widgets/dapp_webview_controller.dart` (platform-dispatched: `webview_flutter` mobile / `flutter_inappwebview` desktop / iframe web).
- **Files (touch):** `example_dapps.dart` `DappDescriptor` (add an optional `frontendCanisterId` + a `DappPath.frontendInApp`); `dapp_runner_screen.dart` (add an "Open in-app" affordance next to the existing "Open in browser").
- **Effort:** **M.** Risk: **Medium** (R-4 webview fragmentation, R-5 vanity domains). Dependencies: Phase 1's read_state candid rewire is nice-to-have.
- **Acceptance:** (1) paste `3r4gx-…` or `nns.ic0.app` → candidate backend list incl. `rrkah…` governance, confirm in 1 tap; (2) ICLighthouse/Kinic render in-app with their read-only content usable (screenshot parity with the §2 headless renders); (3) platform-dispatch compiles + runs on linux desktop + web.

### Phase 3 — C: Greasemonkey-style user scripts over a rendered frontend
**Scope:** let a user attach a JS user-script to a loaded webview (observe/augment/automate); injected via the privileged `runJavaScript` channel (R-1); trust prompt mirroring `DappTrustStore` (R-6).
- **Files (new):** `lib/models/user_script.dart` (metadata + match-pattern on canister id); `lib/services/user_script_injector.dart`; a per-dapp "User scripts" panel.
- **Files (touch):** `dapp_webview_controller.dart` (inject ordered scripts into an isolated world on `onPageFinished`).
- **Effort:** **M.** Risk: **Medium** (R-1 CSP, R-6 isolation parity across platforms). Dependencies: Phase 2.
- **Acceptance:** (1) a sample user script (e.g. "highlight the governance canister id on the NNS page") injects and runs on ICLighthouse + NNS; (2) a trust prompt gates first injection; (3) a negative test proves the script cannot read the profile key.

### Phase 4 — A-interactive: injected wallet/provider (sign with the profile key)
**Scope:** inject `window.ic` / `window.ic.plug` shim whose methods delegate to the host `callAuthenticated` bridge (raw Ed25519, §3.2); make a Plug-compatible dapp sign + transact as the active profile.
- **Files (new):** `lib/services/wallet_provider_shim.dart` (the JS source of the `window.ic` shim, injected via `runJavaScript`); a host-side bridge from shim-call → `bridge.callAuthenticated`.
- **Files (touch):** `dapp_webview_controller.dart` (inject the shim before the dapp's main bundle); reuse `script_app_host`'s permission gate for shim-originated calls.
- **Effort:** **M-L.** Risk: **High** (R-2 II-hard dapps, R-1 CSP, per-dapp compatibility variance). Dependencies: Phase 2 (webview).
- **Acceptance:** (1) a Plug-compatible read+write dapp (e.g. a local-replica poll) signs + transacts as the active profile inside the webview; (2) `getPrincipal()` returns the profile principal; (3) an II-hard dapp falls back to "open in browser" with a clear message instead of silent failure; (4) the profile private key never appears in the page's JS world (test asserts).

---

## §7 Architecture sketch

```
                         ┌─────────────────────────── icp-cc (Flutter) ───────────────────────────┐
                         │                                                                          │
   Dapp card ───────────►│  DappDescriptor { backendCanisterId, frontendCanisterId?,                 │
   (catalog)             │                   paths: [backendDirect, frontendInApp, frontendBrowser]} │
                         │                                                                          │
        ┌────────────────┴───────────────┐                         ┌─────────────────────────────┐ │
        │ Model 1 — Native declarative   │                         │ Model 2 — Real web frontend │ │
        │ ui_v1_renderer + JS bundle     │                         │ DappWebviewScreen (webview) │ │
        │  init/view/update + icp_call   │                         │  loads <canister>.icp0.io   │ │
        │  ScriptAppHost                 │                         │   ┌─ user-script injector(C)│ │
        └─────────────┬──────────────────┘                         │   └─ window.ic.plug shim (A)│ │
                      │                                            └──────────────┬──────────────┘ │
                      │   both models share ◄────────────────────────────────────┘                │
                      ▼                                                                            │
        ┌─────────────────────────────────┐    ┌──────────────────────────────────────────────┐  │
        │ Profile keypair (Ed25519)       │    │ RustBridge.callAuthenticated / callAnonymous  │  │
        │ (secure storage) — sign-as-me   │───►│ certified read_state candid:service +         │  │
        │ never enters page JS            │    │ IC boundary (ic0.app) via backend CORS proxy  │  │
        └─────────────────────────────────┘    └──────────────────────────────────────────────┘  │
                         │                                                                          │
        Permission gate (per-method OR DappTrustStore) governs BOTH models ◄────────────────────────┘

  Phase 1 (D): FrontendScaffoldGenerator  ──► reuses ui_v1_renderer + ScriptAppHost (Model 1)
  Phase 2 (B+A-ro): BackendDiscoveryService + DappWebviewScreen (Model 2, read-only)
  Phase 3 (C):     UserScriptInjector  ──► runJavaScript into Model 2's webview
  Phase 4 (A-int): WalletProviderShim (window.ic)  ──► delegates to RustBridge.callAuthenticated
```

---

## §8 Open questions needing human decisions

1. **Phase order confirmation.** Recommended D → (B+A-read-only) → C → A-interactive. Alternative: ship A-read-only first (highest user-visible wow) if the webview-fragmentation risk (R-4) is acceptable early.
2. **Webview engine choice for desktop.** `flutter_inappwebview` (cross-desktop, adds `webkit2gtk` Linux dep) vs restricting in-app webview to mobile+web only (desktop keeps "open in browser"). This affects Linux-desktop packaging (`build-native.md`).
3. **Provider impersonation policy.** Should icp-cc impersonate `window.ic.plug` (broadest dapp compat) or expose a distinct `window.icpcc` provider that opt-in dapps detect? Plug-impersonation maximizes compat but inherits Plug's API churn.
4. **User-script trust model.** Per-script trust prompt (like marketplace scripts) or per-dapp broad grant (like `DappTrustStore`)? R-6 leans per-script.
5. **R-3 side-fix scope.** Rewire `CandidService` to the robust read_state path as part of Phase 1 (recommended — it unblocks scaffolding canisters without `__get_candid_interface_tmp`), or file separately?
6. **Discovery disambiguation UX.** Present a ranked candidate list (1-tap confirm) vs auto-pick top candidate (faster, occasionally wrong). Recommended: candidate list.

---

## §9 Confidence summary
| Capability | Verdict | Confidence |
|------------|---------|-----------|
| B — backend discovery | **READY** | 9/10 |
| A — read-only webview | **READY** | 8/10 |
| D — Candid scaffold | **READY** (most feasible) | 9/10 |
| C — user scripts | **FEASIBLE-WITH-RISK** | 7/10 |
| A — interactive wallet | **FEASIBLE-WITH-RISK** (make-or-break ✓) | 6/10 |
| **Overall vision** | **VIABLE** — ship phased, D first | **8/10** |
