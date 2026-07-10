# Issue Hunt — Functional, Visual & Tech-Debt Sweep (Wave-5)

- **Status:** 🚧 IN PROGRESS
- **Date:** 2026-07-10
- **Scope:** Whole app (Linux desktop + Flutter Web + backend).
- **Method:** empirically grounded (every claim cited to `file:line` or a live
  observation), PoC-first, one commit per unit. Orchestrated via subagent
  swarms (planner → implementers → verifiers).
- **Predecessors (DONE):** `2026-07-10-quality-sweep.md` (Wave-4, all 11 WUs),
  `2026-07-08-quality-initiative.md` (Wave-1/2/3).

## §0. Baseline (measured 2026-07-10)

- Backend: `just api-dev-up` → healthy (port `38093` at planning time).
- Web build served at `http://127.0.0.1:8099`; rebuild for local backend:
  `flutter build web --dart-define=PUBLIC_API_ENDPOINT=http://127.0.0.1:<port>
  --dart-define=MARKETPLACE_WEB_URL=http://127.0.0.1:<port>`.

## §1. Findings (3 parallel planners, all COMPLETE)

Source files (gitignored, evidence only): `.tmp/ux-findings-wave5.md`,
`.tmp/audit-findings-wave5.md`, `.tmp/test-findings-wave5.md`. Screenshots:
`.tmp/screenshots/`.

| ID | Area | Severity | Title |
|----|------|----------|-------|
| UXR-2 / AUD-4 / AUD-11 | connectivity | **P1** | False "offline" banner on Web; `dart:io` Socket to `google.com:80`; should probe backend & be web-aware |
| UXR-5 / AUD-1 | marketplace | **P1** | Marketplace fetch failure swallowed → misleading empty "library", no error/retry |
| UXR-6 | dapps | **P1** | Only shipped dapp points at dead local replica `127.0.0.1:4943`; whole tab non-functional for real users |
| UXR-7 | dead code | **P2** | Orphaned `script_card.dart` ships "Payments Coming Soon" stub contradicting real ICPay flow |
| UXR-3 | marketplace | **P2** | Browse list endpoints return the FULL source bundle per script |
| UXR-4 | marketplace | **P2** | Browse tiles render generic 📦, ignore `iconUrl` images |
| UXR-8 | onboarding | **P2** | Wizard close (X) has no tooltip; dismiss → "Guest" limbo, wizard re-appears each restart |
| AUD-2 | scripts | **P2** | Validation `catch (e){return null}` masks every error as "bridge unavailable" |
| AUD-5 / AUD-9 | web/platform | **P2** | `BookmarksService` uses raw `dart:io` File → bookmarks broken on Web |
| AUD-7 / AUD-8 | DRY (Rust) | **P3** | `https://ic0.app` hardcoded ×5; `api.icpay.org` duplicated client+server |
| AUD-3 | silent error | **P3** | generic `catch(e){return null}` to mean "not found" (download_history, script_template) |
| AUD-6 | timeout | **P3** | gnome-keyring `Process.run` has no timeout |
| AUD-10 | heuristic | **P3** | Candid JSON-vs-IDL classification by first-char prefix list |
| AUD-12 | dead code | **P3** | `getFeaturedScripts`/`getTrendingScripts` unused (only self-tests) |
| UXR-9 | backend routing | **P3** | `/scripts/categories` → "Script not found" (shadowed by `/scripts/:id`) |
| TQ-1 / TQ-2 | test quality | **P1** | ~24 "mock-the-mock" tests assert on a standalone re-impl, not the real service (Wave-4 antipattern) |
| TQ-3 | test quality | **P1** | 9 `expect(true, isTrue)` placeholders that can never fail |
| TQ-4 | test quality | **P2** | Connectivity tests: `isA<bool>()` tautologies + `onTimeout:()=>true` (always pass, flaky) |
| TQ-5 | coverage | **P2** | `web_json_store`/`file_json_store`/`offline_banner_dismiss_service` = 0 tests |
| TQ-6 | test hygiene | **P2** | Hardcoded LAN IPs (`10.0.0.9`, `192.168.1.5`) in dapp test fixtures |

## §2. Work Units (serialized; shared git index)

> Prefix **IH-** = Issue Hunt. Each: PoC-first, one commit, `flutter analyze`
> clean + cited tests green + `cargo` green where Rust touched.

### IH-1 — Connectivity: web-aware + probe the actual backend [P1] (UXR-2/AUD-4/AUD-11)
Split `connectivity_service` via conditional export: Web impl uses browser
`navigator.onLine` + online/offline events; native impl probes the **actual API
host** (`AppConfig.apiEndpoint` /health) with a short budget, not `google.com:80`.
Remove the catch-all. Rewrite the connectivity tests deterministically (faked
probe + `fake_async`), removing the `onTimeout:()=>true` tautologies (TQ-4).
**Files:** `lib/services/connectivity_service.dart`, `lib/widgets/connectivity_scope.dart`.

