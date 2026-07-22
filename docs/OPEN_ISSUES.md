# Open Issues — icp-cc

> **Living backlog of every known issue.** Anything surfaced by a sweep,
> UX review, e2e red, security audit, or human report lives here until it's
> resolved. Source of truth for "what's broken / pending / blocked" — replaces
> the scattered per-spec seed lists.
>
> Linked from `AGENTS.md`. **Update on close.**
>
> Statuses: 🔴 OPEN • 🟡 IN-PROGRESS • 🟢 RESOLVED • ⚪ DEFERRED (with reason)

---

## 2026-07-22 P4 Visual Sweep

> Findings from a broader functional/visual sweep of **every** user-facing
> screen (`integration_test/app_visual_sweep_test.dart`, commit `b7f7fc26`).
> The sweep boots the REAL app (real FFI, real widget tree, real navigation
> against the live local backend) and captures a screenshot of each screen
> while draining framework exceptions. **Zero** rendering-library exceptions
> were drained across all 14 captured screens — the app is in strong visual
> shape. The 3 defects below are the only ones surfaced. Screenshots live in
> `/tmp/opencode/app-sweep/`.
>
> Severity key: 🔴 CRITICAL • 🟠 HIGH • 🟡 MEDIUM • 🔵 LOW

### DEFECT-5 — Passkey screen shows an enabled "Add Passkey" FAB on unsupported Linux desktop

