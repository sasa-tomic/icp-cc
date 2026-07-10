# Wave 6 — Functional, Visual & Tech-Debt Sweep

- **Status:** 🔧 IN PROGRESS
- **Date:** 2026-07-10
- **Scope:** Whole app (Flutter Web + Linux desktop + backend).
- **Method:** empirically grounded (every claim cited to `file:line` or a live
  observation), PoC-first / TDD (RED → GREEN), one commit per unit. Orchestrated
  via subagent swarms (3 discovery planners → implementers → verifiers).
- **Predecessors (DONE, not reopened):**
  - `2026-07-10-issue-hunt.md` (Wave-5, IH-1..14)
  - `2026-07-10-quality-sweep.md` (Wave-4, QS-1..10)
  - `2026-07-08-quality-initiative.md` (Wave-1/2/3)

## §0. Baseline (measured 2026-07-10)

- `flutter analyze`: CLEAN (5.9s).
- Backend healthy on port `37245`; Web build served at `http://127.0.0.1:8099`.
- Single-test dev cycle ≈ 6s (verified). `flutter build web` ≈ 85s.
- 3 parallel discovery subagents produced: `.tmp/ux-findings-wave6.md`
  (10 findings), `.tmp/audit-findings-wave6.md` (12 findings),
  `.tmp/test-findings-wave6.md` (5 findings + coverage gaps).

## §1. Findings

### UX (live web review, no mocks)
| ID | Sev | Title |
|----|-----|-------|
| W6-1 | P1 | "Works now · Mainnet" ICP Ledger dapp BROKEN on Web → raw 501 exception dump (`ic_agent_engine_web_access.dart:43-48` falls back to `window.location.origin`) |
| W6-2 | P2 | Canister/dapp call failures surface as raw `IcAgentLoadException` stacks (HTTP headers+HTML) |
| W6-3 | P2 | Dapp runner shows hardcoded POLLS copy ("read polls", "vote") inside the ICP Ledger runner (`dapp_runner_screen.dart:79-83`) |
| W6-4 | P2 | Script details "Versions" tab renders completely blank — no content/empty-state/error |
| W6-5 | P2 | Settings Documentation + Report Issue links dead → 404 (`github.com/kalaj01`); real repo is `sasa-tomic/icp-cc` |
| W6-6 | P2 | No-match search shows misleading "Your Script Library is Empty" |
| W6-7 | P3 | `ModernEmptyState` announces every empty-state string TWICE to screen readers (`modern_empty_state.dart:203-218`) |
| W6-8 | P3 | Details canister id clipped ("ryjl3-tyaaa-aaaaa-aa…") and not copyable |
| W6-9 | P3 | Downloaded marketplace scripts lose their icon → revert to 📦 |
| W6-10 | P3 | Tappable card bodies aren't exposed as buttons (a11y) |

### Functional / tech-debt (static audit)
| ID | Sev | Title |
|----|-----|-------|
| A-W6-1 | P2 | `validate_credentials`/`verify_signature` reject keys/principals containing substring `"invalid"` (test-scaffolding in prod, can reject valid users) — `auth.rs:166,198,206` |
| A-W6-2 | P2 | Fragile `!responseData['success']` crashes on non-bool (12 sites); same file uses robust `!= true` 10× |
| A-W6-3 | P2 | DRY: response-decoding boilerplate copy-pasted ~15× in marketplace service (1514 lines) |
| A-W6-4 | P2 | `getCompatibleScripts` validates all IDs then sends only `.first` (misleading API) |
| A-W6-5 | P2 | One-sided status bound `> 299` (~11 sites) vs `< 200 \|\| > 299` |
| A-W6-6 | P2 | `getMarketplaceStats` passes unchecked `data` to `fromJson` (null→TypeError) |
| A-W6-7 | P2 | `jsonDecode` in error branch throws `FormatException`, masking real HTTP status (updateScript/deleteScript) |
| A-W6-8 | P2 | `profile_repository` unchecked `as List<dynamic>` cast bypasses corruption-recovery (`:94`) |
| A-W6-9 | P3 | `isLocalDevelopment` `.contains('.local')` false-positives |
| A-W6-10 | P3 | IC proxy `unwrap_or_default()` swallows truncated body → corrupt CBOR (`ic_proxy.rs:167`) |
| A-W6-11 | P3 | Candid registry host `icp-api.io` hardcoded literal (no symbolic name) |
| A-W6-12 | P3 | `formatPrincipal` validates with `contains('-')` heuristic |

