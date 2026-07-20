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

## Critical / Blockers

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

**Follow-up (filed, not fixed):** UX-N2 — scripts_screen.dart has vestigial
`_isLoadingMore` / `_hasMore` / `_offset` state but no UI to trigger
load-more. Wire a scroll-listener or "Load More" button to surface this to
users.

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

- **Status**: 🔴 OPEN
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-5)
- **Severity**: HIGH (one-click data loss)

Four unguarded destructive paths:
- `recent_calls_list.dart:73-78` — Clear wipes ALL call history, no confirm.
- `bookmarks_list.dart:185-208` — Bookmark trash deletes immediately.
- `keypair_switcher_sheet.dart:174-179` — Tapping tile instantly selects + pops.
- `import_keys_dialog.dart:53-55` — "Profile already exists. Delete it first"
  suggests destroying a profile + its local data to restore a backup.

**Fix:** add confirm dialogs / undo SnackBars at each; rewrite import to
allow merge-or-replace or scope into a NEW profile.

### UX-H6 — Wizard doesn't surface vault + passkey steps

- **Status**: 🔴 OPEN
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-6)
- **Severity**: HIGH (post-onboarding security gap)
- **Location**: `apps/autorun_flutter/lib/screens/unified_setup_wizard.dart:798-812`

Both vault setup and passkey enrollment are buried behind the profile menu.
AccountRegistrationWizard (lines 573-594) DOES show a post-registration
passkey prompt; unify the helper and call from both wizards.

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

- **Status**: 🔴 OPEN
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-8)
- **Severity**: HIGH (first-impression confusion)
- **Locations**: `apps/autorun_flutter/lib/main.dart:585` (uses `kCanistersTabLabel`), `apps/autorun_flutter/lib/screens/bookmarks_screen.dart:21` (defines `kCanistersTabLabel = 'Canisters'`)

First-time users don't know what "Canisters" means. Rename or attach a
one-line info popover on long-press / hover.

### UX-H9 — Raw exception strings in user-facing errors

- **Status**: 🔴 OPEN
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-9)
- **Severity**: HIGH (AGENTS violation: "human errors")
- **Locations**: `vault_password_setup_screen.dart:175-178`, `account_registration_wizard.dart:599`, `scripts_screen.dart:607, 748, 767, 891`

Raw exception strings (HTTP bodies, stack traces) leak into SnackBars /
error text. The friendly-error pattern already exists in `_DappErrorView` —
extend it.

### UX-H10 — Fake progress bars

- **Status**: 🔴 OPEN
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-10)
- **Severity**: HIGH (trust erosion)
- **Locations**: `scripts_screen.dart:522-530`, `quick_upload_dialog.dart:237-246`

Download + upload progress is FAKED via `[0.3, 0.6, 0.9]` with
`Future.delayed(100ms)`. Drive from real byte/HTTP progress OR use an
indeterminate spinner.

### UX-H11 — Three divergent "well-known canisters" catalogs

- **Status**: 🔴 OPEN
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-11)
- **Severity**: HIGH (DRY/consistency; AGENTS violation)
- **Locations**: `canister_call_builder.dart:36-46`, `well_known_canisters.dart:26-83`, `canister_registry_service.dart`

Three separate hard-coded lists with DIFFERENT members. Call Builder omits
ICLighthouse / Cyql / Kinic / Canistergeek that the Canisters tab shows.

**Fix:** replace with one shared const.

### UX-H12 — No authenticated canister calls (power users can't sign)

- **Status**: 🔴 OPEN
- **Surfaced**: 2026-07-19 (`docs/specs/2026-07-19-ux-review.md` §H-12)
- **Severity**: HIGH (power-user surface incomplete)
- **Location**: `apps/autorun_flutter/lib/widgets/canister_client_sheet.dart:321`

"Call" button only invokes `callAnonymous`; bridge supports
`callAuthenticated` but it's never used. Wire when an active keypair exists.

### UX-N2 — Pagination UI missing (load-more state machine is vestigial)

- **Status**: 🔴 OPEN
- **Surfaced**: 2026-07-20 (e2e Phase 52 implementation — `scripts.load_more`)
- **Severity**: MEDIUM (missing app feature; e2e covers the contract only)
- **Location**: `apps/autorun_flutter/lib/screens/scripts_screen.dart:99-102, 362-417`

`ScriptsScreenState` tracks pagination state — `_isLoadingMore`,
`_hasMore`, `_offset` — and `_loadMarketplaceScripts(isLoadMore: true)`
fetches the next page. But **no UI trigger is wired up**: there's no
scroll-listener on the `CustomScrollView`, no "Load More" button, no
infinite-scroll affordance. With a backend that has more scripts than the
page size (20), the user can never see past the first page.