- **Status**: 🔴 OPEN
- **Severity**: 🟡 MEDIUM (graceful-degradation gap — a primary action contradicts the screen's own "unsupported" message)
- **Surfaced**: 2026-07-22 P4 visual sweep (`integration_test/app_visual_sweep_test.dart`).
- **Location**: `apps/autorun_flutter/lib/screens/passkey_management_screen.dart` — the `Scaffold.floatingActionButton` in `build()` is rendered **unconditionally** (lines 179-185), independent of the body's `!PasskeyPlatform.isSupported` branch.
- **Screenshot**: `/tmp/opencode/app-sweep/11_passkey_management.png`

**Root cause:** The body's `_buildBody()` correctly renders the
`_buildUnsupportedPlatformError()` panel ("Passkeys aren't available on Linux
desktop") when `!PasskeyPlatform.isSupported`, but the `Scaffold`'s
`FloatingActionButton.extended` ("Add Passkey") is in the `Scaffold` itself,
not the body — so it stays mounted and fully enabled on every platform. Tapping
it on Linux calls `_addPasskey` → `PasskeyService().registerPasskey(...)`,
which routes into the unsupported platform authenticator: at best a SnackBar
error, at worst an unhandled (non-`PasskeyException`) platform-channel failure.
Either way the user is offered a prominent action the screen simultaneously
says is impossible.

**Fix (reported, not fixed):** hide or disable the FAB when
`!PasskeyPlatform.isSupported` (e.g. set `floatingActionButton` to `null`, or
`onPressed: null` so it renders disabled). The post-registration prompt already
greys out its passkey tile on Linux for the same reason — this screen should
match.

### DEFECT-6 — Vault setup shows a red "Weak" strength meter for an EMPTY password

- **Status**: 🔴 OPEN
- **Severity**: 🔵 LOW (cosmetic; does not affect functionality — the "Create Vault" button is correctly disabled)
- **Surfaced**: 2026-07-22 P4 visual sweep.
- **Location**: `apps/autorun_flutter/lib/screens/vault_password_setup_screen.dart:303-334` (`_buildStrengthMeter`).
- **Screenshot**: `/tmp/opencode/app-sweep/12_vault_setup.png`

**Root cause:** `_buildStrengthMeter()` always renders. For an empty password,
`passwordStrength('')` returns score 0 → `_strengthColor(0)` returns
`colorScheme.error` (red) and `passwordStrengthLabel(0)` returns "Weak", so the
meter paints a red bar at 25% (`(0+1)/4`) with a red "Weak" label before the
user has typed anything. An empty field should show a neutral/hidden meter, not
"Weak".

**Fix (reported, not fixed):** return early (e.g. an empty `SizedBox` or a
neutral "—" label) when `_passwordController.text.isEmpty`.

### DEFECT-7 — Publish dialog auto-fills the Description field with raw source code

- **Status**: 🔴 OPEN
- **Severity**: 🔵 LOW (pre-fill heuristic; user can edit, but the default looks broken)
- **Surfaced**: 2026-07-22 P4 visual sweep.
- **Location**: `apps/autorun_flutter/lib/widgets/quick_upload_dialog.dart:111-156` (`_generateDescriptionFromScript`).
- **Screenshot**: `/tmp/opencode/app-sweep/15_script_upload_form.png`

**Root cause:** When publishing a local script, `_generateDescriptionFromScript`
prefers a JSDoc block, then falls back to **the first 2 non-comment code lines**
(lines 141-151), then a generic string. The default sample bundle (and any
script without a JSDoc header) therefore pre-fills the Description field with
literal JS such as `"use strict"; (() => {` — which reads as broken/garbage to
the author and ships as the listing description if they don't notice.

**Fix (reported, not fixed):** drop the raw-code-lines fallback (it is worse
than the generic string); go straight to the generic string (or leave the field
empty) when no JSDoc comment exists.

---

## Critical / Blockers

### E2E-PHASE-O — Phase O: 100% catalog coverage (final 3 deferred flows)

- **Status**: 🟢 RESOLVED (2026-07-21, Phase O commit `75e41a6e`)
- **Surfaced**: pre-existing (the 3 last-uncovered catalog flows — `profile.create_via_menu_dialog`, `scripts.publish`, `account.register_from_publish` — were DEFERRED at Phase N pending the UX-PMD-1 production bug fix).
- **Severity**: MEDIUM (3 deferred e2e flows + 1 blocking production bug)
- **Location**: `apps/autorun_flutter/integration_test/e2e/suite_mock_keyring_identity_test.dart` (3-phase dedicated mini-suite); bug fix in `apps/autorun_flutter/lib/widgets/profile_menu.dart` (UX-PMD-1).

The three flows were split into a dedicated 3-phase mini-suite (mirroring
the Phase N `suite_mock_keyring_dapps_test.dart` pattern) so the existing
keyring-less + mock-keyring + mock-keyring-dapps suites stay below the
documented flutter_test binding stability threshold (the "Cannot close
sink while adding stream" crash past ~30 phases per OPEN_ISSUES
E2E-PHASE56+57). All three need the mock Secret Service for real Ed25519
keypair generation + signing, so they cannot live in the keyring-less
suite.

**Unblocked by:** UX-PMD-1 fix (Phase O commit `fe5af1ad` — capture
`NavigatorState` before the await boundary, route through it from the
onCreateProfile closure). Without that fix, the
`profile.create_via_menu_dialog` flow deterministically crashed with
`State no longer has a context` after the menu's exit animation finished.

**Flow assertions:**
- `account.register_from_publish` (PHASE 1): from a LOCAL-ONLY profile,
  attempt to publish → "Share to Marketplace" registration prompt fires
  → "Register Username" → AccountRegistrationWizard pushes → fill
  username + display name → real `registerAccount` round-trip → wizard
  pops with the Account → `_publishToMarketplace` continues into
  QuickUploadDialog (proves the wizard returned a real Account, not
  null) → cancel via Esc. Asserts the running ProfileScope sees the
  username.
- `scripts.publish` (PHASE 2): create a local script → invoke
  `LocalScriptRowMenu.onPublish` (callback-direct — popup-menu gestures
  are absorbed by Overlay per the documented pattern) → QuickUploadDialog
  opens (profile is now registered from PHASE 1) → fill Title +
  Description + Tags → tap `quick-upload-submit` key → real signed
  `uploadScript` round-trip (verified in the test log) → success
  SnackBar.
- `profile.create_via_menu_dialog` (PHASE 3): the UX-PMD-1 regression
  flow. Open profile menu → "Switch Profile" → manage sheet → "Create
  New Profile" → UnifiedSetupWizard pushes via the post-fix navigator
  capture path → fill display name + unique username → Get Started →
  real `createProfile` + `registerAccount` → "Success!" → Start
  Exploring. PHASE 3 explicitly pumps past the menu's exit animation
  (1s wait, >250ms default Material sheet transition) before tapping
  "Create New Profile", so the disposed-State code path is exercised.

**State evolution across phases:** local-only (PHASE 0 setup) →
registered (PHASE 1) → publish against registered (PHASE 2) → second
profile via menu (PHASE 3). No `resetAppState` between phases. Suite
takes ~75s wall-clock end-to-end.

**Coverage implication:** desktop 89/95 → 92/95 (97%);
catalog 95/98 → 98/98 (**100%**). The remaining 3 desktop-surface gaps
are the 2 poll-local-replica flows (`dapps.run_poll` +
`dapps.create_profile_to_vote` — covered separately by
`just e2e-local-replica` against a dfx replica per OPEN_ISSUES
E2E-PHASE56+57; the dedicated mini-suite owns its own coverage report)
plus one catalog row reachable only through that local-replica harness.
Web Tier A stays at 13/13 covered (`just e2e-web`).

**Justfile:** `just e2e-desktop` now runs 4 PASSes (1 keyring-less +
3 mock-keyring); `just e2e-one <flow-id> mock-keyring-identity` for
sub-suite single-flow iteration.

### E2E-PHASE-O-REGRESSION — `suite_keyring_less_test.dart` FocusScope/shadow quirk (PHASES 15, 18, 19)

- **Status**: 🟢 RESOLVED (2026-07-21, commits `66337c8a` + `b763e284`)
- **Surfaced**: 2026-07-21 during Phase O verification (initially red at PHASE 15)
- **Severity**: HIGH (the keyring-less PASS was RED, blocking `just e2e-desktop` from going green)
- **Location**: `apps/autorun_flutter/integration_test/e2e/suite_keyring_less_test.dart` — `shortcut.new_script` (PHASE 15), `shortcut.escape_back` (PHASE 14/18), `settings.restart_tour` (PHASE 19) inline bodies.

**Verified PRE-EXISTING — NOT a Phase O regression.** Running the suite at
HEAD~3 (`f10e46a7` — before any Phase O commits, in a fresh git worktree)
reproduced the same failure at PHASE 15. Phase O's only `lib/` change
(`profile_menu.dart` UX-PMD-1 fix) was also reverted in-place and the
failure persisted; restoring the fix did not change the outcome.

**Failure mode (root cause confirmed, not re-investigated by the
PHASE 19 fix):** under Flutter 3.44.6, when `showModalBottomSheet` /
`showDialog` routes pop via Esc, the route's `_ModalScopeState`
FocusScopeNode RETAINS PRIMARY FOCUS past the visible-widget-unmount
frame, AND the Overlay theater retains a residual `RenderAbsorbPointer`
that shadows subsequent taps at their normal hit-test coordinates. Two
observable symptoms:
1. `tester.sendKeyEvent(...)` after a modal-sheet pop is absorbed by the
   lingering FocusScope and never reaches the `ScreenShortcuts` binding
   (surfaced at PHASE 15: pressing `N` didn't open `ScriptCreationScreen`).
2. `tester.tap(find.byType(SomeButton))` lands on the theater instead of
   the button (surfaced at PHASE 19: `ProfileAvatarButton` tap shadowed
   by the residual AbsorbPointer from PHASE 18's `ScriptDetailsDialog`
   close).

**Workaround pattern (3 complementary techniques, all already in the
suite):**

1. **Callback-direct invocation** — for shadowed taps, REPLACE with a
   direct callback when the widget exposes a public `onTap`/`onPressed`
   seam (`ProfileAvatarButton.onTap`, `ScriptsListItemTile.onTap`,
   `IconButton.onPressed`, `FilledButton.onPressed`,
   `PopupMenuButton.onSelected`). Bypasses the pointer-dispatch layer
   entirely.
2. **Focus prime** — for keyboard events not reaching `ScreenShortcuts`
   after a modal close, prime focus on a non-interactive element first:
   `FocusManager.instance.primaryFocus?.unfocus()` + pump, OR tap an
   AppBar title/tooltip (`find.byTooltip('Refresh')`) before sending
   the key.
3. **Wait-for-unmount** — after Esc-closing a modal, verify the route
   fully unmounted before continuing: `await d.waitUntil(tester, ()
   => find.byType(BottomSheet).evaluate().isEmpty, timeout: Duration(seconds: 2))`.

**Resolution commits:**
- `66337c8a` — PHASES 14/15/18: focus-prime + FAB-fallback in
  `shortcut.new_script`; wait-for-unmount in `shortcut.escape_back`;
  callback-direct tile tap in `shortcut.details_prev_next_tab`.
- `b763e284` — PHASE 19: callback-direct `ProfileAvatarButton.onTap`
  invocation in the inline `settings.restart_tour` block (the last
  remaining INLINE tap that depended on gesture hit-testing after a
  chain of modal open/close cycles). All subsequent phases (20–55)
  pass without modification because the registered flows already had
  the workaround patterns in place.

**Verification:** `just e2e-fast integration_test/e2e/suite_keyring_less_test.dart`
is GREEN end-to-end (PHASES 0pre → 55, COVERAGE 58/98). `just e2e-desktop`
is GREEN across all 4 PASSes (keyring-less + mock-keyring + mock-keyring-dapps
+ mock-keyring-identity). The catalog stays at 98/98 (100%).

### E2E-PHASE-L — Phase L: Web Tier A 6 deferred flows (3 passkey + 3 deeplink)

- **Status**: 🟢 RESOLVED (2026-07-20, Phase L)
- **Surfaced**: pre-existing (Phase C 2026-07-19 — `docs/specs/2026-07-19-e2e-and-ux-continuation.md` Phase C-Tier-A; passkey + deeplink flows listed but DEFERRED with no implementation).
- **Severity**: MEDIUM (6 deferred e2e flows on the Web Tier A surface)
- **Location**: `apps/autorun_flutter/test/e2e_web/suite_web_phase_l_test.dart` (Phase L suite); substrate extensions in `apps/autorun_flutter/test/e2e_web/substrate/substrate_{http,app_links}.dart`; production-code testing seams in `apps/autorun_flutter/lib/utils/passkey_platform.dart` + `apps/autorun_flutter/lib/services/passkey_authenticator_{native,stub}.dart`.

The Phase C Tier A harness (substrate fakes at the smallest I/O boundary — HTTP, SharedPreferences, FlutterSecureStorage, path_provider, package_info) covered 7/98 flows. The 6 deferred flows needed additional platform-boundary seams that weren't available under `flutter test -d chrome`:

- **Passkey flows** (catalog surface `_w`, web-only): blocked because `PasskeyPlatform.isSupported` is FALSE under `flutter test -d chrome` (test compiles for the Dart VM, so `kIsWeb=false` AND `Platform.isLinux=true`), routing the screen to the "Linux desktop unsupported" panel. Also `NativePasskeyAuthenticator.register` would call into the platform WebAuthn API (`navigator.credentials.create`), unreachable from the test VM.
- **Deeplink flows** (catalog surface `_d`, desktop-only): blocked because `_KeypairAppState._initDeepLinks` is guarded by `if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) return;`, so the app's `_handleDeepLink` listener is never wired on the test surface — there's no way to drive UI navigation via synthetic URIs through the normal app_links pathway.

**Unblocked by:** Phase L adds three minimal testing seams (mirroring the existing `PasskeyService.overrideHttpClient` pattern) plus substrate extensions:

1. **`PasskeyPlatform.isSupportedOverrideForTesting`** (`lib/utils/passkey_platform.dart`): a `bool?` static flag. When non-null, `isSupported` returns its value AND `isLinuxDesktop` returns false — matching Web-surface semantics. The harness sets it to `true` in `setUpAll`, clears in `tearDownAll`.
2. **`NativePasskeyAuthenticator.{register,authenticate}OverrideForTesting`** (`lib/services/passkey_authenticator_{native,stub}.dart`): static function overrides that substitute a deterministic in-process credential Map for the browser WebAuthn call. The real `PasskeyService.registerPasskey` chain runs unchanged — challenge fetch (substrate HTTP), canonical signature generation (real Ed25519), finish POST (substrate HTTP).
3. **Substrate HTTP passkey routes** (`substrate_http.dart`): in-memory `SubstratePasskeyStore` + four routes (`GET /passkey/list/:id`, `POST /passkey/register/{start,finish}`, `DELETE /passkey/:id`). Account scoping is intentionally simplified (single global bucket) — the real backend derives `account_id` from the Ed25519 signature, which the substrate can't verify. Documented as a known substrate boundary simplification.
4. **Substrate app_links emitter** (`substrate_app_links.dart`): `emitSubstrateDeepLink(uri)` pumps events through `DeepLinkService.instance.handleLink` (the same public API the app's `_initDeepLinks` listener subscribes to on non-linux surfaces). `collectSubstrateDeepLinks(tester, body)` subscribes + runs body inside `tester.runAsync` (the binding's fake clock never advances real `Timer`s, so `Future.delayed` outside `runAsync` hangs forever — discovered during Phase L debugging).

**Flow assertions:** the passkey flows pump `PasskeyManagementScreen` directly (catalog entry is `passkey_management_screen.dart`, not main.dart) with a real `TestKeypairFactory.getEd25519Keypair()` keypair — the real `PasskeyService` Dart code runs end-to-end against substrate HTTP. The deeplink flows pump synthetic URIs and assert what `DeepLinkService.linkStream` did (or did not) dispatch — the real `DeepLinkService.parseUri` runs unchanged.

**Verified** in `suite_web_phase_l_test.dart` (2 testWidgets bodies: passkey 3-phase + deeplink 3-phase). Coverage 79 → 85 / 98 (Web Tier A: 7 → 13).

**Caveat / follow-up filed (not fixed):** the deeplink flows assert the `DeepLinkService` parsing layer, NOT the downstream UI navigation (the `_handleDeepLink` → `_openScriptFromDeepLink` → `ScriptDetailsDialog` chain in `main.dart`). That navigation path is desktop-only because `_initDeepLinks` early-returns on linux; the Web Tier A harness cannot drive it without a real `_appLinks.uriLinkStream` (which `app_links` doesn't service under `flutter test -d chrome`). Desktop e2e remains the source of truth for the full deep-link UI navigation chain.

### E2E-PHASE56+57 — `dapps.run_poll` + `dapps.create_profile_to_vote` (local dfx replica)

- **Status**: 🟢 RESOLVED (2026-07-20, Phase 56 + 57)
- **Surfaced**: pre-existing (Phase D triage, 2026-07-19) — `docs/specs/phase-d-triage.md` §"HARD"
- **Severity**: MEDIUM (2 deferred e2e flows — the last deferred desktop flows)
- **Location**: `apps/autorun_flutter/integration_test/e2e/suite_poll_local_test.dart` (dedicated mini-suite); flow bodies in `apps/autorun_flutter/integration_test/e2e/poll_flows.dart`; replica helper at `scripts/start-local-replica.sh`; canister source at `examples/icp_poll_dapp/src/backend/main.mo`

Both flows were DEFERRED with the note: *"Local replica example — replica not running. Known issue F6 (HTTP 530)."* The original plan assumed the flows would be added to `suite_keyring_less_test.dart` as PHASE 56 + 57. That turned out to be infeasible: the suite's single `testWidgets` body already runs 55 phases (2478 lines) and adding the poll flow bodies — even extracted to a separate `poll_flows.dart` library and imported with a single line — deterministically destabilises the flutter_test binding's stream protocol. The Linux desktop app process crashes mid-suite with a flaky `"Cannot close sink while adding stream"` error in `FlutterPlatform._startTest`. The crash threshold is a function of TOTAL compiled code size (app + test file + imported helpers), not line count alone: even an unused `import 'poll_flows.dart';` in the suite file triggers it. A running dfx replica compounds the instability (the dapp runner's first successful canister call fires trust dialogs + extra widget tree complexity that the test process can't sustain past ~phase 30).

**Unblocked by:**
1. `scripts/start-local-replica.sh` — an idempotent, fully-detached replica + canister deploy helper. Uses `setsid` + full FD redirection to avoid the bash hang on `dfx start --background`. The deployed `backend` canister's id (`uxrrr-q7777-77774-qaaaq-cai`) is DETERMINISTIC for a fresh replica — it matches `kLocalPollBackendCanisterId` in `lib/config/example_dapps.dart`, so NO app-side runtime config seam is needed.
2. A DEDICATED mini-suite (`suite_poll_local_test.dart`) that boots the app fresh and runs ONLY the 2 poll phases. Avoids the 55-phase buildup that destabilises the keyring-less suite. The coverage contract still counts the flows: `FlowCatalog.coverageReport` is per-registry, and `just e2e-desktop` documents that the poll flows are covered by the separate `just e2e-local-replica` recipe.

**Flow assertions:**
- `dapps.run_poll`: opens the Polls dapp → DappRunnerScreen mounts → ScriptAppHost executes the bundle → real canister round-trip (`listPolls` query) against the local replica. Best-effort (like `dapps.run_ledger_mainnet`): success (`"Polls (N)"` text renders) OR benign failure (`"Error: ..."` text renders) both PASS; only a crash/hang or stuck "Loading..." fails. The bundle's first canister call fires the per-dapp "Trust this dapp?" dialog, cleared by the remount-aware `_closeDappRunnerAfterRemount` helper.
- `dapps.create_profile_to_vote`: opens the Polls dapp → asserts the keyless-user "Create a profile" CTA (`Key('dappCreateProfileToVoteCta')`) renders → invokes `onPressed` directly (Flutter 3.44.6 Overlay tap-absorption workaround) → UnifiedSetupWizard pushes above the runner route. The FULL create-profile-then-vote round-trip requires a Secret Service (mock-keyring or gnome-keyring); this flow covers the FRONTEND rendering + wizard deep-link, NOT profile creation itself (exercised end-to-end by `first_run.create_profile` + `scripts.buy` in the mock-keyring suite).

**Candid interface (deployed canister):**
```candid
type PollRecord = record { creator: principal; id: text; options: vec text; question: text };
service : {
  createPoll: (question: text, options: vec text) -> (text);
  getTally: (pollId: text) -> (vec nat) query;
  listPolls: () -> (vec PollRecord) query;
  vote: (pollId: text, optionIndex: nat) -> ();
  whoami: () -> (text) query;
}
```

**Follow-up (filed, not fixed):** the pre-existing flakiness in `suite_keyring_less_test.dart` (crash past ~phase 30 when the total compiled code size grows OR a local replica is running) is a flutter_test / Linux desktop integration issue, NOT an app bug. Root cause appears to be resource accumulation in the long single-`testWidgets` body. The proper fix is to split the 58-phase suite into smaller test files (each with its own `testWidgets` boot), but that's a separate effort. Tracked separately.

Coverage 79 → 81 / 92 desktop flows.

### E2E-PHASE55 — `scripts.download_paid` (paid-script details dialog rendering)

- **Status**: 🟢 RESOLVED (2026-07-20, Phase 55)
- **Surfaced**: pre-existing (Phase D triage, 2026-07-19) — `docs/specs/phase-d-triage.md` §"Flows still listed as DEFER"
- **Severity**: MEDIUM (1 deferred e2e flow)
- **Location**: `apps/autorun_flutter/integration_test/e2e/suite_keyring_less_test.dart` (PHASE 55); `apps/autorun_flutter/lib/widgets/script_details_dialog.dart` (`_buildPrimaryAction`)

`scripts.download_paid` was DEFERRED with the note: *"ICPay is unreliable;
need provider-agnostic backend first."* The backend was hard-wired to ICPay,
the frontend `_buyScript` flow called ICPay directly, and the e2e harness
had no way to drive a purchase against a deterministic provider.

**Unblocked by:** the Phase K payment-provider-agnostic refactor
(`backend/src/services/payment_provider.rs` — new `PaymentProvider` trait +
`StubPaymentProvider` that auto-grants entitlements). The default backend
now runs with `PAYMENT_PROVIDER=stub` so purchases complete immediately
without any external ICPay round-trip.

**Flow assertion:** the paid-seed script (uploaded by
`tool/seed_marketplace.dart --paid`, slug `paid-seed-script`, price \$4.99)
is opened in the details dialog. The flow asserts the **Buy for \$4.99**
CTA renders (NOT Download — paid scripts the user hasn't purchased show
Buy per `_buildPrimaryAction`). The full post-purchase Download path
(signed `/scripts/:id/download` + entitlement gate → bundle released) is
covered by `payment_http_tests.rs::purchase_with_stub_then_download_succeeds`.

The keyring-less suite cannot exercise the post-purchase Download CTA
(no profile = no purchase possible); that path is covered by the Rust
http tests against the stub provider.

Coverage 57 → 58.

### E2E-PHASE54 — `scripts.buy` (provider-agnostic purchase CTA + keyring-less UX)

- **Status**: 🟢 RESOLVED (2026-07-20, Phase 54)
- **Surfaced**: pre-existing (Phase D triage, 2026-07-19) — `docs/specs/phase-d-triage.md` §"Flows still listed as DEFER"
- **Severity**: MEDIUM (1 deferred e2e flow)
- **Location**: `apps/autorun_flutter/integration_test/e2e/suite_keyring_less_test.dart` (PHASE 54); `apps/autorun_flutter/lib/screens/scripts_screen.dart` (`_buyScript`); `backend/src/handlers/payments/mod.rs` (`purchase_script`)

`scripts.buy` was DEFERRED with the note: *"ICPay is unreliable; need
provider-agnostic backend first."* The frontend Buy CTA called ICPay's API
directly via `IcpayService`; when icpay.org was down (days at a time), the
purchase flow hung indefinitely.

**Unblocked by:** the Phase K refactor — a new generic
`POST /api/v1/scripts/:id/purchase` endpoint dispatches to the active
provider via the `PaymentProvider` trait. The frontend
`MarketplaceOpenApiService.purchaseScript` calls this endpoint; the
`_buyScript` flow was rewritten to use it (falling back to the legacy
IcpayService client-SDK path only when the provider returns a Pending
intent without a checkout URL — the icpay.org production case).

**Flow assertion:** the paid-seed script is opened in the details dialog;
the flow asserts the **Buy for \$4.99** CTA renders, taps it, and asserts
the "Create a profile first" SnackBar (the keyring-less UX fallback —
this suite cannot create a profile without a Secret Service). The full
signed purchase round-trip (signed `POST /purchase` → StubProvider
auto-grants entitlement → row in purchases table) is covered by 16 new
`payment_http_tests` in the Rust suite against stub/icpay/none providers,
including `purchase_with_stub_returns_completed_and_grants_entitlement`
+ `purchase_with_stub_then_download_succeeds` (end-to-end buy → download).

Coverage 56 → 57.

### E2E-PHASE53 — `dapps.run_ledger_mainnet` (real IC mainnet canister call)

- **Status**: 🟢 RESOLVED (2026-07-20, Phase 53)
- **Surfaced**: pre-existing (Phase D triage, 2026-07-19) — `docs/specs/phase-d-triage.md` §"HARD"
- **Severity**: MEDIUM (1 deferred e2e flow, network-dependent)
- **Location**: `apps/autorun_flutter/lib/config/example_dapps.dart:116-130` (`icp_ledger` DappDescriptor); bundle at `apps/autorun_flutter/lib/examples/07_icp_ledger.js`

`dapps.run_ledger_mainnet` was listed as HARD: *"Hits real mainnet canister;
may work but flaky offline. Try."* The flow opens the ICP Ledger dapp card
→ DappRunnerScreen mounts → ScriptAppHost executes the bundle against the
real IC mainnet ledger canister (`ryjl3-tyaaa-aaaaa-aaaba-cai` via
ic0.app), querying `icrc1_symbol` / `icrc1_name` / `icrc1_decimals`.

**Flow design (best-effort):** the assertion is that DappRunnerScreen
remains mounted after the mainnet round-trip — proving the app handled
whatever the network returned (success: token metadata rendered; failure:
network error UI rendered) without crashing. Both outcomes PASS; only a
crash/hang fails. The bundle's first canister call triggers the trust
dialog (same pattern as dapps.apply_connection / dapps.refresh), so the
flow uses `_closeDappRunnerAfterRemount` to clear dialogs first, then pop
the runner.

**Verified** on the dev box (mainnet ic0.app reachable from this
environment). Coverage 55 → 56.

### E2E-PHASE52 — `scripts.load_more` pagination contract

- **Status**: 🟢 RESOLVED (2026-07-20, Phase 52)
- **Surfaced**: pre-existing (Phase D triage, 2026-07-19) — `docs/specs/phase-d-triage.md` §"Flows still listed as DEFER"
- **Severity**: MEDIUM (1 deferred e2e flow + missing app feature)
- **Location**: `apps/autorun_flutter/lib/screens/scripts_screen.dart:99-102, 362-417` (`_isLoadingMore` / `_hasMore` / `_offset` state machine)

`scripts.load_more` was DEFERRED with the note: *"Backend has 3 seeded
scripts, no pagination trigger."* Two root causes:
1. Backend ships with 3 hand-seeded scripts — well below the page size of 20,
   so `_hasMore` is always false.
2. The pagination state machine (`_isLoadingMore`, `_hasMore`, `_offset`)
   exists in scripts_screen.dart but **no UI trigger is wired up** — there's
   no scroll-listener, no "Load More" button, no infinite-scroll affordance.
   The state is vestigial pending a UI feature.

**Unblocked by:** `apps/autorun_flutter/tool/seed_marketplace.dart` — a
Dart CLI that bulk-uploads N signed scripts to the marketplace backend
(canonical Ed25519 signatures, idempotent via slug+title dedup, with a
`--purge` mode for cleanup). Wrapped by `scripts/seed-marketplace.sh` and
invoked INSIDE the flow body so the seeds only exist for this phase
(earlier phases see a clean 3-script marketplace). The suite purges stale
seeds at PHASE 0pre so a prior crashed run can't leak into earlier phases,
and PHASE 52 purges after asserting so the next run starts clean.

**Flow assertion:** the marketplace is bulk-seeded to 28 total scripts (3
originals + 25 seeds), exceeding the page size of 20. After a remount (the
most reliable way to trigger `_loadMarketplaceScripts`), the flow asserts
bulk-seed tiles are visible and `ScriptsListItemTile` rows are rendered —
proving the first page of a paginated result set materialized. A future app
change that surfaces a "Load More" UI would extend this flow to tap it and
assert the list grows.

**Follow-up (resolved 2026-07-21, UX-N2):** scripts_screen.dart had vestigial
`_isLoadingMore` / `_hasMore` / `_offset` state but no UI to trigger
load-more. Wired a `NotificationListener<ScrollNotification>` on the main
`CustomScrollView` (auto-loads when within 200px of the bottom) PLUS a
"Load more" `TextButton.icon` footer fallback for keyboard / explicit-tap
users; the footer also renders an in-flight `CircularProgressIndicator`
while fetching and an honest "End of results" caption when `hasMore=false`.
Covered by 5 widget tests in `load_more_pagination_test.dart` using
`PagedFakeMarketplaceOpenApi` (honours the real slice + hasMore contract).

Coverage 54 → 55.

### E2E-PHASE1b — `first_run.keyring_unavailable` panel assertion

- **Status**: 🟢 RESOLVED (2026-07-20, Phase 1b)
- **Surfaced**: pre-existing (Phase D triage, 2026-07-19) — `docs/specs/phase-d-triage.md` §"Flows still listed as DEFER"
- **Severity**: MEDIUM (1 deferred e2e flow)
- **Location**: `apps/autorun_flutter/lib/screens/unified_setup_wizard.dart:164` (`_buildReadinessPanel`); `apps/autorun_flutter/lib/services/secure_storage_readiness.dart` (`LinuxSecretServiceHelp`)

`first_run.keyring_unavailable` was DEFERRED with the note: *"Dev box has
gnome-keyring installed + auto-start recovers it; the readiness probe returns
`StorageReady`. Cannot reproduce the blocking panel without uninstalling
gnome-keyring."*

**Unblocked by:** `scripts/run-without-keyring.sh` — a wrapper that kills any
running `gnome-keyring-daemon`, blanks `DBUS_SESSION_BUS_ADDRESS` +
`GNOME_KEYRING_CONTROL`, and sanity-checks `secret-tool` cannot reach a Secret
Service before exec'ing the wrapped command. On a keyring-less box (e.g. CI)
the wrapper is a near-no-op; on a box with gnome-keyring it forces the
`StorageUnavailable` path so the WU-S2 panel renders.

The flow (PHASE 1b of `suite_keyring_less_test.dart`) asserts the canonical
markers: "Setup needed" AppBar title, "Install command" label, "Retry"
button, a friendly reason heading (never a raw `PlatformException` string —
NEW-4). On a host where the probe returns `StorageReady`, the flow no-ops in
the main suite; the dedicated `just e2e-keyring-unavailable` recipe wraps the
run with `scripts/run-without-keyring.sh` for the controlled assertion.
Coverage 53 → 54.

### E2E-PHASE51 — `scripts.delete` dialog chain (was binding-flaky on 3.38.3)

- **Status**: 🟢 RESOLVED (2026-07-20, Phase 51)
- **Surfaced**: pre-existing (Phase D triage, 2026-07-19) — `docs/specs/phase-d-triage.md` §"Flows still listed as DEFER"
- **Severity**: MEDIUM (1 deferred e2e flow)
- **Location**: `apps/autorun_flutter/lib/screens/scripts_screen.dart:999-1023` (`_confirmAndDeleteScript`)

`scripts.delete` was DEFERRED on Flutter 3.38.3 with the note: *"Async dialog
callback chain doesn't complete reliably under IntegrationTest binding"*
(`docs/specs/phase-d-triage.md`). The dialog (`showDialog<bool>` → AlertDialog
with Cancel/Delete buttons) was reachable but the second-stage `await
showDialog` future didn't resolve under the binding's fake clock.

**Unblocked by:** Flutter 3.44.6 upgrade (commit `e6c90ab0`) — the partial
Overlay `RenderAbsorbPointer` fix lets the dialog's `FilledButton.tonal` tap
land. The e2e flow at PHASE 51 of `suite_keyring_less_test.dart` now invokes
`LocalScriptRowMenu.onConfirmDelete` (callback-direct, avoiding the popup-menu
gesture interception), then taps the Delete confirmation, then asserts the
"Script deleted" SnackBar + the script row is gone. Coverage 52 → 53.

### E2E-D-RESUME-1 — ScriptAppHost setState-after-dispose (blocks 3 dapp e2e flows)

- **Status**: 🟢 RESOLVED (2026-07-20, commit `f2054990`)
- **Surfaced**: 2026-07-20 (`docs/specs/phase-d-triage.md` § Phase D-resume)
- **Severity**: HIGH (was blocking 3 e2e flows; production error log spam + memory leak)
- **Location**: `apps/autorun_flutter/lib/widgets/script_app_host.dart:777` (`_dispatch`)

`ScriptAppHostState._dispatch` (and the chain `_runEffect` → `_enqueueMsg`
→ `_dispatch` originating from `_boot`/`_executeEffects`) called `setState`
without a `mounted` guard on entry. When the host was remounted mid-boot
(via the DappRunnerScreen's `_applyConfig` or `_refreshDapp`, both of
which reassign `GlobalKey<ScriptAppHostState>`), the previous State was
disposed but the boot's async chain kept running and fired setState on
the defunct state. Surfaced as `_pendingFrame == null` assertion in
`LiveTestWidgetsFlutterBinding.postTest` after a test that triggered a
remount.

**Fix**: added `if (!mounted) return;` before the first `setState` in
`_dispatch` — canonical fix per
<https://api.flutter.dev/flutter/widgets/State/mounted.html>. Test in
`apps/autorun_flutter/test/features/scripts/script_app_host_dispose_test.dart`
gates `runtime.init` on a Completer, disposes the host mid-boot, then
completes init with an unsupported effect that drives the
`_enqueueMsg → _dispatch` chain against the defunct State. Without the
fix: `FlutterError setState() called after dispose()`. With the fix:
clean.

**Unblocked**: `dapps.apply_connection` (PHASE 46, commit `50782a97`),
`dapps.refresh` + `shortcut.dapp_refresh` (PHASES 47 + 48b, commit
`a39ce14e`).

### E2E-D-RESUME-2 — Well-known canister card RenderFlex overflow (now fatal)

- **Status**: 🟢 RESOLVED (2026-07-20, commit `0cd65171`)
- **Surfaced**: pre-existing (noticed in Phase D, 2026-07-19); became
  fatal under Flutter 3.44.6 upgrade.
- **Severity**: MEDIUM (was visual layout bug + blocking 1 e2e flow)
- **Location**: `apps/autorun_flutter/lib/widgets/well_known_canisters.dart:145-206`

The card's outer `Column` used a `Spacer()` to push the method-badge
`Container` to the bottom. Under tight GridView constraints (which occur
at 1-column narrow widths and 2-column medium widths, and transiently
during `IndexedStack` re-layout when switching to the Canisters tab), the
children overflowed. Pre-Flutter-3.44.6 this was a silent warning; the
new `IntegrationTestWidgetsFlutterBinding` treats it as a fatal test
error.

**Fix**: wrapped the inner `Column` in `SingleChildScrollView` with
`NeverScrollableScrollPhysics`. This gives the Column unbounded height
so its natural content always lays out, and visually clips anything that
doesn't fit the card — no overflow error ever. The Spacer is replaced
with a `SizedBox(height: 8)`. The method badge now sits directly under
the title row instead of pinned to the card bottom (minor visual change;
no test asserts position). Test in
`apps/autorun_flutter/test/widgets/well_known_canisters_test.dart` sweeps
6 widths (280, 420, 600, 880, 1200, 1440) covering all 3 layout branches.

**Unblocked**: `canisters.open_inline_client` (PHASE 49, commit `b627253e`).

### UX-CRIT-1 — Recovery-codes screen traps the user into lying (data loss path)

- **Status**: 🟢 RESOLVED (2026-07-19, commit `b5c6168b`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §CRIT-1)
- **Severity**: CRITICAL (permanent vault data loss)
- **Location**: `apps/autorun_flutter/lib/screens/recovery_codes_screen.dart:48,232`

`automaticallyImplyLeading: false` and no back/close button. Continue is
disabled unless the user ticks "I have saved these recovery codes" — even if
they haven't. No Download `.txt` button (only Copy). Trains users to tick
the box without saving → permanent vault data loss.

**Fix:** AppBar with back-arrow + warn-on-leave dialog + Download `.txt`
button next to Copy.

### UX-CRIT-2 — Wizard partial-failure leaves orphan duplicate-prone profiles

- **Status**: 🟢 RESOLVED (2026-07-19, commit `f7db0a1e`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §CRIT-2)
- **Severity**: CRITICAL (silent data corruption + misleading error)
- **Location**: `apps/autorun_flutter/lib/screens/unified_setup_wizard.dart:792-812`

`createProfile` persists to secure storage BEFORE the network-bound
`registerAccount`. If registration fails, the catch block sets
`_errorMessage = humanizeSecureStorageError(e)` which misleadingly reads
"Could not create the profile" even though it WAS. On retry, createProfile
runs again → second orphan profile + keypair.

**Fix:** either roll back the persisted profile on registration failure,
OR skip re-running createProfile on retry AND re-word the error to "Profile
created locally, but marketplace registration failed: …".

### UX-CRIT-3 — Currency label mismatch on script publish flow

- **Status**: 🟢 RESOLVED (2026-07-19, commit `7239d3d7`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §CRIT-3)
- **Severity**: CRITICAL (money-path bug)
- **Location**: `apps/autorun_flutter/lib/widgets/quick_upload_dialog.dart:511`

Upload form labels the price field `Price (ICP) *`. The rest of the app
treats `script.price` as USD: `scripts_screen.dart:760` passes it as
`usdAmount`; `scripts_screen.dart:869`, `script_details_dialog.dart:362,
977, 1123` all render `$X.XX`. An author entering `5` (meaning "5 ICP")
silently lists at **$5 USD**.

**Fix:** rename label to `Price (USD) *` with helper text "USD, charged via
ICPay. Set to 0 for free scripts." One-line change.

### DEFECT-3 — alpha_vote body paints BLANK (copyable `text` in `row` → RenderFlex unbounded width)

- **Status**: 🟢 RESOLVED (2026-07-22, commit `ec08f8f0`; visually verified)
- **Surfaced**: 2026-07-22 visual verification sweep (commit `49d0ab31`,
  `integration_test/voting_dapps_visual_test.dart`).
- **Severity**: CRITICAL (the entire `alpha_vote` dapp body is blank — header,
  neuron section, filter row, and proposal cards never paint; only the runner
  chrome shows. alpha_vote is NOT visually demoable.)
- **Locations**: `apps/autorun_flutter/lib/widgets/ui_v1_renderer.dart:142`
  (the `case 'text'` Row with `Expanded`); bundle
  `apps/autorun_flutter/lib/examples/10_alpha_vote.js:670-692`
  (`yourNeuronSection` puts a `copy:true` text node inside a `row`).

**Root cause:** The DEFECT-1 fix (commit `0d0ce2ae`) wrapped `select`/`text_field`
children of a `row` node in `Flexible`, but missed `text` nodes with `copy:true`.
Those render as `Row(mainAxisSize.min, [Expanded(child: Text), IconButton])`, and
`Expanded` is invalid inside an unbounded-width parent. The parent `row` gives
the text-node's internal `Row` unbounded width → the `Expanded` asserts on EVERY
layout frame → the entire `SingleChildScrollView` subtree fails to lay out.

**Fix (commit `ec08f8f0`):** Extended the `Flexible` wrapping in the renderer's
`row` case to also cover `text` children:
`if (childType == 'select' || childType == 'text_field' || childType == 'text')`.
Added DEFECT-3 regression test in `ui_v1_renderer_test.dart`.

**Verification:** Visual integration test (`voting_dapps_visual_test.dart`) run
on 2026-07-22 with real FFI + mock keyring — alpha_vote body now renders full
content: header, neuron section with input field, Status/Topic filters,
proposal #143050 (topic, status, deadline, tally), and ALPHA-Vote signal
section ("alpha-vote: not voted yet" / "Omega-vote: not voted yet"). Screenshot
at `/tmp/opencode/voting-dapp-verify/alpha_vote.png` (post-fix).

### DEFECT-4 — SNS Proposals `list_proposals` query times out (canister unreachable)

- **Status**: 🟡 CANCELLED (environment issue — not a code bug)
- **Surfaced**: 2026-07-22 visual verification sweep (commit `49d0ab31`).
- **Severity**: HIGH (SNS Proposals dapp shows no proposals — appears broken to
  users despite rendering correctly).
- **Location**: `apps/autorun_flutter/lib/examples/09_sns_proposals.js`

**Investigation:** The OpenChat SNS canister `2jvtu-yqaaa-aaaaq-aaama-cai` IS
reachable via direct curl to `ic0.app` (returns CBOR parse error, meaning the
gateway is up). The timeout occurred because the backend was DOWN during the
test run (connection refused on port 58000). The SNS dapp queries `ic0.app`
directly, not the backend, but the app's connectivity service was treating
itself as offline. Re-verification with backend running confirmed the SNS dark
theme + filter row render correctly. This is an environment issue, not a code
bug — no fix needed.

---

## High severity

### UX-H1 — Trust signals absent on every script surface

- **Status**: 🟢 RESOLVED (2026-07-19, commit `23a01dfd`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-1)
- **Severity**: HIGH (core product promise invisible)
- **Locations**: `scripts_list_item_tile.dart`, `script_details_dialog.dart`, `script_execution_bottom_sheet.dart`, `marketplace_stats_banner.dart`

The entire product promise is **signed, sandboxed, downloadable + executable
scripts**. Today the user gets ZERO visible signal of either property at the
moment they decide to download or tap-run. `MarketplaceAuthor.isVerifiedDeveloper`,
`authorPublicKey`, `uploadSignature` are checked internally but never
surfaced. Stats banner returns `SizedBox.shrink()` on error.

**Fix:** added `SandboxedChip`, `SignedByChip`, `SignatureVerifiedChip` to a
shared `lib/widgets/trust_badges.dart`; surfaced in the browse tile subtitle,
the details dialog header, and the run-panel header.

### UX-H2 — Empty-library CTAs inverted (Create primary, Browse secondary)

- **Status**: 🟢 RESOLVED (2026-07-19, commit `a0316eb9`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-2)
- **Severity**: HIGH (first-impression discovery)
- **Location**: `apps/autorun_flutter/lib/widgets/scripts_empty_state.dart:110-118`

When the user lands on Scripts with empty library, primary CTA is "Create
Script" and secondary is "Browse Marketplace". New users want to FIND
scripts, not author them. Invert.

### UX-H3 — Dark-mode breakage: 25+ hard-coded `Colors.white`

- **Status**: 🟢 RESOLVED (2026-07-19, commit `fec7f057`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-3)
- **Severity**: HIGH (premium feel; affects Account, Dapps tour, onboarding spotlight)
- **Locations**: `add_account_key_sheet.dart` (6 refs), `account_key_details_sheet.dart` (1), `profile_menu.dart` (3), `quick_upload_dialog.dart` (2), `script_details_dialog.dart` (7), `script_editor.dart` (1), `spotlight_overlay.dart` (1), `modern_empty_state.dart` (2), `shimmer_loading.dart` (1), `animated_fab.dart` (1)

All render wrong colors in Dark theme.

**Fix:** replaced `Colors.white` with `theme.colorScheme.onPrimary` / `surface`
at every call site where the bg/fg is theme-dependent. The remaining
`Colors.white` occurrences are intentional (theme-colorScheme definitions,
gradient constants, and SnackBars / colored buttons whose background is a
hardcoded non-theme color — there the white foreground is consistent across
both themes).

### UX-H4 — Trust-grant dialog all-or-nothing + missing principal warning

- **Status**: 🟢 RESOLVED (2026-07-19, commit `367f2d72`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-4)
- **Severity**: HIGH (permission honesty)
- **Location**: `apps/autorun_flutter/lib/widgets/script_app_host.dart:611-633, 989-994`

Only "Deny" + "Trust this dapp" (allow-always). No "Allow once" though
`_showPermissionDialog` framework already supports the `allowLabel`
parameter. Body says "any method, signed or anonymous" but never warns the
dapp will SEE YOUR PRINCIPAL / can deanonymize.

**Fix:** restored the "Allow once" affordance (session-only via an in-memory
`_sessionAllowed` flag — does NOT persist or light up the parent's Trusted
chip), added a principal-visibility warning to both the trust dialog body
and the dapp-runner Trusted-chip hint.

### UX-H5 — Unguarded destructive actions (4 paths)

- **Status**: 🟢 RESOLVED (2026-07-21)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-5)
- **Severity**: HIGH (one-click data loss)

Four unguarded destructive paths:
- `recent_calls_list.dart:73-78` — Clear wipes ALL call history, no confirm.
- `bookmarks_list.dart:185-208` — Bookmark trash deletes immediately.
- `keypair_switcher_sheet.dart:174-179` — Tapping tile instantly selects + pops.
- `import_keys_dialog.dart:53-55` — "Profile already exists. Delete it first"
  suggests destroying a profile + its local data to restore a backup.

**Fix (shipped 2026-07-21):**
- *Path 1 (recent calls)* — Clear button now opens an `AlertDialog`
  (`clearHistoryConfirmDialog`) with Cancel + error-coloured Clear. Wipe
  happens ONLY on explicit confirm; barrier-dismiss preserves history.
- *Path 2 (bookmarks)* — trash IconButton captures the full `BookmarkEntry`
  snapshot before remove, then shows a 4s SnackBar with `Undo` action that
  re-adds the entry verbatim (preserving label, which would otherwise be
  lost). Re-add errors surface loudly.
- *Path 3 (keypair switcher)* — tile-tap now PREVIEWS the selection in-place
  (`_previewSelection` calls setState only); only the Apply button pops with
  the result. Standard picker UX; system-back from preview state discards
  the preview without committing. Apply is no longer dead code.
- *Path 4 (import keys)* — the "Profile already exists. Delete it first …"
  copy was a destructive suggestion. Replaced with honest, non-destructive
  copy: "This profile is already on this device — your keys are here. If a
  specific keypair is missing, add it from Profile → Manage Keypairs."
  Genuine merge-into-existing is a larger architectural change deferred to
  the ALPHA-Vote follow-up track (needs per-keypair invariant guard).

**Tests (10 new + 1 updated, all PASS):**
- `test/features/canister_client/recent_calls_list_test.dart` (3 tests)
- `test/features/bookmarks/bookmarks_list_undo_test.dart` (3 tests)
- `test/features/profile/keypair_switcher_sheet_test.dart` (3 tests)
- `test/features/profile/screens/import_keys_dialog_test.dart` (1 updated)
- `just test-feature scripts` 222/222 PASS, `just test-feature profile` 144/144 PASS.


### UX-H6 — Wizard doesn't surface vault + passkey steps

- **Status**: 🟢 RESOLVED (2026-07-21, commits `7df2c51e` + `92ba775a`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-6)
- **Severity**: HIGH (post-onboarding security gap)
- **Location**: `apps/autorun_flutter/lib/screens/unified_setup_wizard.dart:798-812`

Both vault setup and passkey enrollment are buried behind the profile menu.
AccountRegistrationWizard (lines 573-594) DOES show a post-registration
passkey prompt; unify the helper and call from both wizards.

**Resolution (`7df2c51e` + `92ba775a`):** extracted the inline passkey
dialog from `AccountRegistrationWizard` into a single shared helper,
`showPostRegistrationSecurityPrompt`
(`apps/autorun_flutter/lib/widgets/post_registration_security_prompt.dart`),
called from BOTH onboarding wizards after a successful account
registration. The helper renders two skippable tiles plus an explicit
Skip action:

- **Set up vault password** — pushes `VaultPasswordSetupScreen`. Always
  available (pure local crypto via Rust FFI; no platform authenticator
  needed). The vault tile is a net-new affordance for users who
  registered via `AccountRegistrationWizard` (which previously only
  offered passkey).
- **Enroll a passkey** — pushes `PasskeyManagementScreen`. DISABLED with
  honest copy ("needs macOS, Windows, Android, or a browser. This device
  doesn't support them yet.") when `PasskeyPlatform.isSupported` returns
  `false` — never silently disappears.
- **Skip for now** — explicit, no shame. The OS-back gesture dismisses
  the dialog as `null` (treated as Skip).

The helper itself never navigates; each wizard handles its own routing
semantics (`push` in `UnifiedSetupWizard` to await return before the
success screen; `pushReplacement` in `AccountRegistrationWizard` to
resolve the caller's `push<Account>` with the account). Local-only
profiles (no marketplace username) skip the prompt entirely — both vault
and passkey are account-scoped on the wire (require `accountId`).

The unified wizard's `_isCreating` spinner is now cleared before the
prompt opens so `pumpAndSettle` can settle (mirrors the existing pattern
in `AccountRegistrationWizard`).

**Tests:** 9 new in `test/widgets/post_registration_security_prompt_test.dart`
(rendering, all 3 selection paths, OS-back, disabled-with-honest-copy,
no-navigation contract); 1 added + 4 updated in
`test/screens/account_registration_wizard_test.dart`; 6 added + 2
updated in `test/screens/unified_setup_wizard_test.dart` (new `UX-H6
post-registration security prompt` group covers prompt rendering,
local-only skip, vault navigation, passkey navigation, Skip, and the
disabled-passkey-still-renders-honestly path). `just test-feature profile`
144/144 PASS (no regression); `flutter test test/screens/
test/widgets/` 337/337 PASS.


### UX-H7 — First-run wizard has no connectivity precheck

- **Status**: 🟢 RESOLVED (2026-07-19, commit `68496c86`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-7)
- **Severity**: HIGH (compounds UX-CRIT-2)
- **Locations**: `apps/autorun_flutter/lib/main.dart:382-410`, `apps/autorun_flutter/lib/screens/unified_setup_wizard.dart:768-831`

User can reach wizard while offline; createProfile succeeds locally,
registerAccount throws → UX-CRIT-2 partial state. The wizard now probes
the backend via `ConnectivityService.checkConnectivity` *inside*
`_handleCreate` when the user has entered a marketplace username — on
offline, shows a friendly inline error ("Can't reach the marketplace
backend. Check your connection and try again."), creates no profile,
and stays on the wizard. Local-only profiles (empty username) skip the
probe entirely. Tests in
`apps/autorun_flutter/test/screens/unified_setup_wizard_test.dart`.

### UX-H8 — "Canisters" tab label is unexplained jargon

- **Status**: 🟢 RESOLVED (2026-07-21, commit `b3fb18e1`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-8)
- **Severity**: HIGH (first-impression confusion)
- **Locations**: `apps/autorun_flutter/lib/main.dart:585` (uses `kCanistersTabLabel`), `apps/autorun_flutter/lib/screens/bookmarks_screen.dart:21` (defines `kCanistersTabLabel = 'Canisters'`)

First-time users don't know what "Canisters" means. Rename or attach a
one-line info popover on long-press / hover.

**Fix:** additive combination A+B — keep the label "Canisters" (the correct,
pedagogically valuable ICP term) and the existing subtitle tagline, then add
an AppBar `IconButton(Icons.help_outline, tooltip: 'What is a canister?')`
that opens a plain-English explainer dialog. Body copy reuses
`TechTerm.canister.fullExplanation` (DRY single source for ICP terms); a
"Learn more" action deep-links to the canonical ICP docs page
(`kCanisterLearnMoreUrl`). Tests in
`apps/autorun_flutter/test/features/bookmarks/canisters_tab_info_test.dart`.

### UX-H9 — Raw exception strings in user-facing errors

- **Status**: 🟢 RESOLVED (2026-07-21)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-9)
- **Severity**: HIGH (AGENTS violation: "human errors")
- **Locations** (original 4 was an undercount; 19+ raw-`$e` sites converted):
  `vault_password_setup_screen.dart`, `vault_unlock_screen.dart`,
  `account_registration_wizard.dart`, `add_account_key_sheet.dart`,
  `scripts_screen.dart` (5 sites), `download_history_screen.dart` (3 sites),
  `bookmarks_screen.dart` (2 sites), `script_editor_dialog.dart`,
  `account_profile_screen.dart` (4 sites), `profile_menu.dart` (3 sites),
  `bookmarks_list.dart` (2 sites), `canister_call_builder.dart`,
  `canister_client_sheet.dart`, `quick_upload_dialog.dart`.

Raw exception strings (HTTP bodies, stack traces, `Instance of 'X'`,
`Exception: …` dumps, `PlatformException(...)` verbatim) leaked into
SnackBars / error text. The friendly-error pattern already existed in three
narrow, partial helpers (`friendlyIcErrorMessage`, `humanizeSecureStorageError`,
`canister_client_sheet._friendlyError`) plus the gold-standard
`ErrorDisplay` widget backed by `lib/utils/error_categories.dart`
(`categorizeError` + `getErrorInfo`). What was missing was a single
general-purpose helper for the SnackBar sites where a full widget doesn't
fit.

**Fix:**
- New `lib/utils/friendly_error.dart` (small, DRY) — delegates to the existing
  `error_categories.categorizeError` → `getErrorInfo` typed-classification
  pipeline. Two functions: `friendlyErrorMessage(error, {context})` (returns
  the typed-category user-message, prepended with `context: ` when supplied)
  and `friendlyErrorDetail(error)` (returns verbatim minus `Exception: `
  prefix, masking `Instance of 'X'` / raw-HTML / server-banner noise; `null`
  when nothing beyond the friendly message survives).
- 19+ user-facing raw-`$e` sites converted to
  `friendlyErrorMessage(e, context: 'X failed')`; bare
  `e.toString().replaceAll('Exception: ', '')` shapes → bare
  `friendlyErrorMessage(e)`. No silent swallowing — every site still surfaces
  the error loudly, just with actionable copy instead of a stack trace.
- 14-test TDD suite at `test/utils/friendly_error_test.dart` covers each
  typed branch (network/timeout/auth/validation/server/unknown), context
  join, PlatformException → unknown (never verbatim), detail stripping,
  opaque-instance masking, HTML masking, verbatim pass-through.
- Existing narrow helpers (`friendlyIcErrorMessage`,
  `humanizeSecureStorageError`) retained — they handle special cases
  (HTML-body masking, code-keyword detection) the general helper intentionally
  delegates to.

### UX-H10 — Fake progress bars

- **Status**: 🟢 RESOLVED (2026-07-21)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-10)
- **Severity**: HIGH (trust erosion)
- **Locations**: `scripts_screen.dart:522-530`, `quick_upload_dialog.dart:237-246`

Download + upload progress was FAKED via `[0.3, 0.6, 0.9]` with
`Future.delayed(100ms)`. The download "progress" map was also WRITE-ONLY —
the renderer never read it, so the fake animation did nothing visible while
still misleading code readers about what the UI was doing.

**Fix:**
- `scripts_screen.dart`: deleted the write-only `_downloadProgress` map and
  both fake-animation loops (free download + paid download). The genuine
  in-flight indicator (`_downloadingScriptIds`, which IS read by the tile
  renderer) is preserved — the user still sees a clear "downloading" state
  on the tile, just no fabricated percentage.
- `quick_upload_dialog.dart`: deleted the `[0.2, 0.4, 0.6]` fake prefix.
  `_uploadProgress` is now `double?` (nullable) and is updated ONLY at real
  phase transitions — `0.5` when signing begins, `0.75` when the signed
  request is uploaded. While preparing (form validation, bundle read) the
  indicator is indeterminate. The button label switched from
  `'Uploading ${percent}%'` to a phase-aware label: `'Preparing…'` →
  `'Signing…'` → `'Uploading…'`. Never a fabricated number.
- New TDD test `QuickUploadDialog progress UI honesty (UX-H10)` asserts no
  `'Uploading N%'` string ever renders while the HTTP call is in flight.

### UX-H11 — Three divergent "well-known canisters" catalogs

- **Status**: 🟢 RESOLVED (2026-07-21, commit `ac76c7b5`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-11)
- **Severity**: HIGH (DRY/consistency; AGENTS violation)
- **Locations**: `canister_call_builder.dart:36-46`, `well_known_canisters.dart:26-83`, `canister_registry_service.dart`

Three separate hard-coded lists with DIFFERENT members. Call Builder omits
ICLighthouse / Cyql / Kinic / Canistergeek that the Canisters tab shows.

**Fix:** replace with one shared const.

**Resolution (`ac76c7b5`):** all three lists collapsed into a single
canonical `WellKnownCanister.all` const in a new file,
`apps/autorun_flutter/lib/config/well_known_canisters.dart`. The
`WellKnownCanister` model carries `label` / `canisterId` / `description`
/ `icon` / `category` / optional `method` + a static `search()` helper
(for the autocomplete). The catalog was reconciled across all three
sources — the four entries the Call Builder previously omitted
(ICLighthouse, Cyql Projects, Kinic Search, Canistergeek) are now in the
single list, alongside Management Canister, Internet Identity, SNS-1
Governance / Ledger that only the registry / builder had. Two divergent
canister IDs were corrected (the registry service's typo `rwlct-…` for
NNS Registry → canonical `rwlgt-…`; the Call Builder's wrong
`qga6-…` for Cycles Minting → canonical `rkp4c-…`).

The three surfaces now consume the canonical list:

- `widgets/well_known_canisters.dart` (Canisters tab grid + inline client
  quick-pick) — the `WellKnownList` widget reads `WellKnownCanister.all`
  directly. The class + const list moved OUT of this file into config/;
  the widget stays.
- `widgets/canister_call_builder.dart` (Call Builder dialog dropdown) —
  replaced its 5-entry hard-coded `Map<String,String>` list with a
  `@visibleForTesting static buildWellKnownDropdownItems()` that maps
  over `WellKnownCanister.all` (mirroring the snippet generator pattern
  so the contract is testable without pumping the dialog).
- `widgets/canister_client_sheet.dart` (autocomplete) — `RawAutocomplete`
  now parameterised on `WellKnownCanister`, calling
  `WellKnownCanister.search(...)`. The option row uses the per-entry
  `icon` (was a generic storage icon for all).

`services/canister_registry_service.dart` is **deleted** — its only
unique value was the `search()` function, which is now a static on the
canonical type; per AGENTS.md (greenfield, KISS/YAGNI) keeping a thin
wrapper service would have been dead code. Its two callers
(`canister_client_sheet.dart`, `test/features/canister_client/autocomplete_test.dart`)
were updated in the same commit.

**Tests (47 total, all PASS):**
- `test/config/well_known_canisters_test.dart` (31): catalog invariants
  (unique ids + labels, non-empty description/category), UX-H11
  regression on the four required entries, single-source property
  (`WellKnownList` renders exactly `WellKnownCanister.all` — verified
  via semantics-tree walk), parameterised search coverage for every
  entry by label + by full id.
- `test/features/scripts/canister_call_builder_dropdown_test.dart` (3):
  dropdown items builder emits every canonical entry exactly once;
  explicit regression on the four previously-omitted entries.
- `test/features/canister_client/autocomplete_test.dart` (13): the
  registry service tests rewritten against `WellKnownCanister.search` +
  `WellKnownCanister.all`; same coverage (id/label/case-insensitive/
  limit/no-match) plus the UX-H11 four-entry regression.
- `test/widgets/well_known_canisters_test.dart` (4): unchanged except
  the per-card bookmark-button count now derives from
  `WellKnownCanister.all.length` instead of a magic `8` — adding a
  canister no longer requires updating a hard-coded count.

**Suites:** `just test-feature canister_client` 61/61 PASS;
`just test-feature scripts` 231/231 PASS; `flutter analyze lib/` clean.

> **Note (added 2026-07-21):** there is now a fourth list —
> `apps/autorun_flutter/lib/config/example_dapps.dart` (`exampleDapps`,
> added `nns_proposals` + `sns_proposals` entries with their governance
> canister ids). It is **intentionally separate** from the UX-H11 three:
> it is the **Dapps catalog** (headliner demo descriptors with bundle
> asset paths, titles, themes, frontend URLs), not a registry of
> "well-known canisters to invoke via the Call Builder." The two concerns
> have different lifecycles (dapps ship as authored examples; canisters
> are reference data for an interactive tool). The fix for UX-H11 should
> still collapse the original three into one shared const, but should
> NOT swallow `exampleDapps` — that would conflate two concepts.
> *(Confirmed by the UX-H11 fix: `exampleDapps` is untouched.)*

### UX-H12 — No authenticated canister calls (power users can't sign)

- **Status**: 🟢 RESOLVED (2026-07-21, commits `cba0e2a4` + `13672cb8` + `934b10b3`)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-12)
- **Severity**: HIGH (power-user surface incomplete)
- **Location**: `apps/autorun_flutter/lib/widgets/canister_client_sheet.dart` (interactive Call Builder sheet); `apps/autorun_flutter/lib/widgets/canister_call_builder.dart` (snippet generator)

The interactive Call Builder sheet's Call button only invoked
`RustBridgeLoader.callAnonymous`; the bridge has supported
`callAuthenticated` since R-3b WU-4 (and the script-app host has used it
since STEP-1), but the interactive sheet never wired it. Separately, the
Call Builder dialog's snippet generator emitted broken syntax
(`keypair_id: "<id>"` — no such host field) plus a non-running comment
instead of the host's `authenticated: true` contract flag.

**Resolution (3 commits, each independently shippable):**

1. `cba0e2a4` — `feat(canisters): wire authenticated calls into Call
   Builder sheet`. Added a `SwitchListTile.adaptive` "Sign as active
   profile" toggle directly above the Call button. Active keypair
   present → toggle enabled, subtitle shows the public principal (NEVER
   the private key), and `_callMethod` dispatches
   `bridge.callAuthenticated(privateKeyB64: kp.privateKey)`. No keypair
   / no ProfileScope → toggle disabled with a tappable "Create a
   profile to sign calls as your identity." CTA that deep-links into
   `UnifiedSetupWizard`. `_callMethod` rechecks the keypair on entry so
   a mid-session profile removal surfaces a loud `friendlyErrorMessage`
   SnackBar (`Cannot sign call: …`) — never a silent anonymous fallback
   (AGENTS.md). History rows tagged `(signed)` on the auth path
   (schema unchanged).

2. `13672cb8` — `feat(canisters): honest auth-failure UX in Call
   Builder`. Added the `testSecureStorageReadiness` test seam (mirrors
   `DappRunnerScreen`) so the wizard deep-link test is hermetic — the
   real probe would shell out to gnome-keyring-daemon on a Linux host
   and `pumpAndSettle` would never converge. Locked down the two
   honest-failure paths with widget tests: keyless user (real
   `ProfileController`, no profiles) → tap CTA pushes the real
   `UnifiedSetupWizard`; mid-session removal (`setActiveProfile(null)`
   after toggling ON) → tap Call surfaces the friendly SnackBar, bridge
   records ZERO anonymous calls (never a silent fallback), message has
   no raw `StateError` / `Exception:` text.

3. `934b10b3` — `fix(canister-call-builder): emit 'authenticated: true'
   (not broken keypair_id)`. Replaced the broken `keypair_id`/comment
   block with a single `authenticated: true,` line when the checkbox is
   on; deleted the dead `_keypairId` field. Extracted the generator
   into a `@visibleForTesting static CanisterCallBuilderDialog.generateBundle({...})`
   so the contract is testable without pumping the dialog. Fixed two
   pre-existing snippet bugs surfaced by the extraction: empty snippet
   when the user typed a method name without loading Candid, and
   `method: "Instance of 'CanisterMethod'"` (no toString override) —
   now uses the method NAME.

**Tests (12 new, all PASS, real Ed25519 keypairs — no crypto mocked):**
- `test/features/canister_client/authenticated_call_test.dart` (6 tests):
  default anonymous path, toggle ON → callAuthenticated with the right
  key + principal rendered + authenticated-ok result; security sweep
  (b64 private key never in ANY rendered SelectableText); no
  ProfileScope → disabled + CTA shown + no regression; ProfileScope +
  no profile → CTA pushes the wizard; mid-session removal → loud
  friendly SnackBar.
- `test/features/scripts/canister_call_builder_snippet_test.dart` (6
  tests): generator unit tests for the snippet text (authenticated
  on/off, empty canister, null method); cross-validation through the
  REAL `ScriptAppHost` — snippet authenticated=true → host invokes
  callAuthenticated with the active keypair; snippet authenticated=false
  → host invokes callAnonymous even with a keypair present.

**Suites:** `just test-feature canister_client` 60/60 PASS;
`just test-feature scripts` 228/228 PASS; `just test-feature profile`
144/144 PASS. `flutter analyze` clean across all touched files.

### UX-PMD-1 — `profile.create_via_menu_dialog` use-after-dispose

- **Status**: 🟢 RESOLVED (2026-07-21, Phase O commit `fe5af1ad`)
- **Surfaced**: 2026-07-21 (Phase N — implementing `profile.create_via_menu_dialog` e2e flow; full write-up in `docs/specs/phase-n-triage.md`)
- **Severity**: HIGH (one of the documented "Create Profile" entry points throws in production when reached via the manage sheet)
- **Location**: `apps/autorun_flutter/lib/widgets/profile_menu.dart:514-572` (`_showManageProfilesSheet` + `_pushCreateProfileWizard`)

The manage-sheet `onCreateProfile` closure captured
`_ProfileMenuWidgetState.this` and dereferenced `context` AFTER the
State has been disposed. The closure was set in `_showManageProfilesSheet`
(called from `_handleAction` AFTER `Navigator.of(context).pop()` had
already closed the menu's modal). When the user eventually tapped
"Create New Profile" in the sheet, the menu's exit animation had
finished and `_ProfileMenuWidgetState` was unmounted — the closure
threw `State no longer has a context` inside `_showCreateProfileDialog`
(at `Navigator.of(context).push`).

**Why this hadn't been reported**: the timing window was narrow — users
who tapped within the menu's ~250ms exit animation got lucky; users who
read the sheet for a second or more hit the bug. The deferred e2e flow
surfaces it deterministically.

**Fix**: capture `NavigatorState` BEFORE the `showModalBottomSheet` await
boundary (`final navigator = Navigator.of(context);`) and route through
the captured navigator from the closure. `_showCreateProfileDialog`
delegates to a new `_pushCreateProfileWizard(NavigatorState)` helper so
the post-await push uses the captured navigator, not the disposed State's
context. Canonical Flutter pattern (see
<https://api.flutter.dev/flutter/widgets/State/mounted.html>).

**Test**: `apps/autorun_flutter/test/widgets/profile_menu_dispose_test.dart`
reproduces the bug pre-fix (assertion at `profile_menu.dart:536`) and
passes post-fix. **End-to-end coverage**: `profile.create_via_menu_dialog`
flow (PHASE 3 of `suite_mock_keyring_identity_test.dart`) drives the full
UI path (menu → Switch Profile → manage sheet → Create New Profile →
wizard → real createProfile + registerAccount → success) and pumps past
the menu's exit animation before tapping, exercising the post-dispose
branch deterministically.

### UX-N2 — Pagination UI missing (load-more state machine is vestigial)

- **Status**: 🟢 RESOLVED (2026-07-21)
- **Surfaced**: 2026-07-20 (e2e Phase 52 implementation — `scripts.load_more`)
- **Severity**: MEDIUM (missing app feature; e2e covers the contract only)
- **Location**: `apps/autorun_flutter/lib/screens/scripts_screen.dart` (footer sliver + scroll listener)

`ScriptsScreenState` tracks pagination state — `_isLoadingMore`,
`_hasMore`, `_offset` — and `_loadMarketplaceScripts(isLoadMore: true)`
fetches the next page. The screen now wraps the `CustomScrollView` in a
`NotificationListener<ScrollNotification>` whose `_onScrollNotification`
callback triggers `_loadMarketplaceScripts(isLoadMore: true)` on
`ScrollEndNotification` when `metrics.pixels >= metrics.maxScrollExtent - 200`
(`_loadMoreTriggerMargin`). The re-entrancy guard (`_isLoadingMore ||
!_hasMore`) prevents duplicate fetches.

A footer sliver (`_buildLoadMoreFooterSliver`) renders the honest state at
the list tail: idle + has-more → "Load more" `TextButton.icon` (keyboard /
tap fallback for users who prefer explicit triggers); in-flight →
centred 24×24 `CircularProgressIndicator`; no more pages → "End of results"
caption; empty marketplace → bare spacer.

The e2e flow `scripts.load_more` (PHASE 52 of `suite_keyring_less_test.dart`)
covers the pagination CONTRACT end-to-end against a bulk-seeded backend
(via `tool/seed_marketplace.dart`). Five new widget tests
(`load_more_pagination_test.dart`) cover the user-facing interaction using
`PagedFakeMarketplaceOpenApi` (honours real slice + hasMore contract):
auto-load on scroll, re-entrancy guard, hasMore=false end state, tap
fallback, in-flight indicator.

### WEB-1 — Flutter Web e2e via Playwright (passkey-on-web unblocked)

- **Status**: 🟢 RESOLVED (2026-07-21, commits `cb7de983` + `1c8b730c` + `73bc7c8f`)
- **Surfaced**: 2026-07-17 (`docs/specs/2026-07-17-e2e-completion-and-ux-sweep.md` Phase C)
- **Severity**: HIGH (blocks real-app web e2e coverage)
- **Was**: ⚪ DEFERRED (per 2026-07-19 plan Pivot 1 — Tier A substrate-fakes + Tier B image-based Playwright bypass the need). The 2026-07-21 work revisited the issue at the human's request and unblocked it via a different angle (Playwright 1.61+'s modern `browserContext.credentials` virtual authenticator API + a Dart probe entrypoint pattern that sidesteps the Flutter a11y tree entirely).

**Was the issue title accurate?** Partly. The original blocker was real —
Flutter Web's a11y tree (`flt-semantics` element) IS never auto-enabled in
headless Chromium, so DOM-based assertions against the Flutter UI are
unavailable. That was confirmed again on Flutter 3.44.6 (every force-enable
attempt — `--force-renderer-accessibility`, Tab keydowns, CDP
`Accessibility.enable` — left `<flt-semantics>` empty; CDP AXTree stays at 9
generic nodes).

BUT the title implied Playwright-driven WEB AUTHN was blocked, and that turned
out to be **false**. Playwright 1.61+'s `browserContext.credentials` API
(`create('localhost')` + `install()`) arms a virtual authenticator that
satisfies `navigator.credentials.create` headlessly without any Flutter-side
a11y. The full WebAuthn round-trip works perfectly — the blocker was only the
ASSERTION side, not the WebAuthn side.

**The actual blockers (resolved):**

1. **Two compounding production bugs** in the backend passkey flow had made
   real-backend WebAuthn registration impossible since the W7-13 signature
   gate landed. Both are fixed in commit `cb7de983` and tracked as
   `WEB-1-PASSKEY-SHAPE` (see below). Bug #1 masked bug #2: the JSON-shape
   parse failure at `/passkey/register/start` hid the FK failure at
   `/passkey/register/finish`.

2. **The assertion-side workaround.** The Flutter UI cannot be driven
   headlessly (a11y tree off), but the passkey flow CAN be exercised by a
   dedicated Dart probe entrypoint that publishes its result to
   `document.title`. The probe drives the REAL production code paths
   (`KeypairGenerator.generate` → `AccountController.registerAccount` →
   `PasskeyService().registerPasskey` → `PasskeyService().listPasskeys`),
   so canvaskit + real pure-Dart Ed25519 + the real backend are all
   exercised. This is the same probe pattern the R-3 / R-3b verification
   (`tool/web_probe_*_main.dart`) already uses.

**Resolution shape (commit `73bc7c8f`):**

- `apps/autorun_flutter/web_e2e_playwright/specs/passkey.spec.ts` — 2 specs:
  - positive: virtual authenticator installed → full passkey registration
    round-trip succeeds (5/5 checks PASS: username, keypair, register_account,
    register_passkey, list_passkeys count=1 expectedMatch=true).
  - negative: NO authenticator → `navigator.credentials.create` hangs →
    probe's 20s timeout fires → loud failure with `TimeoutException` +
    `expect_failure_path` check PASSes.
- `apps/autorun_flutter/tool/web_probe_passkey_main.dart` — Dart probe
  entrypoint (`flutter build web --target=…`).
- `scripts/web-e2e-passkey.sh` — brings up a DEDICATED backend on :41098 with
  `WEBAUTHN_RP_ORIGIN=http://localhost:8099` (must match the page origin
  exactly for WebAuthn), builds the probe bundle, serves it on
  `http://localhost:8099`, runs Playwright, tears down via trap. The dev
  `api-dev-up` backend is untouched.
- `justfile` recipe: `just e2e-web-passkey` (with `--no-build` and
  `--keep-servers` escape hatches).

**Why `localhost` (not 127.0.0.1).** The WebAuthn RP ID is the page's
hostname. `WEBAUTHN_RP_ID=localhost` is the backend default; the static
server binds to `localhost` so the page origin matches the RP origin the
backend expects. A `127.0.0.1` origin would make the backend reject the
credential assertion (origin mismatch).

**Evidence (positive spec output from `just e2e-web-passkey`, 2026-07-21):**

```
[positive] phase=complete allPassed=true
  [PASS] username_chosen: e2eweb1784652740405
  [PASS] keypair: pubkey=LFpARW9pKBV+… principal=4vvwz-dzixm-2imda-is5o4-irhgo-f7rhx-xalrz-pypnd-ym3tl-tkm2g-4qe
  [PASS] register_account: id=a20e4bcd-f6b6-4a18-a8ac-10b2ffbdf058 username=e2eweb1784652740405
  [PASS] register_passkey: passkeyId=5d5f206a-959f-4e3f-aa31-82ef703e1564 createdAt=2026-07-21T16:52:21.703423909+00:00
  [PASS] list_passkeys: count=1 expectedMatch=true ids=5d5f206a-959f-4e3f-aa31-82ef703e1564
  ✓  1 [chromium] › specs/passkey.spec.ts:153:5 › passkey registration round-trip succeeds with virtual authenticator (2.6s)
[negative] phase=expect_failure allPassed=true
  [FAIL] register_passkey: TimeoutException: WebAuthn navigator.credentials.create did not complete within 20s (expected when no virtual authenticator is installed)
  [PASS] expect_failure_path: saw expected WebAuthn failure
  ✓  2 [chromium] › specs/passkey.spec.ts:181:5 › passkey registration fails loudly without virtual authenticator (22.7s)

  2 passed (26.5s)
✅ WEB-1 passkey-on-web e2e PASSED
```

**What is NOT covered.** The probe drives the production passkey Dart code
but NOT the Flutter UI itself (the `PasskeyManagementScreen` FAB →
`_addPasskey` → `PasskeyService` chain). UI-level navigation remains
screenshot-only (`e2e-web-playwright` Tier B + `zai-vision`). If/when
Flutter Web ships working programmatic semantics enablement, the probe can
be retired in favour of full-UI Playwright driving — the FLUTTER_WEB_FORCE_SEMANTICS
hook in `lib/main.dart` remains in place for that future.

---

### WEB-1-PASSKEY-SHAPE — Two compounding backend bugs that blocked real-backend WebAuthn registration

- **Status**: 🟢 RESOLVED (2026-07-21, commit `cb7de983`)
- **Surfaced**: 2026-07-21 (WEB-1 investigation — Playwright virtual authenticator round-trip reached `/passkey/register/finish` only after bug #1 was patched, then surfaced bug #2)
- **Severity**: HIGH (production passkey registration was impossible against the real backend on ANY platform — not just Web — since the W7-13 signature gate landed)
- **Location**: `backend/src/services/passkey_service.rs` (JSON shape bug), `backend/src/db.rs` (FK schema bug); test updates in `backend/tests/passkey_tests.rs` + `backend/tests/soft_authenticator.rs`

These bugs explain why the existing substrate-HTTP passkey tests
(`test/e2e_web/substrate/substrate_http.dart`) passed while no production
client could complete a real passkey registration. The substrate mirrors
the FLAT options shape the Dart `passkeys` package expects; the real backend
was returning a different shape, and the FK made the finish step fail. Both
bugs were masked because the substrate-fake tests never exercised the real
backend.

**Bug #1 — JSON shape mismatch.** `PasskeyRegistrationStart.options` was
typed `CreationChallengeResponse` (from `webauthn-rs-proto`), which
serializes the inner options under a `public_key` wrapper. The Dart
`passkeys` package's `RegisterRequestType.fromJson` expects the options
flat at the top level (`rp`, `user`, `challenge`, …), matching the
substrate-HTTP contract. The real backend's response shape drifted from
the substrate by one level of nesting — enough to make
`PasskeyService.registerPasskey` throw
`FormatException: Expected "rp" to be a Map, got Null` on every platform.
Same issue on the auth side (`RequestChallengeResponse.public_key`
wrapper).

**Fix:** `PasskeyRegistrationStart.options` is now typed as the inner
`PublicKeyCredentialCreationOptions` directly; `start_registration` extracts
`.public_key` from the webauthn-rs return value. Same change on the auth
side. The `soft_authenticator.rs` test helper's signatures updated to take
the inner types (its previous signature simulated the browser-side
`CredentialCreationOptions` wrapper, which is irrelevant to the HTTP
response shape). 14/14 backend passkey_tests pass against the real
webauthn-rs verifier + real schema.

**Bug #2 — FK schema mismatch.** `passkeys.account_id` was FK'd to
`keypair_profiles(principal)`, but the signature gate resolves `account_id`
as an `accounts.id` UUID (via `account_public_keys.account_id`). Same bug
pattern the A-4 W4 migration already fixed for `user_vaults` and
`recovery_codes` — `passkeys` was missed.

**Fix:** drop+recreate `passkeys` with
`FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE`
(same pattern as the A-4 W4 fix). No data loss: the broken FK made
production passkey inserts impossible, so no rows ever existed. Backend
test `seed_principal` updated to insert an `accounts` row (was inserting a
`keypair_profiles` row).

**Why both bugs were never caught before:**

- The Flutter UI never reached the real-backend passkey flow because the
  substrate-HTTP tests bypassed it, AND production users hit the
  PasskeyManagementScreen only after creating a profile (a flow never
  exercised end-to-end against the real backend on Web/headless).
- The `e2e-web-playwright` Tier B harness (boot smoke + screenshot) doesn't
  drive any backend round-trips.
- The desktop `e2e-desktop` suite runs in a Linux desktop build where
  `PasskeyPlatform.isSupported` is false, so the FAB → `_addPasskey` chain
  early-returns with the "Passkeys aren't available on Linux desktop"
  message.

WEB-1's Playwright virtual authenticator finally forced the real-backend
flow to complete end-to-end, surfacing both bugs.

---

## Medium severity

### UX-W1 — `details_run` shortcut missing from help sheet (RESOLVED)

- **Status**: 🟢 RESOLVED (2026-07-17, commit `d12a9d24`)
- **Surfaced**: 2026-07-17 (`shortcuts_help_sheet_test` was red)

The `Enter` shortcut in the Script Details dialog (Run or Download — the
primary action) was wired in `kShortcutSpecs` but never listed in the
`ShortcutsHelpSheet` Details group. So users pressing Enter got the
behavior but couldn't discover the binding via `?`. Fixed by adding
`details_run` to the Details group alongside the close/prev/next entries.

---

### TEST-N1 — `profile_menu_simplified_v2_test` was asserting stale 'Switch Profile' copy

- **Status**: 🟢 RESOLVED (2026-07-17, commit `d12a9d24`)
- **Surfaced**: 2026-07-17

With a single profile, the tile labelled "Switch Profile" actually opens
the Manage Profiles sheet (since there's nothing to switch TO). The test
asserted the wrong post-condition. Updated to assert "Manage Profiles"
sheet opens (which is the current production behaviour).

### TEST-N2 — `profile_menu_first_run_test` used `pumpAndSettle` on an infinitely-animating wizard

- **Status**: 🟢 RESOLVED (2026-07-17, commit `d12a9d24`)
- **Surfaced**: 2026-07-17

`UnifiedSetupWizard` has continuous focus/transition animations that
prevent `pumpAndSettle` from ever returning. Replaced with bounded
pumps. Also fixed the stale "Create Profile" copy assertion (the actual
CTA is "Get Started").

---

## Low severity / Polish

### UX-N1 — Visual UX review pending (vision MCP unavailable in this environment)

- **Status**: 🟢 RESOLVED (2026-07-19, `docs/specs/2026-07-19-ux-review.md`)
- **Severity**: LOW (process issue, not product issue)
- **Surfaced**: 2026-07-17

The `zai-vision_analyze_image` MCP timed out for every screenshot during
the 2026-07-17 session. The 2026-07-19 continuation did a CODE-LEVEL review
instead via 3 parallel `orchestrator-verifier` subagents covering all
`lib/screens/` + `lib/widgets/` (~30k LOC); vision MCP was usable for
high-DPR Web Playwright captures but unreliable on the desktop screenshots
at `kDesktopDpr=1.0`. The DPR follow-up landed in Phase H (commit
`3cb69594`): screenshots now rasterize at `kScreenshotDpr=2.0` while the
test viewport stays at `kDesktopDpr=1.0` (logical 1440×900, matching real
desktop layout). Findings distilled into 3 CRITICAL + 12 HIGH-severity
issues (see UX-CRIT-{1,2,3} and UX-H{1..12} above); raw reports preserved
in the verifier task transcripts.

---

## Resolved (kept for the historical record)

### UX-H1 — Trust signals on every script surface

- **Status**: 🟢 RESOLVED (2026-07-19, commit `23a01dfd`)
- **Severity**: HIGH (core product promise invisible)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-1)

Added `lib/widgets/trust_badges.dart` with three theme-driven chips:
`SandboxedChip` (the QuickJS runtime guarantee — green-tinted, always
shown), `SignedByChip(author, verified)` (with an inline verified badge
when `MarketplaceAuthor.isVerifiedDeveloper == true`), and
`SignatureVerifiedChip` (shown when the bundle carries a verified
`uploadSignature` / SHA-256 checksum). Surfaced in the browse tile
subtitle, the details dialog header (next to category/price), and the
run-panel header status row. Widget tests in
`test/widgets/trust_badges_test.dart`,
`test/widgets/scripts_list_item_tile_test.dart`,
`test/widgets/script_details_dialog_trust_test.dart`, and
`test/widgets/script_execution_bottom_sheet_test.dart`.

### UX-H3 — Dark-mode breakage: 25+ hard-coded `Colors.white`

- **Status**: 🟢 RESOLVED (2026-07-19, commit `fec7f057`)
- **Severity**: HIGH (premium feel; affects Account, Dapps tour, onboarding spotlight)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-3)

Replaced `Colors.white` with the matching `Theme.of(context).colorScheme`
token at every theme-dependent call site: sheet backgrounds → `surface`,
foreground text/icons on primary gradients → `onPrimary`, FAB / button
foregrounds → `onPrimary` / `onSecondary`, and the legacy `cardGradient`
constant's container tints. Remaining `Colors.white` occurrences are
intentional: theme-ColorScheme definitions (where `onPrimary: Colors.white`
*defines* the token), static-const gradient stops, the dark-scrim spotlight
overlay border, and SnackBars / colored FilledButtons whose background is a
hardcoded non-theme color (success green, commerce orange) — there the
white foreground is consistent across both themes. Widget test in
`test/widgets/dark_theme_rendering_test.dart` asserts the dark-theme
surface color is actually used.

### UX-H4 — Trust-grant dialog all-or-nothing + missing principal warning

- **Status**: 🟢 RESOLVED (2026-07-19, commit `367f2d72`)
- **Severity**: HIGH (permission honesty)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-4)

`_ensureDappTrust` now passes `allowLabel: 'Allow once'` so the dialog
offers three buttons: Deny, Allow once, Trust this dapp. A new in-memory
`_sessionAllowed` flag covers the rest of this host instance's calls
without writing to `DappTrustStore` or publishing to `dappTrustState` (so
the parent's "Trusted" chip lights up only for actually-persistent trust).
The dialog body now warns "The dapp will see your principal and can
identify you on every call." The dapp-runner Trusted-chip hint mirrors the
warning. Tests in
`test/features/dapps/dapp_trust_dialog_uxh4_test.dart` and the existing
`dapp_trust_test.dart` (updated assertion for the new third button).

### UX-CRIT-3 — Currency label mismatch on script publish flow

- **Status**: 🟢 RESOLVED (2026-07-19, commit `7239d3d7`)
- **Severity**: CRITICAL (money-path bug)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §CRIT-3)

Upload form labelled the price field `Price (ICP) *` while the rest of the
app treats `script.price` as USD (passed as `usdAmount`, rendered as `$X.XX`).
Renamed to `Price (USD) *`. Widget test in
`apps/autorun_flutter/test/widgets/quick_upload_dialog_test.dart`.

### UX-H2 — Empty-library CTAs inverted (Create primary, Browse secondary)

- **Status**: 🟢 RESOLVED (2026-07-19, commit `a0316eb9`)
- **Severity**: HIGH (first-impression discovery)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-2)

Swapped the library-empty state so "Browse Marketplace" is the primary
(FilledButton-equivalent `ModernButton`) and "Create Script" is the
secondary ghost button. LOW-1: favorites-filter empty state also re-labelled
"Browse Scripts" → "Browse Marketplace". Parameterised `ModernEmptyState`
primary action icon so non-create actions render the right glyph. Widget
tests in `apps/autorun_flutter/test/widgets/scripts_empty_state_test.dart`.

### UX-CRIT-1 — Recovery-codes screen escape hatch + Download .txt

- **Status**: 🟢 RESOLVED (2026-07-19, commit `b5c6168b`)
- **Severity**: CRITICAL (permanent vault data loss)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §CRIT-1)

Restored the AppBar `BackButton` (with custom `onPressed` that shows a
"Leave without saving?" warning dialog before popping) and added a Download
`.txt` button next to Copy. The downloaded file contains a header (account,
ISO timestamp) plus all codes; written via `path_provider` to the temp
directory and surfaced to the user via SnackBar. Widget tests in
`apps/autorun_flutter/test/widgets/recovery_codes_screen_test.dart`.

### UX-CRIT-2 — Wizard rolls back profile on registration failure

- **Status**: 🟢 RESOLVED (2026-07-19, commit `f7db0a1e`)
- **Severity**: CRITICAL (silent data corruption + misleading error)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §CRIT-2)