### Test quality & coverage
| ID | Sev | Title |
|----|-----|-------|
| TQ-W6-1 | P1 | `generateTestSignatureSync` is a FAKE (DJB2 hash) disguised as real crypto; docstring lies. Flows into `unified_test_builder` → integration tests |
| TQ-W6-2 | P1 | Backend auth/recovery/middleware (passkey, vault-loss recovery, auth.rs) = ZERO tests |
| TQ-W6-3 | P2 | Generic `throwsA(isA<Exception>())` swarm (~11 sites) — passes for wrong errors |
| TQ-W6-4 | P2 | `native_bridge_js_smoke_test.dart` silently skips 17× when lib absent (always-green) |
| TQ-W6-5 | P2/P3 | 2 leftover `isA<bool>()` tautologies + `fake_passkey_authenticator_test` mock-the-mock + marketplace overlap |

## §2. Work Units

> Prefix **W6-** = Wave-6. Each: PoC-first / RED-test-first, one commit,
> `flutter analyze` clean + cited tests green + `cargo` green where Rust touched.

### W6-1 — IC agent proxy origin correct fallback + friendly IC call-failure UX [P1] (UX W6-1, W6-2)
- Fix `_resolveProxyOrigin()` (`ic_agent_engine_web_access.dart`): the comment
  claims `AppConfig.apiEndpoint` is "VM-only" but it is `String.fromEnvironment`
  → web-available. Use it as the fallback origin instead of
  `window.location.origin` (which is only correct for same-origin reverse-proxy
  production deploys; split-origin = silent breakage). Keep the dart-define
  override as highest priority.
- Map `IcAgentLoadException` to a friendly message in the dapp runner + canister
  call sheet (e.g. "Couldn't reach the canister — check connection and retry"),
  with the raw text in a collapsible "details". No raw HTTP-header/HTML dumps.
- Files: `lib/rust/web/ic_agent_engine_web_access.dart`,
  `lib/config/app_config.dart` (verify), `lib/screens/dapp_runner_screen.dart`.

### W6-2 — auth.rs: remove substring "invalid" heuristic [P1] (A-W6-1, security)
- Delete the `== "invalid-*"` sentinel + `.contains("invalid")` checks in
  `verify_signature` (`:166`) and `validate_credentials` (`:198,206`). Real
  validation happens via `verify_ed25519_signature`/`from_bytes` (fail loudly).
- If tests rely on the sentinel path, inject a test-only rejection via a feature
  flag or restructure the test to pass genuinely-invalid signatures.
- RED test: a valid principal/public-key containing the run "invalid" must be
  accepted (currently rejected).
- Files: `backend/src/auth.rs`, `backend/tests/*`.

### W6-3 — Marketplace service hardening: extract `_decode` helper [P2] (A-W6-2,3,5,6,7)
- Add `Map<String,dynamic> _decodeSuccessResponse(...)` + `T _decodeData<T>(...)`
  helpers (mirror `PasskeyService._handleResponse`). Collapse every method.
- Mechanically fix all `!responseData['success']` → `!= true` (via helper).
- Standardize status bound to `< 200 || > 299` (via helper).
- Guard `getMarketplaceStats` data-is-Map check.
- Make error-branch decode (updateScript/deleteScript) tolerate non-JSON bodies
  (reuse `_buildUploadErrorMessage` pattern) — don't mask the HTTP status.
- Files: `lib/services/marketplace_open_api_service.dart`.

### W6-4 — `getCompatibleScripts`: align signature with behaviour [P2] (A-W6-4)
- Pick one: either `String canisterId` (single, drop the loop) OR loop/merge.
  Prefer single (simplest, matches backend). Update callers.
- Files: `lib/services/marketplace_open_api_service.dart`, callers.

### W6-5 — profile_repository unchecked cast [P2] (A-W6-8)
- `profileData['keypairs'] as List<dynamic>? ?? <dynamic>[]` (mirror line 84).
- RED test: a profile object omitting `keypairs` throws no TypeError (and is
  handled as empty by the corruption-recovery path).
- Files: `lib/services/profile_repository.dart`.

### W6-6 — Dapps runner: generalize copy + Versions tab [P2] (UX W6-3, W6-4)
- W6-3: generalize `_kKeylessStatusHint`/`_kCreateProfileToVoteLabel` to
  dapp-agnostic copy, or make per-dapp via descriptor.
- W6-4: investigate why "Versions" tab renders blank (likely
  Column/Expanded/height collapse). Fix so "Version History" / "No version
  history" empty-state shows. If backend `/scripts/:id/versions` is 404, hide
  the tab when no versions OR implement the route. RED test: tab shows content.
- Files: `lib/screens/dapp_runner_screen.dart`, `lib/config/example_dapps.dart`,
  `lib/widgets/script_details_versions_tab.dart`, `script_details_dialog.dart`.