### IH-2 — Marketplace load failure: surface typed error + Retry [P1] (UXR-5/AUD-1)
Track a `_marketplaceLoadError` state in `scripts_screen.dart`; on catch set it
+ render an inline "Couldn't load the marketplace — Retry" panel (mirror
`bookmarks_screen.dart`), distinct from genuine-empty. **Files:** `lib/screens/scripts_screen.dart`.

### IH-3 — Dapps: make the example actually usable for real users [P1] (UXR-6)
Investigate `examples/icp_poll_dapp` + bundled `06_icp_poll.js`. Decision: if a
real mainnet canister exists/works → point defaults at it; else honestly gate
the example as "developer (needs local replica)" with a clear empty-state
explaining how to `dfx start && dfx deploy`, and the runner's unreachable hint
already auto-expands. Never ship a silently-dead tab. **Files:** `lib/config/example_dapps.dart`, `lib/screens/dapp_runner_screen.dart`, `lib/screens/dapps_screen.dart`.

### IH-4 — Bookmarks: route through web-aware `JsonDocumentStore` [P2] (AUD-5/AUD-9)
Delete raw `dart:io` File + `getApplicationDocumentsDirectory` in
`bookmarks_service.dart`; reuse the existing `JsonDocumentStore` abstraction.
Bookmarks now work on Web. Add a `web_json_store`/`file_json_store` test (TQ-5). **Files:** `lib/services/bookmarks_service.dart`.

### IH-5 — Browse list endpoints: exclude full `bundle` [P2] (UXR-3)
Backend: omit `bundle` from `/featured`, `/trending`, `/category/*`, `/compatible`,
`/` (list); keep it only in `/scripts/:id`, `/preview`, signed `/download`.
Frontend model already tolerates null `bundle`. Big bandwidth win + stops shipping
source in a list view. **Files:** `backend/src/handlers/*`, `backend/src/main.rs`.

### IH-6 — Browse tiles: render `iconUrl` image [P2] (UXR-4)
`scripts_list_item_tile.dart`: render `CachedNetworkImage(iconUrl)` with the `📦`
fallback on load-failure, matching the details dialog. **Files:** `lib/widgets/scripts_list_item_tile.dart`.

### IH-7 — Delete orphaned `script_card.dart` "Payments Coming Soon" stub [P2] (UXR-7)
Delete `widgets/script_card.dart` + its tests (`script_card_paid_cta_test.dart`,
`script_card_keypair_test.dart`). Real paid flow lives in `scripts_screen.dart`. **Files:** `lib/widgets/script_card.dart`, tests.

### IH-8 — Validation: narrow catch → typed error [P2] (AUD-2)
`script_validation_service.dart`: catch only the specific "FFI bridge missing"
exception; let JSON/parse errors propagate as a typed `ValidationException`
carrying the cause. **Files:** `lib/services/script_validation_service.dart`.

### IH-9 — Wizard: close-button tooltip + handle no-profile dismiss [P2] (UXR-8)
Add `tooltip: 'Close'` to the wizard's close `IconButton`; on dismiss-without-
profile, surface a persistent "complete your profile" affordance (not a silent
Guest limbo + recurring wizard). **Files:** `lib/screens/unified_setup_wizard.dart`, possibly `main.dart`.

### IH-10 — DRY: single-source IC gateway + ICPay API URL [P3] (AUD-7/AUD-8)
One `const DEFAULT_IC_GATEWAY` in `canister_client.rs` referenced everywhere
(5 sites); client requires `apiUrl` from backend instead of a duplicate literal. **Files:** Rust `canister_client.rs`, `backend/src/handlers/ic_proxy.rs`, `backend/src/main.rs`, Dart `marketplace_open_api_service.dart`.

### IH-11 — Backend routing + dead-method cleanup [P3] (UXR-9, AUD-12)
Register `GET /scripts/categories` (distinct categories) BEFORE `/scripts/:id`
(or 404 properly). Decide featured/trending: wire into UI or delete dead client
methods. **Files:** `backend/src/main.rs`, `lib/services/marketplace_open_api_service.dart`.

### IH-12 — Misc tech debt [P3] (AUD-3/AUD-6/AUD-10)
Replace generic `catch(e){return null}` not-found with explicit check
(download_history, script_template); bound gnome-keyring `Process.run`;
structural IDL-vs-JSON test. **Files:** small edits across services.

### IH-13 — Test-quality cleanup [P1] (TQ-1/TQ-2/TQ-3)
Drop the ~24 mock-the-mock tests (`marketplace_open_api_service_test.dart`
L30-312, `script_upload_api_test.dart`); rewrite the 9 `expect(true)` favorites
placeholders into real tests. Real coverage already exists alongside. **Files:** test files.

### IH-14 — Test hygiene [P2] (TQ-5/TQ-6)
Add `web_json_store`/`file_json_store`/`offline_banner_dismiss_service` tests;
replace hardcoded LAN IPs with neutral fake hosts. **Files:** test files.

## §3. Execution order (serialized)

P1 first (IH-1, IH-2, IH-3, IH-13), then P2 (IH-4..IH-9, IH-14), then P3
(IH-10, IH-11, IH-12). Backend-touching WUs (IH-5, IH-10, IH-11) may batch.

## §4. Change log

| WU | Commit | Summary |
|----|--------|---------|