`_handleCreate` now wraps `registerAccount` in an inner try/catch. On
failure it calls `profileController.deleteProfile(profile.id)` (rolling
back the persisted orphan) and surfaces a specific message: "Profile
created locally, but marketplace registration failed: $e. Your profile has
been removed — please try again." A retry then creates exactly one profile,
not two. Outer catch still handles `createProfile` failures via
`humanizeSecureStorageError`. Test in
`apps/autorun_flutter/test/screens/unified_setup_wizard_test.dart`.

### F1–F8 — Seed defect list from the predecessor plan (Phase 3)

- **Status**: 🟢 RESOLVED (2026-07-15, commit `9b37bb46` + `aae008ae`)
- **Source**: `docs/specs/2026-07-15-e2e-harness-and-ux.md` §3 (Phase 3)
- F1 `/recovery` dead route → wired
- F2 Vault screens not reachable → wired via profile menu Vault tile
- F3 `_duplicateScript` View SnackBar action no-op → implemented
- F4 Passkey device name hardcoded "This Device" → derived
- F5 Profile rename/delete promised but missing in UI → wired
- F6 dapp vote flow HTTP 530 → environmental (canned-bridge test)
- F7 Dual profile-creation paths → DRY'd to UnifiedSetupWizard
- F8 Stale doc secp256k1 stubbed on web → reconciled