### W6-7 — Settings: fix dead external links [P2] (UX W6-5)
- Point Documentation → `https://github.com/sasa-tomic/icp-cc`,
  Report Issue → `https://github.com/sasa-tomic/icp-cc/issues` (verified 200).
- Files: `lib/screens/settings_screen.dart`.

### W6-8 — Search no-match: distinct empty state [P2] (UX W6-6)
- When search box non-empty + filtered list empty → show "No scripts match
  '<query>' — clear search" (distinct from genuine "library empty").
- Files: `lib/screens/scripts_screen.dart` / state.

### W6-9 — Misc robustness [P3] (A-W6-9,10,11,12)
- `isLocalDevelopment`: parse URI host vs explicit dev-host set (drop `.local`
  substring).
- IC proxy: `unwrap_or_default()` → match with `BAD_GATEWAY` on body-read error.
- Candid registry host: `kCandidRegistryHost` const.
- `formatPrincipal`: drop the `contains('-')` "validation" pretence; just
  normalise case for display (or use the FFI principal parser).
- Files: `app_config.dart`, `ic_proxy.rs`, `candid_service.dart`,
  `data_transformer.dart`.

### W6-10 — a11y + icon polish [P3] (UX W6-7,8,9,10)
- `ModernEmptyState`: drop redundant `Semantics(label:)` wrappers (Text already
  exposes the string) — stops double-announcement.
- Details canister id: full id, monospace, tap-to-copy (mirror Account screen).
- Persist `iconUrl` (and emoji) on local `ScriptRecord` at download → installed
  scripts keep artwork.
- Tappable cards (canisters/dapps) → `Semantics(button: true, label: …)` /
  split sub-actions into focusable buttons.
- Files: `modern_empty_state.dart`, details dialog, `scripts_list_item_tile.dart`
  / script_repository download path, `well_known_canisters.dart`, `dapps_screen.dart`.

### W6-11 — Test helper: make `generateTestSignatureSync` REAL [P1] (TQ-W6-1)
- It currently emits a DJB2 hash (docstring claims "real cryptographic").
- Fix: make it produce a REAL Ed25519 signature. The cryptography package is
  async, so pre-compute + cache real signatures keyed by (publicKey, payload)
  during the async `ensureInitialized`, OR migrate the ~4 consumers to the async
  `generateTestSignature`. Prefer the honest async migration where callers can
  be async; otherwise cache real signatures at init.
- Fix the lying docstring regardless. Ensure real-signature consumers
  (`script_repository_api_test.dart:299,348`) still pass.
- Files: `test/shared/test_signature_utils.dart`, `unified_test_builder.dart`,
  consumers.

### W6-12 — Test cleanup: loud guards + drop tautologies + rewrite swarm [P2] (TQ-W6-3,4,5)
- `native_bridge_js_smoke_test.dart`: one `setUpAll` asserting lib loaded (fail
  loud) OR `@Skip('requires libicp_core')` — drop every per-test silent return.
- Drop the 2 `isA<bool>()` tautologies (keyboard_shortcuts, vault_crypto).
- Drop the 2 overlapping marketplace error tests (superseded by error_test).
- Fold/trim `fake_passkey_authenticator_test.dart` (keep 1 structural + 2
  negatives).
- Rewrite the `throwsA(isA<Exception>())` swarm (~11) to assert the specific
  error type/message.
- Files: various test files.

### W6-13 — Backend auth/recovery/middleware tests [P1] (TQ-W6-2)
- Add integration tests for: passkey register/authenticate round-trip + negative
  (mismatched challenge, delete-last); recovery generate/verify/status (one-shot,
  exhaust-all); auth middleware (missing/invalid/expired token → 401, admin
  guard). Follow existing `backend/tests/*` harness (real in-memory SQLite, real
  schema — NO service-layer mocks).
- Files: `backend/tests/*`.

## §3. Execution order + parallelism

Serialized git index. Parallelizable batches (no file overlap):
- **Batch A (frontend services):** W6-3, W6-4, W6-5 (all marketplace service +
  profile repo).
- **Batch B (backend):** W6-2, W6-9-backend, W6-13.
- **Batch C (screens/UX):** W6-1, W6-6, W6-7, W6-8, W6-10.
- **Batch D (tests):** W6-11, W6-12.

Suggested sequence: P1 first (W6-1, W6-2, W6-11, W6-13), then P2, then P3.

## §4. Success criteria (Definition of Done)
- User-visible change reachable from the running app (for UX WUs).
- `flutter analyze` clean; cited tests green; `cargo nextest`+`clippy` green.
- No silent errors; single-source constants; typed errors not heuristics.
- Confidence ≥ 8/10. One commit per unit.

## §5. Change log
| WU | Commit | Summary |
|----|--------|---------|
| plan | `<tbd>` | Wave-6 plan committed |
