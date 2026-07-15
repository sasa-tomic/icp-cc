# 2026-07-15 — Unified E2E Harness (Desktop + Web) + Functional/Visual Sweep

- **Status:** PLANNING → IN PROGRESS
- **Surfaces:** (per human steering 2026-07-15) **"TUI" = Flutter Linux desktop (native)**;
  **"Web UI" = Flutter Web**. (No terminal UI exists in this repo.)
- **Predecessors:** Wave-7 (`2026-07-14-wave7-issue-hunt.md`, COMPLETE). This initiative
  extends it on the test-harness + UX axis.

## §0. Baseline (measured 2026-07-15)
| Check | Verdict | Evidence |
|-------|---------|----------|
| Backend API | ✅ UP | `GET :37245/api/v1/marketplace-stats` → 200 `{totalScripts:3,totalDownloads:426}` |
| Browser | ✅ Playwright Chromium | `~/.cache/ms-playwright/chromium-1228/chrome-linux64/chrome`; playwright@1.61.1; node v22.23.1 |
| Flutter | ✅ 3.38.3 | `flutter doctor` only red = "no google-chrome" (we use Playwright's) |
| Native FFI | ✅ buildable | `target/release/libicp_core.so` |
| Desktop e2e today | ⚠️ slow | `integration_test/ux_probe/` = 16 files, **one app-boot per file**, 2 passes; **~15 min** (≈9–10 min is redundant build/load across 12 boots) |
| Web e2e today | ❌ NONE | `test/features/web/*` are unit/golden tests, not real-app web e2e |
| UX/verification tests | scattered | widget tests in `test/features/ux/`, `navigation/`, `onboarding/` — not unified |
| Web widget-test floor | ~4.6s warm | `flutter test -d chrome` cold 15.5s / warm 4.6s (Playwright chromium) |
| Flow catalog (Phase 0) | 98 flows | enumerated across 13 sections (first-run/profile/keypair/account/scripts/downloads/canisters/dapps/vault/passkey/settings/shortcuts/deeplink) |

## §1. Problem statement (what the human asked)
1. The app has "many functional and visual issues" — find them all, fix them.
2. Radically improve the **e2e harness for desktop + web** so it:
   - runs in **seconds**,
   - covers **ALL supported user flows**,
   - drives the **REAL app** (no stubs/mocks except at the smallest I/O boundary),
   - becomes the home for **all UI/UX verification tests**.
3. Optimize multi-step user actions (fewer clicks; keyboard-first).
4. Cross-cutting: quick dev cycle (seconds), loud/debuggable errors, tech-debt
   reduction (DRY/KISS/YAGNI, single-source constants, timeouts, no silent
   errors), test-swarm quality review, alignment check vs `HUMAN_EXPECTATIONS.md`,
   and a **no-mocks UX review** against the real running app.

## §2. Architecture — write flows ONCE, run on BOTH surfaces

### 2.1 Single flow catalog (`integration_test/e2e/flows/`)
A typed, exhaustive catalog of every supported user flow. **Single source of
truth for coverage.** Each entry:
```dart
class UserFlow {
  final String id;            // e.g. 'first_run.create_profile'
  final String name;          // human label
  final Set<FlowSurface> runsOn; // {desktop, web}
  final bool needsKeyring;    // desktop: mock Secret Service required
  final Set<String> tags;     // for fast subset runs: 'smoke', 'marketplace', ...
  final Future<void> Function(E2EDriver d) run;
}
```
Coverage matrix + "which flows are tested" is derived from this list → trivial to
audit and extend. This directly answers the human's "easy to list / add flows".

### 2.2 Shared platform-agnostic flow code
Flows are written with Flutter `integration_test` finders/testers — which work
identically on **desktop** (Xvfb) and **web** (Chromium). **One implementation
runs on both surfaces** (DRY). Surface-specific divergence (e.g. real passkey
authenticator only on web) is encoded via `runsOn` + a tiny `E2EDriver.surface`
shim — never duplicated flows.

### 2.3 Desktop runner — FAST (2 boots, not 16)
- Boot the real app **once per keyring-mode**, run all flows in that mode in ONE
  `flutter test` process with **per-flow state isolation** (wipe
  `~/.cache/data/com.example.icp_autorun/` + secure-storage keys before each flow).
- Result: **2 app boots total** (keyring-less + mock-keyring) instead of 16.
- `just e2e` (both surfaces), `just e2e-desktop`, `just e2e-web`,
  `just e2e-fast <tag>` (subset, for sub-second dev loop).

### 2.4 Web runner — NEW, REAL app via Playwright Chromium (TWO TIERS)
> **Empirical correction (Phase 0):** on Flutter 3.38.3 `flutter test -d chrome`
> **rejects `integration_test/` files** ("Web devices are not supported for
> integration tests yet"). It DOES run `flutter_test` (widget) tests headless
> (~4.6s warm). Full real-app web boot requires `flutter drive` + Xvfb + a
> Chrome-149-matching **chromedriver** (~60s+ cold). Playwright Chromium binary
> confirmed at `~/.cache/ms-playwright/chromium-1228/chrome-linux64/chrome`.

- **Tier 1 — fast (`just e2e-web`, ~seconds):** the flow catalog authored as
  widget tests (`pumpWidget(KeypairApp())` + real backend via
  `--dart-define=PUBLIC_API_ENDPOINT=http://127.0.0.1:<port>`,
  `CHROME_EXECUTABLE=<playwright chromium>`). `flutter test -d chrome`. This is
  the dev-loop surface: covers everything exercisable through the widget tree
  (browse/search/filter/details/download/flows/vault crypto/profile/settings…).
- **Tier 2 — full boot (`just e2e-web-drive`):** `flutter drive` +
  `test_driver/integration_test.dart` adapter + Xvfb :97 + chromedriver :4444, for
  flows needing real platform integration (WebAuthn passkey register/delete,
  deep-link boot path). Heavier; reserved for those flows.
- The **same flow implementation** is reused across Tier 1 and Tier 2 (and desktop),
  since `tester.tap/enterText/pump` are binding-agnostic. The catalog selects tier.
- Web bundle reaches the **real backend** (confirmed live; CORS-correct IC relay at
  `/api/v1/ic/*` verified returning mainnet cbor). The ONLY mock is the outbound
  **ICPay checkout** (`icpay.org` unreachable from sandbox) — at the smallest
  boundary (the outbound HTTP call), gated loudly by `--dart-define=ICP_E2E_MOCK_ICPAY=1`.
- Note: `secp256k1` is now REAL on Web too (`docs/BROWSER_SUPPORT.md:104-107`);
  `TODO.md:89` "secp256k1 stubbed" is STALE and will be reconciled.

> **Phase 1 H-3 AS-BUILT (empirical, committed):** the two-tier assumption above
> was refined by implementation. Findings:
>
> - **Tier 1 (`flutter test -d chrome`) — WORKS but is STRUCTURE-ONLY.** It runs
>   under `TestWidgetsFlutterBinding`, which (a) returns **HTTP 400 for every
>   network call** and (b) registers **no real plugins** (`shared_preferences`,
>   `path_provider`, `app_links` throw `MissingPluginException`). The REAL app
>   DOES boot (`pumpWidget(KeypairApp())` mounts `MaterialApp`, the conditional
>   import loads the real pure-Dart `native_bridge_web.dart`, `secp256k1`/Ed25519
>   run), so Tier 1 asserts the **cross-surface contract** (catalog compiles,
>   production tree mounts). Real-network flows CANNOT run here. Loading real
>   state needs plugin **substrate fakes** (`SharedPreferences.setMockInitialValues`
>   …) — honest platform substrate (like Xvfb), NOT business mocking; lands in
>   Phase 2. `just e2e-web` ships this smoke (~9s, green).
> - **Tier 2 (`flutter drive` web) — BLOCKED on Flutter 3.38.3.** Chrome for
>   Testing 149 launches under chromedriver ONLY with three container flags
>   (`--no-sandbox --disable-gpu --disable-dev-shm-usage`; a `google-chrome`
>   symlink on PATH is also needed). But `flutter drive -d chrome
>   --target=<integration_test>` then fails at **web DEBUG COMPILE on Flutter's
>   OWN framework code** — `<invalid>` exhaustiveness errors in
>   `cupertino/colors.dart:1024` + `material/tooltip.dart:827` (not app code;
>   cache-clear doesn't help). This is the `integration_test`-on-web gap; the
>   repro is kept at `integration_test/e2e/web_drive_smoke_test.dart`. When
>   Flutter ships working integration_test-on-web, the desktop `FlowRun` bodies
>   move over **unchanged** (same `WidgetTester` + `E2EDriver` API).
> - **Net:** desktop is the primary real-app e2e surface (2 boots, ~all flows);
>   web Tier 1 proves the contract compiles + boots; real-network web e2e is a
>   tracked follow-up gated on Flutter, not on this codebase.

### 2.5 Debug hooks (so WE can directly drive + dump)
- `--dart-define=ICP_E2E=1` enables a test-only `E2EBridge`:
  - exposes current app state (active screen, profile count, vault state) via
    semantics labels the harness asserts on,
  - a programmatic navigation entry for flows that otherwise need many clicks,
  - a structured **state dump** on failure (last screen, pending snackbars).
- This is a test affordance over the real app, NOT a mock. Production code path
  is unchanged; the bridge only adds observability + a nav shortcut.

## §3. Phases & work units
> Each unit: PoC-first / RED-test-first, one commit, `flutter analyze` clean +
> green tests + `just` target wired. Serialized top-level commits (shared tree).

### Phase 0 — Recon grounding (subagents, read-only)
- **R-0a** enumerate every supported user flow from screens/controllers/wizards → flow catalog seed.
- **R-0b** measure current `ux_probe` wall-time; confirm web build/endpoint mechanism; confirm Playwright chromium drives `flutter test -d chrome`.

### Phase 1 — Harness skeleton
- **H-1** flow catalog + `E2EDriver` + per-flow isolation helper (desktop).
- **H-2** desktop fast runner (2 boots); `just e2e-desktop` + `just e2e-fast`.
- **H-3** web runner (Playwright chromium); `just e2e-web`; CI-ready.
- **H-4** `E2EBridge` debug hooks (state dump + nav shortcut), gated by dart-define.

### Phase 2 — Migrate + author flows (TDD), grouped to fold setup/teardown
Migrate the high-value `ux_probe` flows + `test/features/{ux,navigation,onboarding}`
verification tests into the catalog; add missing coverage. Group flows sharing
expensive setup. Positive + negative + edge per flow.

### Phase 3 — Issue hunt (real-app, no mocks) + fixes (RED→GREEN)
- Desktop: Xvfb + screenshots of every screen; web: Playwright screenshots + DOM.
- Catalog functional/visual issues with evidence; fix one commit each (TDD).

**Seed issue list (discovered empirically in Phase 0, each = RED test → fix → GREEN):**
- 🟥 **F1 `/recovery` route is dead** — `vault_unlock_screen.dart:146` does
  `Navigator.pushNamed('/recovery')` but `main.dart` registers no routes table;
  `RecoveryCodesScreen` is never instantiated → tapping "Use recovery code" throws.
  Backend `POST /recovery/generate` + `PasskeyService.generateRecoveryCodes` exist.
  Fix: wire a `/recovery` route + reach the screen (or remove the dead-end link).
- 🟥 **F2 Vault screens not reachable by navigation** — `VaultPasswordSetupScreen` /
  `VaultUnlockScreen` are only reachable programmatically; no menu entry. The ZK
  vault (a headline feature) is invisible to users. Fix: add a Vault tile in the
  profile menu that probes + routes to setup/unlock.
- 🟧 **F3 `_duplicateScript` "View" SnackBar action is a no-op** — empty body with
  TODO (`scripts_screen.dart:1156-1160`). Fix: implement (open the duplicate) or remove.
- 🟧 **F4 Passkey device name hardcoded "This Device"** — every passkey shows
  identically (`passkey_management_screen.dart:142`). Fix: derive a real label.
- 🟧 **F5 Profile rename/delete promised but missing in UI** —
  `_ManageProfilesSheet` subtitle says "Create, rename, or delete" but only offers
  switch+create; `ProfileController.deleteProfile`/`updateProfileName` have no UI.
  Fix: wire rename/delete into the manage sheet (or fix the misleading subtitle).
- 🟧 **F6 `f_dapp_vote_flow` fails (HTTP 530)** — marketplace/catalog fetch returns
  Cloudflare 1033; the headline dapp-vote e2e is red. Investigate + fix (endpoint
  reachability / fallback / the catalog boot path).
- 🟨 **F7 Dual profile-creation paths** — legacy `_CreateProfileDialog` coexists
  with `UnifiedSetupWizard` (inconsistent, not readiness-gated). DRY to one path.
- 🟨 **F8 Stale doc** — `TODO.md:89` claims secp256k1 stubbed on web; it's real.
  Reconcile the doc.
- *(more to be surfaced by the real-app screenshot/DOM pass in Phase 3/6)*

### Phase 4 — Click-reduction / keyboard-first UX
- Audit every common path's click count; add intuitive, clearly-indicated
  keyboard shortcuts; encode the optimized path in the matching e2e flow.

### Phase 5 — Tech-debt + test-swarm quality
- DRY duplicated harness patterns; single-source constants; timeouts on all I/O;
  no silent errors; drop low-signal/overlapping tests; fold shared setup.

### Phase 6 — UX review (real app) + alignment
- tmux/Xvfb desktop boot + Playwright web boot as a real user; screenshot+DOM
  analysis; remove any AI slop/stubs; fix anything stuck on a spinner.
- Alignment check vs `HUMAN_EXPECTATIONS.md` (update doc if guidance shifted).

### Phase 7 — Verify + report
- `flutter analyze` clean; full `just test` + `just e2e` green; coverage matrix;
  update TODO.md; final verdict.

## §4. Confidence
- Architecture (one flow impl, two surfaces; fast shared-boot desktop runner;
  Playwright web): **9/10** correct, **9/10** safe.
- "Seconds" for web is aspirational (Flutter web cold boot is inherently slower);
  we target seconds for desktop + tagged subsets, and minimal rebuild for web via
  flutter's build cache. Flagged honestly below.