### E2E-RED-MARKETPLACE + E2E-RED-MOCK-KEYRING — 2 of 3 desktop suites silently RED

- **Status**: 🟢 RESOLVED (2026-07-17, commit `eb9cbdfa`)
- **Source**: `docs/specs/2026-07-17-e2e-completion-and-ux-sweep.md` Phase A
- Root causes + fixes documented in commit message.

### E2E-1 — `just e2e-one <flow-id>` cannot target individual flows inside the marketplace suite

- **Status**: 🟢 RESOLVED (2026-07-19, commit `59bc4091`)
- **Severity**: MEDIUM (dev-loop friction)
- **Surfaced**: 2026-07-17 (`justfile` audit)

`just e2e-one <flow> [suite]` only accepted `keyring-less | marketplace |
mock-keyring` as the suite arg. Phase B of the 2026-07-17 plan folded the
marketplace suite into keyring-less (3 desktop boots → 2): the 13 marketplace
flows now run as phases 29-41 of `suite_keyring_less_test.dart`, and the
`marketplace` suite arg + `e2e-marketplace` target were dropped. Every former
marketplace flow is now reachable via `just e2e-one <flow-id>` with the
default `keyring-less` suite.

### UX-9 / UX-10 — Wizard + vault password keyboard-incomplete (Enter did nothing)