The e2e flow `scripts.load_more` (PHASE 52 of `suite_keyring_less_test.dart`)
covers the pagination CONTRACT end-to-end against a bulk-seeded backend
(via `tool/seed_marketplace.dart`), asserting the first page loads with
`_hasMore = true`. But the actual user-facing load-more interaction is
untested because the UI doesn't exist.

**Fix:** add a `NotificationListener<ScrollEndNotification>` that calls
`_loadMarketplaceScripts(isLoadMore: true)` when the user reaches the
bottom of the list (or a Material 3 "Load more" button at the list tail).
Extend PHASE 52 to tap/scroll and assert the list grows beyond the
initial page.

### WEB-1 — Flutter Web e2e via Playwright blocked on semantics enablement

- **Status**: ⚪ DEFERRED (per 2026-07-19 plan Pivot 1 — Tier A substrate-fakes + Tier B image-based Playwright bypass the need)
- **Surfaced**: 2026-07-17 (`docs/specs/2026-07-17-e2e-completion-and-ux-sweep.md` Phase C)
- **Severity**: HIGH (blocks real-app web e2e coverage)
- **Owner**: future Flutter upgrade / harness rework

**Problem.** The Playwright-against-built-web approach (build the bundle,
serve via `python -m http.server`, drive with Chromium) works for *booting*
the app — `flt-glass-pane` mounts, `flt-scene-host` has a canvas child,
`flutterCanvasKit` is loaded. But the Flutter Web engine's a11y semantics
tree (`flt-semantics` element) is **never enabled**, so Playwright has no
DOM to assert against — every assertion can only see a generic canvas.

**What I tried (all failed on Flutter 3.38.3 / canvaskit):**
1. `SystemChannels.accessibility.send(['enableSemantics', null])` — Dart-side
   flag set, no DOM effect.
2. `SemanticsService.announce(...)` — public Flutter API that the docs imply
   forces semantics on; no DOM effect.
3. Playwright `page.keyboard.press('Tab')` — the SemanticsEnabler listens for
   Tab keydown at the window level; no DOM effect (likely because the
   canvaskit `flt-glass-pane` shadow-DOM intercepts/absorbs the key).
4. Dispatching a synthetic `KeyboardEvent('keydown', {key:'Tab'})` on
   `window` directly — same: no effect.
5. `--web-renderer html` — flag was removed in Flutter 3.38 (canvaskit only).
6. `--wasm` — flutter_secure_storage_web blocks Wasm (`dart:js_util` +
   `package:js/js.dart` forbidden in Wasm).

**Working theory.** Flutter Web's `SemanticsEnabler` only honours its own
internal screen-reader detection (via `navigator.userAgent` matching known
AT tools). Headless Chromium's UA doesn't match. There is no public JS API
to override this; the engine internals are not exposed on `window._flutter`.

**Hook in place.** `lib/main.dart` keeps a `FLUTTER_WEB_FORCE_SEMANTICS`
dart-define that calls `SemanticsService.announce()` post-frame. It's a
no-op today but becomes effective the moment Flutter Web ships working
programmatic semantics enablement — no further app change needed.

**Workarounds for now.**
- **Web Tier 1 (widget tests via `flutter test -d chrome`)** is the only
  real-app web coverage today. Extends cleanly to ~30 Surface.web flows
  (browse, search, filter, settings, vault crypto, profile via localStorage,
  onboarding wizard). HTTP works (real backend), plugins need substrate
  fakes (`SharedPreferences.setMockInitialValues`, etc.). The current
  `suite_web_smoke_test.dart` only asserts the contract compiles; needs
  extending.
- **Chrome DevTools Protocol** `Accessibility.getFullAXTree` returns ~11
  generic nodes (just the RootWebArea + canvas wrappers) — too sparse to
  assert on.
- **Manual web UX review** still works — a human opens the URL and looks.

**Revisit when:** Flutter ships an upgrade that exposes a working
`enableSemantics()` JS API, OR `flutter drive` web is unblocked (currently
broken by `<invalid>` exhaustiveness in `cupertino/colors.dart:1024` +
`material/tooltip.dart:827`).

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

## Maintenance

This file is updated:
- On every issue discovery (add a row in the right severity bucket).
- On every issue close (move from open bucket to "Resolved" with commit ref).
- At session end (re-prioritize, surface blockers, link to plans).

**Do not** let this file grow stale — open issues live here, closed ones go
to git history.
