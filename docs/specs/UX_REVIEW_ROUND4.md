# UX Review — Round 4 (Canisters / Script Details / Account)

**Date:** 2025-07-02
**Reviewer work unit:** UX-1 (LIVE-APP UX friction audit of 3 previously un-reviewed surfaces)
**Method:** App launched and driven as a real user. Two complementary live-app techniques (both exercise the **real production app/widgets**, no product mocks):

1. **Live GTK binary** under Xvfb `:99` (1440×900×24) + the committed mock Secret Service (`scripts/run-with-mock-keyring.sh`), screenshotted via ImageMagick `import -window root`. Proves the app truly runs on this box and reaches the first-run wizard.
2. **Flutter integration-test probes** (placed in `/tmp/opencode/probe_round4/`, **outside** the repo so `apps/`/`lib/` are untouched) that launch `app.main()` and pump the production `ScriptDetailsDialog` / `AccountProfileScreen`, driving them with Flutter finders and capturing screenshots straight from the render layer tree (`RenderView.layer.toImage`, the same technique Round-3 used). They also print authoritative **visible-text dumps**, which are the primary structural evidence here (the reviewer model cannot view images directly).

**Baseline:** [Round 3](UX_REVIEW_ROUND3.md) + [Round 3 Addendum](UX_REVIEW_ROUND3.md#addendum--empirical-verification-under-the-mock-secret-service). All WU-1…WU-9 / WU-S1…S3 are implemented and green. This round reviews **3 new surfaces** and re-verifies **WU-2 / WU-3**.

> **Reviewer constraint (honesty note):** this model cannot view images. The screenshots in `docs/specs/ux_screenshots/round4/` are captured as evidence for the human reader; the reviewer's own analysis is grounded in the probes' visible-text dumps + the source (`file:line`). Where a screenshot's exact on-screen state could not be textually confirmed, it is stated.

---

## Screens captured (8)

| # | File | Surface | How captured |
|---|------|---------|--------------|
| 00 | `00_new_user_wizard.png` | First-run wizard (creation form, StorageReady under mock) | Live GTK binary + ImageMagick |
| 01 | `01_new_user_scripts_empty.png` | Scripts library, no profile → WU-1 "Set Up Your Profile" CTA | Probe `a_canisters.dart` |
| 02 | `02_canisters_tab_new_user.png` | **Canisters** tab (Popular/Bookmarks/Recent) | Probe `a_canisters.dart` |
| 03 | `03_canister_client_sheet.png` | **Canisters** — canister-client bottom sheet (NNS Registry methods) | Probe `a_canisters.dart` |
| 04 | `04_details_dialog_details_tab.png` | **Details dialog** — Details tab | Probe `b_details.dart` |
| 05 | `05_details_dialog_reviews_tab.png` | **Details dialog** — Reviews tab | Probe `b_details.dart` |
| 06 | `06_details_dialog_versions_tab.png` | **Details dialog** — Versions tab | Probe `b_details.dart` |
| 07 | `07_account_screen_returning_user.png` | **Account** screen (returning user, real Ed25519 key) | Probe `c_account.dart` |

---

## Confirmation the app ran (commands used)

```bash
# 1. Rebuild (a stale binary silently misleads — Round-3 addendum lesson):
just linux                                    # build/linux/x64/release/bundle/icp_autorun (fresh)

# 2. Live GTK binary under mock keyring (genuine "regular user" launch):
Xvfb :99 -screen 0 1440x900x24 -ac +extension XTEST >/tmp/opencode/xvfb.log 2>&1 &
scripts/ux_probe_r3_addendum.sh launch docs/specs/ux_screenshots/round4/00_new_user_wizard.png 14
# -> app reached the wizard creation FORM (mock Secret Service = StorageReady);
#    app log: "mock secret service: ready"; marketplace fetch fails HTTP 530 (no API) — expected.

# 3. Integration probes driving the real production app/widgets (screenshots + text dumps):
cd apps/autorun_flutter
export LD_LIBRARY_PATH="$PWD/build/linux/x64/release/bundle/lib:$LD_LIBRARY_PATH"
flutter test /tmp/opencode/probe_round4/a_canisters.dart   # Canisters tab + client sheet
flutter test /tmp/opencode/probe_round4/b_details.dart     # ScriptDetailsDialog (3 tabs)
flutter test /tmp/opencode/probe_round4/c_account.dart     # AccountProfileScreen (real keypair)

# 4. TQ-1 WU-2/WU-3 behavioral proof (real ScriptsScreen + real crypto):
flutter test test/features/scripts/snackbar_actions_coverage_test.dart   # 3/3 PASS
```

---

# Screen 1 — "Canisters" tab (`bookmarks_screen.dart`, ~1866 lines)

## DOM / structure analysis (from probe text dump)

The 2nd nav tab is labelled **"Canisters"** (`main.dart:444`), but the screen's own AppBar title is **"Explore ICP Services"** with subtitle *"Interact with Internet Computer canisters"* (`bookmarks_screen.dart:85–91`). **The tab relabel (WU-7) did not propagate to the screen header** — a residual honesty gap (see UX-2).

The body is a single scrollable Column of three sections, each behind a large gradient "section header" card (`_buildSectionHeader`):

1. **Popular Canisters** (`:132`) — `_WellKnownList`, a `GridView` of 8 tappable cards (`_WellKnownCard`, `:1565`): NNS Registry, NNS Governance, NNS Ledger, Canlista Registry, Cyql Projects, ICLighthouse, Kinic Search, Canistergeek. Tapping a card opens the `CanisterClientSheet` modal (`_openInlineClient`, `:53`).
2. **Your Bookmarks** (`:153`) — renders the `BookmarkComposer` (an **always-visible inline form**: Canister ID / Method name / Label / "Add Bookmark") **plus** a `_BookmarksList` empty-state ("No Bookmarks Yet").
3. **Recent Calls** (`:185`) — `_RecentCallsList`, empty-state "No recent calls…".

**Canister Client** = a `showModalBottomSheet` (`CanisterClientSheet`, `:311`) with a 4-stage state machine `_ClientFlowState { disconnected, connecting, connected, ready }` (`:309`):
- **disconnected** → canister `RawAutocomplete` field + (when empty) a "Quick Start" mini-list (`_buildQuickStartSection`).
- **connecting/connected** → fetches Candid via FFI (`_fetchAndParse` → `bridge.fetchCandid`, `:423`), then renders the **method picker**.
- **ready** → input section (JSON / auto-form toggle) + the **Call** button.

### Headline finding — the method picker is overwhelming

When the probe tapped **NNS Registry**, the Candid fetch **hit the real IC mainnet** and the sheet rendered the registry's full method set as a **single `Wrap` of `FilterChip`s**: `add_api_boundary_nodes, add_firewall_rules, add_node, add_node_operator, add_nodes_to_subnet, add_or_remove_data_centers, change_subnet_membership, … update_unassigned_nodes_config` — **≈50 chips, unsearchable and ungrouped** (`_buildMethodSelector`, `bookmarks_screen.dart:819–862`). There is no search box, no query/update kind grouping, and no "common methods" pinning. A new user looking for e.g. `get_subnet` must visually scan a wall of chips. → **UX-3**.

## Click-count — most common operations

| Goal (new user, from Scripts tab) | Taps | Typing |
|---|---|---|
| Call a **Popular Canister** method (e.g. NNS Ledger `account_balance_dfx`) | **4**: Canisters tab → Popular card → method chip → **Call** | 0 (Candid auto-fetched; args auto-generated) |
| Call from a **bookmark** | **4**: Canisters tab → bookmark → method chip → Call | 0 |
| Call a **custom canister** | **5+**: Canisters tab → field → type ID → fetch → method chip → Call | canister ID |
| Add a bookmark | **3 fields + 1 tap** (form is always inline on the screen) | ID + method |

The Popular-Canister path is good (4 taps, 0 typing). The friction is **finding the right method** in the chip wall, and the **always-visible Add-Bookmark form cluttering** the explore screen (→ UX-4).

## Keyboard accessibility

- Canister field is keyboard-friendly: it's a `RawAutocomplete` with `textInputAction: done` and `onSubmitted → _fetchAndParse` (`:724`). Pressing **Enter** fetches Candid. ✔
- Method selection is **mouse-only** in practice: `FilterChip`s are reachable via Tab but there are ~50 of them — no type-to-filter, no `/`-focus shortcut. ✘
- The bottom sheet closes only via barrier tap / drag — **no `Esc` handler**. ✘
- The global shortcuts map (`keyboard_shortcuts.dart:20`) covers only Scripts-screen actions (`mod+N`, `mod+F`, `R`, `mod+1/2`, `?`); **none are Canisters-specific** (no `/` to focus the canister field, no `Enter`=Call). → UX-9.

---

# Screen 2 — `ScriptDetailsDialog` (`widgets/script_details_dialog.dart`, ~1518 lines)

> The most-traversed dialog: details → download → run.

## DOM / structure analysis (from probe text dump)

`Dialog` sized to ~90 % width × 85 % height (`:129–139`), responsive (`isNarrow = width < 600`). Layout:

- **Header** (`:142`): 48 px icon tile, `script.title` (headlineSmall bold), *"by {authorName}"*, a **category** badge, a **price** badge (`FREE` blue, or `$x.xx` green), and a star **rating** (or "No rating").
- **TabBar** (`_buildTabBar`, `:950`): **Details** (0) / **Reviews** (1) / **Versions** (2), plus a top-right close `IconButton` (`:290`).
- **Details tab**: *Description*, *Tags* (`Wrap` of label chips), *Code Preview* (first 50 lines of the bundle), the primary **Download** button ("Download FREE" / "Download $x.xx"), and a *Statistics* block (Downloads / Rating / Version / Updated / Compatible Canisters).
- **Reviews tab**: 5→1 star breakdown bars + review list.
- **Versions tab**: version history rows, each with **Diff** (`TextButton → _showVersionDiff`, `:1462`) and **Install** (`TextButton → widget.onInstallVersion`, `:1470`) actions.

### Headline finding — three concurrent network fetches fire on open

`initState` kicks off **all three** loads unconditionally (`script_details_dialog.dart:48–54`): `_loadScriptPreview()` + `_loadReviews()` + `_loadVersions()`. On this box (no marketplace API) each prints *"Failed to load … Exception: HTTP 530"* and the tabs render error strings; on a real slow link the dialog opens with **three spinners** before any content is usable. Reviews and Versions are invisible until their tab is tapped, yet they're fetched up-front. → **UX-5**.

### Secondary finding — "Code Preview" downloads the whole bundle

`_loadScriptPreview` calls `downloadScript(script.id)` and then `take(50)` lines (`:104–113`). The preview burns a full bundle download (and, for a paid script, may be unauthorized) just to show 50 lines. A dedicated lightweight preview/metadata endpoint would be cheaper and safer. → **UX-6**.

### Finding — paid scripts have no in-dialog purchase path

`scripts_screen.dart:477`: `onDownload: script.price == 0 ? () => _downloadScript(script) : null`. For a **paid** script the Download callback is `null` (button disabled/absent) and there is **no purchase CTA inside the dialog** — the user is left without an obvious next step. → folded into UX-5's scope note.

## Click-count — most common operations

| Goal | Taps |
|---|---|
| Download a **free** script then run it | **3**: tap row (opens dialog) → **Download** → **Run** (WU-2 snackbar action). WU-2 collapses the old 4-tap path. ✔ |
| Read reviews / version history | **2**: tap row → Reviews/Versions tab |
| Install an older version | **3**: tap row → Versions tab → **Install** |

## Keyboard accessibility

- The 3 tabs are custom `GestureDetector`s (`_buildTab`, `:969`) — **not** a Material `TabBar`, so there is **no built-in left/right-arrow traversal**. ✘
- **No `Esc`-to-close** handler on the dialog (only the X `IconButton`). ✘
- **No `Enter`=Download** shortcut. ✘
- Close (`Icons.close`) is an icon-only button with no `Tooltip`. (Minor.)

---

# Screen 3 — `AccountProfileScreen` (`screens/account_profile_screen.dart`, ~1239 lines)

## Reachability (important)

`AccountProfileScreen` is pushed **only** from `profile_menu.dart:359–372` (`_navigateToAccountProfile(account, profile)`), and that path runs only when an **active backend `Account` exists** (`profile_menu.dart:341–348` branches to *registration* otherwise). Consequence: a user who created a **local profile but never registered an account on the marketplace backend can never open this screen** — even though everything it shows (public keys, "Use for signing", Export, Passkey status) is **local** data. On this box (no API) the screen is therefore **unreachable via live navigation**; the probe pumps it directly with a real Ed25519 keypair (generated via FFI) and a constructed `Account`. → **UX-7**.

## DOM / structure analysis (from probe text dump)

AppBar **"My Identity"** + a `Refresh` `IconButton` (`:198`). Body is a `RefreshIndicator` → `SingleChildScrollView` Column:

- **Account header** (`_buildAccountHeader`): display name ("Alice Liddell"), `@username`, "Created … ago".
- **PROFILE section** (`_buildProfileSection`, `:386`): `Display Name *`, `Bio`, a **"Contact Info" expander** (Email / Telegram / Twitter-X / Discord / Website — collapsed by default; the probe saw the expander label, not the fields), and a **"Save Changes"** `FilledButton` (`:479`).
- **SECURITY section** (`_buildSecuritySection`, `:567`):
  - **Passkeys** tile — *"Requires browser on Linux"* (honest degradation; `PasskeyPlatform.isSupported == false` on Linux desktop). ✔
  - **Public Keys** — "1/10", per-key row with **"Use for signing"** (`:955`), remove (`IconButton :969`), **Export** (`:817`).
  - **Backup / Export** tile (`:801`).
- **FAB** `Add Key` (`:233`, bottom-right).

### Finding — contact fields hidden behind an expander

The five contact fields (Email/Telegram/Twitter/Discord/Website) are collapsed behind a single "Contact Info" expander. Discoverable, but adds a tap and the probe could not confirm any inline validation hints for the URL/email fields. (Minor; noted, not a proposal.)

### Finding — Import/Export discoverability is inconsistent

At rest the probe found **no** "Import Keys" / "Export Keys" `TextButton`s (they live at `account_profile_screen.dart:742–755` inside a layout that only surfaces them conditionally); only the **Backup/Export** tile (`:801`) is reliably visible. Import in particular is hard to find. → **UX-8**.

## Click-count — most common operations

| Goal | Taps |
|---|---|
| Edit display name | **2**: edit field → **Save Changes** |
| Switch signing key | **1**: "Use for signing" on the key row (already visible) |
| Add a key | **2**: FAB **Add Key** → generate/confirm in sheet |
| Export keys | **2**: Backup/Export tile → Export |

## Keyboard accessibility

- The profile/contact fields are standard `TextField`s → keyboard-enterable. ✔
- **No global shortcuts** for this screen (no `mod+S` to save, no `Esc`-back). The shortcuts map (`keyboard_shortcuts.dart:20`) has nothing identity-related. ✘ → UX-9.
- Per-key actions ("Use for signing", remove) are `TextButton`/`IconButton` — Tab-reachable but not shortcut-bound.

---

# WU-2 / WU-3 re-verification (live + empirical)

| | Code | Live screenshot | Behavioral test |
|---|---|---|---|
| **WU-2** "Run" `SnackBarAction` after download | `scripts_screen.dart:445–448` ✔ | **Not captured** (download needs the marketplace API; `just api-dev-up` not started this session) | **TQ-1 PASS** — `snackbar_actions_coverage_test.dart`: *"WU-2: Run snackbar action opens the execution sheet for the downloaded script"* ✔ |
| **WU-3** "Publish" `SnackBarAction` after create | `scripts_screen.dart:585–588` ✔ | **Not captured** (create→Publish is deep navigation inside `ScriptsScreen`; live pixel-coordinate driving is blocked — see honesty note below) | **TQ-1 PASS** — `snackbar_actions_coverage_test.dart`: *"WU-3: Publish snackbar action opens QuickUploadDialog when an account is registered"* **and** *"…opens the registration prompt when no account is registered"* ✔ |

**TQ-1 evidence (run this session, 3/3 green):**
```
flutter test test/features/scripts/snackbar_actions_coverage_test.dart
00:06 +1: WU-2: Run snackbar action opens the execution sheet for the downloaded script
00:07 +2: WU-3: Publish snackbar action opens QuickUploadDialog when an account is registered
00:08 +3: WU-3: Publish snackbar action opens the registration prompt when no account is registered
All tests passed!
```
These tests pump the **real `ScriptsScreen`** inside a `ProfileScope` with a **real Ed25519 keypair** (`TestKeypairFactory`) and drive the full create→Publish and download→Run chains — i.e. they exercise the production widget path end-to-end. That is stronger behavioral proof than a static screenshot.

### Why no live WU-2/WU-3 screenshot (honest)

Two independent blockers, building on the Round-3 addendum's honesty:

1. **WU-2 (download→Run)** requires marketplace connectivity. The dev API server (`just api-dev-up`) was not started this session, so `_downloadScript`'s round-trip never completes and the success snackbar never fires. (Deliberate scope choice; the task permits relying on TQ-1 here.)
2. **Pixel-coordinate input injection does not transfer to the live GTK window.** I built an **XTEST input injector** (`/tmp/opencode/xclick.c`, compiled against `libXtst` — Xvfb's XTEST extension is present, major=2/minor=2) specifically to overcome Round-3's "no xdotool/ydotool" blocker. It **does** synthesize real pointer events (verified: a click on the wizard's close button changed the screen, `compare -metric RMSE` = 0.128 vs. the wizard). **But** the live Flutter GTK window opens at its default size (< 1440×900), so the nav-tab coordinates discovered by the integration probe (e.g. Canisters tab at 966,857 on the probe's forced 1440×900 surface) **do not map** to the smaller live window — a Canisters-tab click at the probe coordinate produced a byte-identical screenshot (`compare -metric AE` = 0 vs. the prior frame), i.e. it missed. Without vision to re-aim per the live window's actual geometry, reliable blind driving of deep flows (create→Publish) is not achievable. The integration-probe route (Flutter finders, not pixels) remains the faithful method and is what produced screenshots 01–07.

The **single former blocker from Round-3 — "no profile / no secure storage" — is gone** (mock Secret Service + the in-probe channel mocks make `SecureStorageReadiness` return `StorageReady`); the residual gap is purely input-injection/geometry, not a product defect.

---

# Proposals — derived UX Work Units (UX-2 … UX-9)

Each accepted proposal below is a derived UX WU for `UI_EXCELLENCE_PLAN.md`, in the established format. Priorities: **P0**=ship-blocking honesty/correctness, **P1**=high-friction, **P2**=polish. Effort: **S/M/L**.

### UX-2 — Canisters: make the screen header match the "Canisters" tab  [P0, S]
- **User problem:** WU-7 relabelled the nav tab to **"Canisters"** but the screen's AppBar still says **"Explore ICP Services"** ("Interact with Internet Computer canisters"). The first thing a new user sees on the tab contradicts the tab name — an honesty/consistency gap WU-7 explicitly set out to fix.
- **Grounding:** `apps/autorun_flutter/lib/screens/bookmarks_screen.dart:85` (`Text('Explore ICP Services')`) and `:88` subtitle vs `apps/autorun_flutter/lib/main.dart:444` (`label: 'Canisters'`). Confirmed live: probe printed `navLabel="Canisters"=true appBarTitle="Explore ICP Services"=true`.
- **Concrete change:** Set the AppBar title to `Canisters` (or `Canister Tools`) and adjust the subtitle to one honest line, e.g. *"Call Internet Computer canisters directly"*. No logic change.
- **Dependencies / Risk:** none / **LOW** (string change + 1 test assertion).
- **Acceptance:** a nav-label/header consistency test; `just test-feature scripts` green.

### UX-3 — Canisters: searchable, grouped method picker (collapse the ~50-chip wall)  [P1, M]
- **User problem:** Calling a real canister dumps its entire Candid method set as one unsearchable `Wrap` of `FilterChip`s — the NNS Registry alone exposes ≈50 methods (`add_api_boundary_nodes … update_unassigned_nodes_config`). A user cannot find `get_subnet` without scanning the wall.
- **Grounding:** `bookmarks_screen.dart:819–862` (`_buildMethodSelector` → `Wrap(children: _methods.map((m) => FilterChip(...)))`). Confirmed live: the canister-client sheet (shot 03) rendered all ≈50 NNS methods as chips, fetched from the real IC mainnet.
- **Concrete change:** (a) add a **search/filter text field** above the chip wrap that filters `_methods` by name (substring); (b) **group by kind** (query / update / composite) with small section labels; (c) optionally **pin "common" methods** (e.g. `http_request`, `account_balance_dfx`) at the top for well-known canisters. Keep the existing `_selectMethod` contract.
- **Dependencies / Risk:** none / **MED** (pure presentation; gate behind a `canister_method_picker_test.dart`).
- **Acceptance:** with ≥20 methods, typing in the filter reduces the chip count; `just test-feature scripts` green.

### UX-4 — Canisters: collapse the inline "Add Bookmark" form behind a button  [P2, S]
- **User problem:** The "Your Bookmarks" section always renders the full `BookmarkComposer` form (Canister ID / Method / Label / Add Bookmark) inline on the explore screen, even when empty — visual clutter that pushes Recent Calls below the fold.
- **Grounding:** `bookmarks_screen.dart:161–173` (`BookmarkComposer(onSave: BookmarksService.add, …)` always in the tree). Visible in shot 02.
- **Concrete change:** Render a compact `OutlinedButton.icon` ("+ Add Bookmark") that expands the `BookmarkComposer` on tap (and auto-collapses after save). Keep the existing `_BookmarksList` empty-state.
- **Dependencies / Risk:** none / **LOW**.
- **Acceptance:** default explore view shows the button, not the form; tapping expands it.

### UX-5 — Details dialog: lazy-load Reviews/Versions per-tab; add a purchase CTA for paid scripts  [P1, M]
- **User problem (a):** `initState` fires **three** network loads at once (`_loadScriptPreview` + `_loadReviews` + `_loadVersions`), so the dialog opens with three spinners on a slow link and three error strings when offline. **(b):** for a **paid** script the Download callback is `null` (`scripts_screen.dart:477`) and there is **no in-dialog purchase CTA** — a dead end.
- **Grounding:** `widgets/script_details_dialog.dart:48–54` (initState triple-load); `:56`, `:77`, `:98` (the three loaders); `screens/scripts_screen.dart:477` (`onDownload: script.price == 0 ? … : null`). Confirmed live: tabs printed "Failed to load … HTTP 530" (shot 04/05/06).
- **Concrete change:** (a) load only the **Details/preview** content on open; fetch reviews/versions **when their tab is first selected** (track a `_loadedTabs` set). (b) When `script.price > 0`, render a **"Purchase & Download"** primary action (wires to the existing purchase flow) instead of leaving the dialog action-less.
- **Dependencies / Risk:** none / **MED** (lifecycle change — add a test that reviews are *not* fetched until the tab opens; purchase wiring depends on the existing purchase path).
- **Acceptance:** opening the dialog issues exactly one fetch until another tab is tapped; paid scripts show a purchase CTA; `just test-feature scripts` green.

### UX-6 — Details dialog: stop downloading the full bundle just for the 50-line preview  [P2, M]
- **User problem:** `_loadScriptPreview` calls `downloadScript(id)` and then `take(50)` lines — a full bundle download (potentially unauthorized for paid scripts) to show a snippet.
- **Grounding:** `widgets/script_details_dialog.dart:104–113`. Confirmed live: the preview path is the one that printed "Failed to load preview: HTTP 530".
- **Concrete change:** Prefer a backend **preview/metadata** endpoint (first N lines / description) when available; fall back to the full download only as a last resort for free scripts. Coordinate with backend (`backend/`).
- **Dependencies / Risk:** depends on a backend preview endpoint (cross-team) / **MED**.
- **Acceptance:** preview renders from the lightweight endpoint; no full-bundle fetch for paid scripts.

### UX-7 — Account: make local key management reachable WITHOUT backend registration  [P0/P1, M]
- **User problem:** `AccountProfileScreen` (public keys, "Use for signing", Export, Passkey status — **all local data**) is only reachable when a **backend `Account` exists**. A user with a local-only profile can never open it. This gates the entire key surface behind marketplace registration.
- **Grounding:** `widgets/profile_menu.dart:341–348` (createAccount branch) and `:359–372` (`_navigateToAccountProfile(account, profile)` requires an `Account`). Confirmed live: the screen is **unreachable via nav** on this box (no API); probe had to pump it directly.
- **Concrete change:** Split the screen into a **local-key surface** (always reachable from the profile menu for any profile) and the **backend-account fields** (username/contacts, shown only when registered; otherwise a "Register an account" CTA). Reuse the existing `_buildSecuritySection` for the local part.
- **Dependencies / Risk:** touches `profile_menu.dart` + the screen's `initState` (`_refreshAccount`) / **MED**. Respect A-3 (only the active profile's own keys).
- **Acceptance:** with a local-only profile, the profile menu opens the key surface (no crash, no backend call); `just test-feature profile` green.

### UX-8 — Account: unify Import/Export discoverability  [P2, S]
- **User problem:** At rest neither "Import Keys" nor "Export Keys" `TextButton`s are visible (they're conditionally laid out at `account_profile_screen.dart:742–755`); only the "Backup / Export" tile (`:801`) is reliably shown. Import in particular is hard to find.
- **Grounding:** `account_profile_screen.dart:742–755` (Import/Export `TextButton.icon`s) vs `:801–819` (Backup/Export tile). Confirmed live: probe found `hasImportKeys=false`, `hasExportKeys=false` at rest (shot 07).
- **Concrete change:** Surface a single consistent **"Manage keys"** group with Import + Export actions always visible (Export may still route through the Backup tile; Import should not be hidden).
- **Dependencies / Risk:** none / **LOW**.
- **Acceptance:** Import and Export are both reachable from the default account-screen view.

### UX-9 — Keyboard shortcuts for the 3 audited surfaces  [P2, M]
- **User problem:** The shortcuts map (`widgets/keyboard_shortcuts.dart:20` `kShortcutSpecs`) and the `?` help sheet (WU-6) cover **only Scripts-screen actions** (`mod+N`, `mod+F`, `R`, `mod+1/2`, `?`). The three audited surfaces are essentially mouse-only: the canister-client method picker has no type-to-filter; the details dialog has no `Esc`-close / `Enter`=Download and its tabs aren't arrow-traversable; the account screen has no `mod+S` save / `Esc`-back.
- **Grounding:** `widgets/keyboard_shortcuts.dart:20–26` (only 6 specs, all Scripts/nav); `bookmarks_screen.dart:819` (chips), `widgets/script_details_dialog.dart:290/950/969` (close + custom tabs), `screens/account_profile_screen.dart:479` (Save).
- **Concrete change:** Add to `kShortcutSpecs` + wire `Shortcuts`/`Actions`: Canisters — `/` focus canister field, `Esc` close sheet; Details dialog — `Esc` close, `Enter` = primary action (Download/Purchase), ←/→ tab traversal (or convert `_buildTab` to a real `TabBar`); Account — `mod+S` save, `Esc` back. All appear in the `?` sheet.
- **Dependencies / Risk:** ideally after UX-3/UX-5 (so the targets exist) / **MED**.
- **Acceptance:** each new shortcut has a test; the `?` sheet lists them; `just test-feature scripts`/`profile` green.

---

# Top friction — 3–5 bullets per screen

**Canisters (UX-2/UX-3/UX-4):**
1. Tab says "Canisters", screen header says "Explore ICP Services" — contradictory (UX-2).
2. Real canisters dump ~50 method chips with no search/grouping — method discovery is the dominant friction (UX-3).
3. Inline Add-Bookmark form always clutters the explore screen (UX-4).
4. No Canisters-specific keyboard shortcuts (UX-9).

**Script Details (UX-5/UX-6):**
1. Three concurrent network fetches on open → triple spinner/error on slow/offline links (UX-5).
2. Preview downloads the full bundle to show 50 lines (UX-6).
3. Paid scripts have no in-dialog purchase CTA (Download is `null`) (UX-5b).
4. Custom tabs aren't keyboard-traversable; no `Esc`/`Enter` shortcuts (UX-9).

**Account (UX-7/UX-8):**
1. The whole key surface is gated behind backend account registration, even though it's local data (UX-7).
2. Import/Export discoverability is inconsistent; Import is hidden at rest (UX-8).
3. Contact fields collapsed behind an expander (minor; noted, not a WU).
4. No identity-screen shortcuts (UX-9).

---

## Confidence: 8.5 / 10

- **High confidence** on the structural/click-count analysis and all 8 derived WUs: grounded in the live probes' visible-text dumps (which confirmed, e.g., the tab-vs-header mismatch, the ≈50 NNS method chips, the triple fetch, and the collapsed contact expander) + the source (`file:line`) + 8 screenshots.
- **WU-2/WU-3** are empirically green via the TQ-1 test (real `ScriptsScreen` + real crypto); the only gap is the live screenshot, blocked by input-injection geometry (honestly explained) — **not** by the former secure-storage blocker, which is resolved.
- **Half-point held back** because: (a) the reviewer cannot view the screenshots directly (analysis rests on text dumps + code); (b) two screens (Details, Account) were pumped directly rather than reached through live navigation (Details needs the marketplace API; Account is gated behind backend registration — itself UX-7); (c) the live GTK window's default size prevented pixel-coordinate transfer for genuine live deep-flow screenshots.

No app source was modified (`git status` shows only `docs/specs/ux_screenshots/round4/` + this doc). Probe code lives in `/tmp/opencode/probe_round4/` (outside the repo).