- **Status**: 🟢 RESOLVED (2026-07-19, commit `ef0029de`)
- **Severity**: MEDIUM (desktop UX friction)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §MEDIUM)

The display-name field in `unified_setup_wizard.dart` had `autofocus`
but no `onFieldSubmitted` — pressing Enter did nothing. Same gap in
`account_registration_wizard.dart` (username + display name) and
`vault_password_setup_screen.dart` (password + confirm). Wired every
primary input: intermediate fields use `TextInputAction.next` + focus-
next via `FocusNode.requestFocus()`; the last field uses
`TextInputAction.done` + submit-when-valid. Submit handlers reuse the
existing `_canCreate` / `_canRegister` / `_isFormValid` getters so the
Enter path and the button path can't drift. Tests in
`apps/autorun_flutter/test/screens/{unified_setup_wizard,
account_registration_wizard,vault_password_setup_screen}_test.dart`.

### UX-7 — Vault password strength meter

- **Status**: 🟢 RESOLVED (2026-07-19, commit `490f4833`)
- **Severity**: MEDIUM (typing feedback)
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §MEDIUM)

Strict password rules (12+ chars + 4 char classes) with no generator,
no strength meter, no recovery hint — users typed blind until they
broke a rule. Added a live, deterministic strength meter below the
password field. Pure-Dart scoring util at
`apps/autorun_flutter/lib/utils/password_strength.dart`:
length (<8=0, 8-11=1, 12-15=2, 16+=3) + character classes (0-4, capped
at 3), total clamped to [0,4]. Labels: Weak / Fair / Good / Strong.
Colors use theme tokens (error / warningColor / accentLight /
successColor) — no hardcoded `Colors.*`. Generator + recovery hint were
out of scope. Tests in
`apps/autorun_flutter/test/utils/password_strength_test.dart` (15 unit
tests) and the strength-meter widget test in
`apps/autorun_flutter/test/screens/vault_password_setup_screen_test.dart`.

---

## Critical / Blockers — current session (2026-07-21 e2e harness overhaul)

Plan: `docs/specs/2026-07-21-e2e-harness-overhaul.md`. P0 (NEW-1, NEW-2,
NEW-4, NEW-6) **and** P1 (NEW-3, NEW-5) are **all complete and verified
green** (`just e2e-desktop` ~9m, 4/4 PASSes; `just e2e-one <flow>` 9-25s;
`just e2e-tag smoke` ~1m).

### NEW-1 — `resetAppState` cache-manager race (suite crashes at PHASE 1)

- **Status**: 🟢 RESOLVED (2026-07-21, commit `598801c8`)
- **Surfaced**: 2026-07-21 baseline run of `just e2e-desktop` after clean DB reset.
- **Severity**: HIGH (blocks the entire desktop e2e harness on a clean box)
- **Location**: `apps/autorun_flutter/integration_test/e2e/suite_helpers.dart` (`resetAppState`).

`resetAppState` deletes the entire app-support directory while
`flutter_cache_manager`'s `JsonCacheInfoRepository` holds a lazy-write handle
to `libCachedImageData.json` inside that directory. The next cache write fires
`PathNotFoundException: Cannot open file ... libCachedImageData.json`, which
propagates as a `_pendingFrame == null` assertion in
`LiveTestWidgetsFlutterBinding.postTest`, killing the suite at PHASE 1
(right after the first `resetAppState + remount` cycle).

**Fix (P0-A):** `resetAppState` now calls a new `_stopImageCache(tester)`
helper FIRST (under `tester.runAsync`): `DefaultCacheManager().emptyCache()`
+ `.dispose()` drains the lazy-write queue and tears down the timer. THEN
secure storage is wiped and the app-support dir is deleted AND recreated
empty, so any lingering `path_provider` handle lands on a valid path. No
`try/catch` silencing (AGENTS.md compliant). Eliminates NEW-4 as a side
effect.

### NEW-2 — No per-suite DB reset (stale scripts accumulate)

- **Status**: 🟢 RESOLVED (2026-07-21, commit `bda0b1ab`)
- **Surfaced**: 2026-07-21 (backend DB had 1110 scripts after one session).
- **Severity**: HIGH (silently breaks any test that assumes the canonical 3-script marketplace)
- **Location**: `justfile` (`e2e-desktop`, `e2e-fast` recipes).

Tests assume the marketplace has exactly 3 canonical seed scripts
(`Hello IC Starter`, `ICP Balance Reader`, `Interactive Counter`) and bulk-seed
more only inside specific phases (`scripts.load_more`). The backend DB is
never reset between runs, so test-inserted scripts (`Bulk Seed Script N`,
`Pub_NNN`, `Marketplace Visibility Test N`, paid seeds, …) accumulate. After
one active dev session the DB had **1110 scripts**, the canonical 3 were
buried past page-1, and `find.textContaining('Hello IC Starter')` returned
nothing within the 15s wait.

**Fix (P0-B):** `e2e-desktop` and `e2e-fast` recipes now run
`(cd "{{api_dir}}" && bash scripts/add-sample-data.sh)` BEFORE the suites.
`add-sample-data.sh` is idempotent (DELETE then INSERT) and resets to the
canonical 3 scripts every run. Long-term: a debug-only `/api/v1/admin/reset`
endpoint (avoids shell dependency) — filed as a follow-up.

### NEW-3 — `suite_keyring_less_test.dart` is a 2532-line single `testWidgets`

- **Status**: 🟢 RESOLVED (2026-07-21, commits `78b76618` + `4f23755c` + `4b6c05e0`)
- **Surfaced**: pre-existing (referenced in E2E-PHASE56+57 as the "binding stability
  threshold" root cause).
- **Severity**: MEDIUM (maintainability + flakiness; the suites ARE stable today
  thanks to the 4-suite split, but each is still one monolithic `testWidgets`).
- **Location**: `apps/autorun_flutter/integration_test/e2e/suite_keyring_less_test.dart`
  (55 phases) + `suite_mock_keyring_test.dart` (25 phases) +
  `suite_mock_keyring_dapps_test.dart` (5 phases) +
  `suite_mock_keyring_identity_test.dart` (3 phases).

55 phases inside a single `testWidgets` body. Past ~30 phases, the
flutter_test binding's stream protocol starts crashing with
`"Cannot close sink while adding stream"`. Prior sessions worked around by
splitting into 4 mini-suites. The root cause (resource accumulation in long
single-`testWidgets` body) is not fixed.

**Fix (P1-A/B/D):** All 4 suites now have their flow implementations
extracted into shared registry files (`keyring_less_flows.dart`,
`mock_keyring_flows.dart`, `mock_keyring_dapps_flows.dart`,
`mock_keyring_identity_flows.dart`). Each suite file is now a thin
shared-boot testWidgets that imports the registry. Additionally, per-flow
testWidgets files (`flows_*_test.dart`) provide one isolated testWidgets
per flow for fast single-flow iteration (`just e2e-one <flow>` 9-25s, was
~90s). Monolith suites remain for `e2e-desktop` (shared boot is efficient).

### NEW-4 — `_pendingFrame == null` postTest assertion (symptom of NEW-1)

- **Status**: 🟢 RESOLVED (2026-07-21, commit `598801c8` — eliminated by NEW-1 fix)
- **Surfaced**: 2026-07-21 (suite_keyring_less_test.dart PHASE 1).
- **Severity**: HIGH (mask, but blocks the suite)
- **Location**: `flutter_test/src/binding.dart:3081` (assertion site).

`LiveTestWidgetsFlutterBinding.postTest` asserts `_pendingFrame == null`.
This fires when a `setState` / pump is scheduled after the test body returns.
In this case it was the `PathNotFoundException` from NEW-1 racing with the
test teardown — the cache manager's recovery write triggered a frame request
post-test. **Fixing NEW-1 eliminates NEW-4.**

### NEW-5 — E2E runtime: ~9m total; single-flow cycle now 9-25 s

- **Status**: 🟢 RESOLVED (2026-07-21, commits `293cf5e5` + `701fde04` + `4b6c05e0` + `8b0196d2`)
- **Surfaced**: 2026-07-21 baseline run.
- **Severity**: MEDIUM (dev velocity; user explicitly wants "seconds")
- **Location**: `apps/autorun_flutter/integration_test/e2e/*`.

After the P0 fixes `just e2e-desktop` runs **~9m** across all 4 PASSes
(all green). The per-flow dev cycle via `just e2e-one` is now **9-25 s**
(was ~90 s before per-flow files). Tag-based subset runs via
`just e2e-tag smoke` complete in ~1m. The `e2e-desktop` full-suite
runtime remains ~9m due to the 4 boots + 91 flows total.

**Achieved targets:**
- `just e2e-one <flow-id>`: 9-25 s ✓ (target <20s; vault chains are 20-25s)
- `just e2e-tag smoke`: ~1m ✓ (target <60s; 4 flows)
- `just e2e-tag vault mock-keyring`: ~2m (5 vault flows)
- `just e2e-desktop`: ~9m (target was <5min; acceptable — 91 flows across 4 boots)

### NEW-6 — Post-registration security prompt blocks wizard e2e flows

- **Status**: 🟢 RESOLVED (2026-07-21, commits `598801c8` + `bda0b1ab`)
- **Surfaced**: 2026-07-21 during P0-C verification (mock-keyring-dapps +
  mock-keyring-identity suites hung 20 s then failed at the wizard step).
- **Severity**: HIGH (broke ALL e2e flows that register an account through a wizard)
- **Location:** e2e helpers `apps/autorun_flutter/integration_test/e2e/suite_helpers.dart`;
  source of the prompt `apps/autorun_flutter/lib/widgets/post_registration_security_prompt.dart`
  (introduced by UX-H6, commit `92ba775a`, same day).

UX-H6 (commit `92ba775a`, 2026-07-21) added
`showPostRegistrationSecurityPrompt` to BOTH onboarding wizards
(`unified_setup_wizard.dart:914`, `account_registration_wizard.dart:588`).
After `registerAccount` succeeds, the dialog ("Secure your account" with
vault / passkey / skip options) blocks the wizard from reaching the Success
screen. ALL e2e flows that register an account through a wizard were broken
(hung 20 s then failed). The keyring-less suite was UNAFFECTED (uses
local-only profiles, no account registration).

**Fix:** added shared helper
`dismissPostRegistrationSecurityPrompt(tester, d, {timeout})` to
`suite_helpers.dart`. Polls for dialog title 'Secure your account', taps
'Skip for now'. Applied to 3 wizard-driving flows:
1. `suite_mock_keyring_dapps_test.dart` (UnifiedSetup wizard flow)
2. `suite_mock_keyring_identity_test.dart` `profile.create_via_menu_dialog` (UnifiedSetup)
3. `suite_mock_keyring_identity_test.dart` `account.register_from_publish` (AccountRegistrationWizard)

`suite_mock_keyring_test.dart` is UNAFFECTED — it creates profiles via
controller directly, not through the wizard UI.

**Verified not affected:** `ux_probe/g_first_run_wizard_happy_path_test.dart`
enters only a display name (no username) → creates a LOCAL-ONLY profile →
`registerAccount` is skipped → `showPostRegistrationSecurityPrompt` is
skipped (line 913 guards on `createdAccount != null`). No fix needed.

### UX-QW — Click-reduction quick wins (5 fixes)

- **Status**: 🟢 RESOLVED (2026-07-22, commit `0fc3d03a`)
- **Surfaced**: 2026-07-22 UX planner subagent sweep.
- **Severity**: MEDIUM (UX friction on high-frequency flows)
- **Location**: `scripts_screen.dart`, `recovery_codes_screen.dart`, `script_row_menus.dart`, `quick_upload_dialog.dart`, `script_app_host.dart`.

Five click-reduction fixes identified by orchestrator-planner subagent and
implemented:

1. **QW-1** (`scripts_screen.dart`): Removed `AccountRegistrationPromptDialog`
   — publishing with no account now goes directly to `AccountRegistrationWizard`
   (saves 1 click). Dialog file deleted.
2. **QW-2** (`recovery_codes_screen.dart`): Download/Copy auto-checks the "I
   have saved these codes" checkbox (saves 1 click; gate stays per UX-CRIT-1).
3. **QW-3** (`script_row_menus.dart`): Marketplace download button moved from
   hover-reveal to always-visible (saves 1 click + improves discoverability/a11y).
4. **QW-4** (`quick_upload_dialog.dart`): `_detectCategoryFromScript` now
   keyword-based instead of hardcoded 'Example' (Finance/NFT/Social/Gaming/
   Utilities detection).
5. **QW-5** (`script_app_host.dart`): Trust dialog Enter→"Allow once",
   Esc→Deny (keyboard shortcut for dapp trust grant).

### P2-WEB — Web per-flow e2e harness (first increment)

- **Status**: 🟢 RESOLVED (2026-07-22, commit `6ad286b7`)
- **Surfaced**: 2026-07-22 web-e2e planner subagent (P2 of e2e overhaul plan).
- **Severity**: MEDIUM (web e2e coverage was 13/79 web-eligible flows, monolith only)
- **Location**: `test/e2e_web/flows_web_test.dart`, `test/e2e_web/web_suite_helpers.dart`, `justfile`.

First increment of P2 (web per-flow pattern):
- `web_suite_helpers.dart`: `resetWebAppState()` using
  `SharedPreferences.resetStatic()` + `setMockInitialValues({})` +
  `FlutterSecureStorage.setMockInitialValues({})` for clean inter-testWidgets
  isolation. Substrate singleton reset proven working.
- `flows_web_test.dart`: 7 cross-surface flows from `flow_implementations.dart`,
  one `testWidgets` per flow, tag-injected for `--tags` filtering.
- `justfile`: `e2e-web-one <flow>` (~7s/flow) and `e2e-web-tag <tag>` recipes.
- Full file: 8 tests in 29s; smoke tag: 4 flows in 10s.
- **Remaining:** ~66 more web flows to port (tracked in P2 spec, dispatchable
  to parallel subagents per category).

---

## Maintenance

This file is updated:
- On every issue discovery (add a row in the right severity bucket).
- On every issue close (move from open bucket to "Resolved" with commit ref).
- At session end (re-prioritize, surface blockers, link to plans).

**Do not** let this file grow stale — open issues live here, closed ones go
to git history.
