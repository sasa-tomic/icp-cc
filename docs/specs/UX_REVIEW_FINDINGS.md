# UX-1 — UX Review Findings & Click-Reduction Proposals

- **Status:** Observational deliverable (UX-1 of `PROD_READINESS_PLAN.md`). **No application code was changed.**
- **Date:** 2026-07-01
- **Target:** Linux desktop (`flutter run -d linux`). Flutter Web is **deferred (R-1)** — not used.
- **Scope:** Per-flow gesture counts + radical click-reduction proposals for the 6 flows defined in UX-1.
- **Method:** Code-grounded click-count analysis of the actual widgets, cross-checked against a live Linux-desktop build. Proposals only.

---

## 1. Methodology & Environment (honest limitations)

### What ran
- **Flutter:** 3.38.3 / Dart 3.10.1.
- **Device:** `Linux (desktop) • linux-x64 • Debian 13`, detected by `flutter devices`.
- **Native lib:** pre-built release bundle at
  `apps/autorun_flutter/build/linux/x64/release/bundle/` (incl. `libicp_core.so`,
  `libapp.so`). Launched directly under a virtual framebuffer.
- **Display:** no physical `$DISPLAY`; used the existing `Xvfb :99 -screen 0
  1440x900x24` already running in the sandbox. `export DISPLAY=:99`.
- **Capture tool:** ImageMagick `import -window root` (no `scrot`/`ffmpeg`/`xdotool`
  available). App launched and **ran cleanly** (only harmless GTK init noise:
  `Atk-CRITICAL atk_socket_embed` / `fl_gnome_settings` GSettings assertion — these
  do not affect rendering).
- **Backend:** the marketplace/account API was **not** started for this run
  (`just api-dev-up`). The app degrades gracefully (loading/empty states). This is
  fine for click-counting because the gesture graph is encoded in the widgets, not
  the network responses.

### What was captured
- Two full-screen screenshots saved under `docs/specs/ux_screenshots/`:
  - `00_initial_state.png`
  - `01_settled_state.png`
- Both are non-blank renders (ImageMagick `identify` reports pixel stdev ≈ 29 000,
  i.e. real content, not a uniform frame).

### Honest limitation
- **The agent model driving this review cannot read images.** The screenshots are
  therefore committed as **artifacts for human review**, not as something this
  report "saw". Every gesture count below is derived by **reading the widget code**
  (`apps/autorun_flutter/lib/screens/` + `lib/widgets/`) and tracing entry points
  (FABs, `onTap`s, dialogs, sheets) with `file:line` citations. This is the core
  UX-1 deliverable and it does **not** require screenshots.
- I could not drive the UI further (no `xdotool` to synthesize taps against the
  running GTK window), so no per-step screenshots beyond the launch state.

### Reading the counts
- A **"tap"** = one discrete user gesture: a button/FAB/list-tile press, a sheet
  open, or a confirmation. Pure typing into an already-focused field is called out
  as a **text entry**, not counted as a tap. The goal is to count the *decision
  points* the user must cross.

---

## 2. Per-Flow Analysis

---

### Flow 1 — Onboarding → first profile

**Goal:** from cold launch, reach a usable profile (local identity + keypair, and
optionally a marketplace @username).

**Screenshot:** `docs/specs/ux_screenshots/00_initial_state.png` (the empty
Scripts screen a first-run user actually lands on — there is **no** profile/setup
prompt).

**Observed gesture count (true first run, zero profiles):**
1. Cold launch → `MainHomePage` (`main.dart:181`) → `ScriptsScreen`. The onboarding
   check `_checkAndShowOnboarding` (`main.dart:285`) calls
   `OnboardingService.shouldShowOnboarding`, which **always returns `false`**
   (`onboarding_service.dart:42`, “no upfront onboarding”). So the user lands
   directly on the Scripts screen with **no profile-creation prompt**.
2. `ProfileController.ensureLoaded()` (`profile_controller.dart:60`) only *loads*
   profiles — it **does not auto-create a default profile**. So a brand-new user
   has zero profiles and zero keypairs, yet sees a Scripts screen whose empty
   state only offers “Create Script” / “Browse Marketplace”
   (`scripts_screen.dart:894`–`902`) — neither of which is meaningful without a
   keypair.
3. Tap the **Profile avatar** (top-right, `main.dart:393` → `_showProfileMenu`
   `main.dart:311`) — **[1 tap]** → profile menu bottom sheet.
4. Tap **“Switch Profile”** (`profile_menu.dart:216`) — **[1 tap]** →
   `_ManageProfilesSheet` (`profile_menu.dart:326`).
5. Tap **“Create New Profile”** (`profile_menu.dart:551`) — **[1 tap]** →
   `_CreateProfileDialog` (`profile_menu.dart:596`).
6. Type a profile name — **[1 text entry]** (field is pre-filled “New Profile”,
   `profile_menu.dart:604`).
7. Tap **“Create”** (`profile_menu.dart:629`) — **[1 tap]** → `createProfile`
   (`profile_menu.dart:354`). No success screen; the sheet just closes.

**Total: 4 taps + 1 text entry** to create the first profile, with **zero
in-app guidance** that this is the required first step. And the profile created
here has **no marketplace @username** — registering one is a *separate* multi-step
flow (Profile avatar → “My Account” → `AccountRegistrationWizard`).

**Friction points:**
- **No first-run guidance.** The empty Scripts screen never mentions profiles or
  keypairs (`scripts_screen.dart:894`–`902`).
- **Profile creation is buried** three taps deep behind the Profile avatar
  (`profile_menu.dart:216` → `:326` → `:551` → `:596`).
- **The polished single-screen onboarding is orphaned.** `UnifiedSetupWizard`
  (`unified_setup_wizard.dart`) is the *designed* first-run flow: one form,
  auto-focused Display Name (`unified_setup_wizard.dart:148`), an optional
  username with live validation, a single “Get Started” button
  (`unified_setup_wizard.dart:334`), and a success screen with “Start Exploring”
  (`unified_setup_wizard.dart:408`). **It is referenced only in tests**
  (`test/screens/unified_setup_wizard_test.dart`) and is **never constructed in
  `lib/`** — i.e. production dead code. (See Bugs §4-B3.)

**Reduction proposals (ranked):**

| # | Proposal | Impact | Effort | Grounding |
|---|----------|--------|--------|-----------|
| 1.1 | **Wire the orphaned `UnifiedSetupWizard` as the first-run gate** when `profileController.profiles.isEmpty` (in `MainHomePage._checkAndShowOnboarding`, `main.dart:285`). Collapses first-profile to **1 screen + 1 success screen**, auto-focused name, optional username in the same form. | **HIGH** | Low | `main.dart:285`; `unified_setup_wizard.dart:148/334/408` |
| 1.2 | **Fix the first-run dead-end CTA.** With no profile, tapping the highlighted “My Account / Register to publish scripts” tile is a **silent no-op** because `_handleAction(createAccount)` guards `if (profile != null)` (`profile_menu.dart:255`). Redirect to profile creation, or disable + explain. | **HIGH** | Low | `profile_menu.dart:255` |
| 1.3 | Add a **“Set up your profile”** primary CTA to the Scripts empty state for first-run users (`scripts_screen.dart:894`–`902`). | MED | Low | `scripts_screen.dart:894` |

**Proposed target:** first profile in **2 taps** (enter name → “Get Started”) +
1 text entry, down from 4 taps; with optional @username in the same screen.

---

### Flow 2 — Browse marketplace → download → run

**Goal:** from app open to a running script’s rendered `view`.

**Screenshot:** none beyond launch state (backend not running → list shows
loading/empty; the gesture graph is fully traceable from code).

**Observed gesture count — fastest path (hover-reveal download):**
1. App opens; marketplace auto-loads in `ScriptsScreen.initState`
   (`scripts_screen.dart:96` → `_initializeMarketplaceData` `:172`). Items render
   in the unified list; each marketplace row exposes a hover-reveal **Download**
   action (`scripts_screen.dart:1394`–`1401`, `_buildMarketplaceScriptMenu`).
2. Tap the **Download icon** on a marketplace row — **[1 tap]** → `_downloadScript`
   (`scripts_screen.dart:356`) → creates a local `ScriptRecord` (`:386`) + SnackBar
   “added to your library” (`:419`).
3. Locate the newly-downloaded **local** copy in the list, tap it — **[1 tap]** →
   `_runScript` (`scripts_screen.dart:469`, via `_handleAllScriptsItemTap:1529`
   for local source) → `showScriptExecutionBottomSheet` (`:493`) → `ScriptAppHost`
   renders the `view`.

**Total (fastest): 2 taps** + a visual search for the new local item. (Meets the
≤2 target, but with discovery friction.)

**Observed gesture count — details-dialog path (what a touch user hits, since
single-tap opens details, not download):**
1. Tap a marketplace row — **[1 tap]** → `_showScriptDetails`
   (`scripts_screen.dart:1537`) → `ScriptDetailsDialog`.
2. Tap **“Download FREE”** (`script_details_dialog.dart:497`) — **[1 tap]** →
   download + SnackBar. **The dialog does not auto-close.**
3. Close the details dialog (X / back) — **[1 tap]**.
4. Tap the downloaded local row — **[1 tap]** → run.

**Total (dialog path): 4 taps.**

**Friction points:**
- **No “Run now” after download.** The post-download SnackBar
  (`scripts_screen.dart:419`–`436`) has no action button.
- **Single-tap = details dialog**, not download (`scripts_screen.dart:1537`). The
  fastest affordance (download) is hidden behind hover-reveal, which desktop
  touchpads/mouse users get but is less discoverable.
- **Downloaded script appears as a separate local list item**, forcing the user to
  visually re-locate it before running.

**Reduction proposals (ranked):**

| # | Proposal | Impact | Effort | Grounding |
|---|----------|--------|--------|-----------|
| 2.1 | **Add a “Run” `SnackBarAction`** to the “added to your library” SnackBar (or auto-open the run sheet on download). Collapses the dialog path 4 → 2 taps. | **HIGH** | Low | `scripts_screen.dart:419` |
| 2.2 | **Make single-tap on a marketplace row = download**, demote “View Details” to long-press / overflow. Then tap-row → download → tap-run = 2 taps with no dialog. | MED | Low | `scripts_screen.dart:1537` |
| 2.3 | Inline a one-line description/source badge in the row so users needn’t open details just to peek. | LOW | Med | `scripts_screen.dart:944` |

**Proposed target:** **2 taps** (download → run), no dialog, with a one-tap “Run”
from the post-download SnackBar as a 1-tap shortcut.

---

### Flow 3 — Author → validate → publish

**Goal:** from the Scripts screen to a published marketplace bundle.

**Observed gesture count (assuming an account already exists):**
1. Tap the **“New Script” FAB** (`scripts_screen.dart:800`–`812`) — **[1 tap]** →
   `_showCreateSheet` (`:540`) → `ScriptCreationScreen`.
2. Author code (text entry — the actual work). The form is **single-page**:
   template pre-selected (`script_creation_screen.dart:90`, first non-blank
   template), title/emoji pre-filled (`:95`), code editor pre-filled (`:93`).
3. Tap **“Create Script”** (`script_creation_screen.dart:510`) — **[1 tap]** →
   `_createScript` (`:123`) → back to list + SnackBar
   (`scripts_screen.dart:549`).
4. Tap the **Share icon** (hover-reveal, unpublished scripts only,
   `scripts_screen.dart:1258`–`1263`) — **[1 tap]** → `_publishToMarketplace`
   (`:580`) → `QuickUploadDialog` (`:622`).
5. Tap **“Upload to Marketplace”** (`quick_upload_dialog.dart:519`) — **[1 tap]**
   → `_uploadScript` (`:176`) → signs + uploads → SnackBar.

**Total: 4 action taps** (+ authoring). The publish dialog is already
single-page: title/description/category/tags/price are **auto-generated from the
script** (`quick_upload_dialog.dart:83`–`98`), and the code-review step is a
collapsed `ExpansionTile` (“Preview code (optional)”, `:553`) rather than a forced
extra step. This confirms the collapse the plan attributed to commits `4d6002a` /
`245d065`.

**Friction points:**
- After creating a script you **return to the list** and must locate the new item
  to reach “Share”; there is no Publish affordance inside the editor itself.
- **No bundle-sandbox validation gate on publish.** `_uploadScript`
  (`quick_upload_dialog.dart:176`) validates only the **form** (title/desc/price
  non-empty: `:417`–`419`, `:432`, `:489`). It does **not** call
  `ScriptValidationService` to reject `eval` / `new Function` / `import` /
  `Intl.*` before signing+uploading. (See Bugs §4-B5 — this is a safety gap, not a
  click count.)

**Reduction proposals (ranked):**

| # | Proposal | Impact | Effort | Grounding |
|---|----------|--------|--------|-----------|
| 3.1 | Add **“Create & Publish”** to `ScriptCreationScreen` that chains straight into `QuickUploadDialog`, removing the list round-trip. −1 tap. | MED | Low | `script_creation_screen.dart:510` |
| 3.2 | **(Safety, not clicks)** Run `ScriptValidationService` over the bundle inside `_uploadScript` before signing; reject sandbox escapes with a clear error. | **HIGH** (correctness) | Low | `quick_upload_dialog.dart:176` |
| 3.3 | Add a **“Share” `SnackBarAction`** to the “Script created successfully!” SnackBar (`scripts_screen.dart:551`) as a 1-tap shortcut to publish. | LOW | Low | `scripts_screen.dart:551` |

**Proposed target:** **3 taps** (New Script → Create & Publish → Upload), with a
validation gate added so “publish” stays safe.

---

### Flow 4 — Run a script → interact → trigger an `icp_call` action

**Goal:** from a rendered script `view`, tap a button that issues an `icp_call`,
and see the result.

**Observed gesture count — first call to a given canister/method:**
1. A script is running (bottom sheet `ScriptExecutionBottomSheet` or full-screen
   `ScriptAppHost`). `ui_v1_renderer` renders a `button` node
   (`ui_v1_renderer.dart:145`–`157`); tapping calls `onEvent(onPress)`.
2. Tap the rendered button — **[1 tap]** → `ScriptAppHost.onEvent`
   (`script_app_host.dart:535`) → `_dispatch` (`:482`) → `runtime.update` →
   effects → `_executeEffects` (`:119`) → `kind == 'icp_call'` (`:140`) →
   `_ensurePermissionForCall` (`:152`) → `_showPermissionDialog` (`:430`).
3. The permission dialog has **three** buttons: **Deny / Allow once / Always
   allow** (`script_app_host.dart:443`–`452`); “Always allow” is the `FilledButton`
   (default). Tap it — **[1 tap]** → call executes → result enqueued → re-render.

**Total (first time): 2 taps** (button + permission). **Subsequent calls to the
same canister/method:** after “Always allow”, the decision is remembered for the
session (`script_app_host.dart:372`–`374`, `_sessionAllow`), so tapping the button
is **1 tap → result**. **This already meets the ≤1-tap target.**

**Friction points:**
- Minimal. The 3-button dialog is slightly heavy but “Always allow” is correctly
  the default and persists per session.

**Reduction proposals (ranked):**

| # | Proposal | Impact | Effort | Grounding |
|---|----------|--------|--------|-----------|
| 4.1 | Collapse the dialog to **2 buttons** (“Always allow for this canister” / “Deny”). “Allow once” is rarely useful and adds cognitive load. Marginal. | LOW | Low | `script_app_host.dart:446` |
| 4.2 | Remember “Always allow” **persistently** (across app restarts) per profile, not just per session, so the first-call 2-tap cost is paid once ever. | LOW | Med | `script_app_host.dart:372` |

**Proposed target:** unchanged — **1 tap** after first approval (already met).

---

### Flow 5 — Profile / keypair management

**Goal:** switch the active profile; add a keypair; set the signing key.

**Observed gesture count — switch active profile:**
1. Tap **Profile avatar** (`main.dart:393`) — **[1 tap]** → menu.
2. Tap **“Switch Profile”** (`profile_menu.dart:216`) — **[1 tap]** →
   `_ManageProfilesSheet` (`profile_menu.dart:326`).
3. Tap the target profile — **[1 tap]** → `setActiveProfile` + SnackBar
   (`profile_menu.dart:531`–`544`).

**Total: 3 taps** to switch. (Target ≤2.)

**Observed gesture count — add a keypair:**
1. Tap Profile avatar — **[1 tap]**.
2. Tap **“My Account”** (`profile_menu.dart:203`) — **[1 tap]** →
   `AccountProfileScreen`.
3. Tap the **“Add Key” FAB** (`account_profile_screen.dart:233`) — **[1 tap]** →
   `AddAccountKeySheet` (`:1123`).
4. Fill label + confirm — **[entry + 1 tap]**.

**Total: ~4 taps** to add a key.

**Observed gesture count — set signing key:** the **“Use for signing”** button is
inline on each eligible key card (`account_profile_screen.dart:973`–`982`) →
**1 tap**. Good.

**Friction points:**
- The **“Switch Profile” intermediary sheet** adds a tap (menu → sheet → profile).
- Profile switching is not surfaced in the menu header; you must open a sub-sheet.

**Reduction proposals (ranked):**

| # | Proposal | Impact | Effort | Grounding |
|---|----------|--------|--------|-----------|
| 5.1 | **Inline the profile list** in the profile menu (or make tapping a profile in the menu switch directly). Switch drops 3 → 2 taps. | **HIGH** | Low | `profile_menu.dart:216` / `:326` |
| 5.2 | Surface the **active profile + fast-switch** control in the menu header (`profile_menu.dart:108`–`196`) so switching is avatar → profile. | MED | Low | `profile_menu.dart:108` |
| 5.3 | Add a quick **“Add key”** action in the menu when a profile is active (skips navigating to `AccountProfileScreen`). | LOW | Med | `profile_menu.dart:198` |

**Proposed target:** switch profile in **2 taps**.

---

### Flow 6 — Passkey setup (environment-blocked on Linux desktop)

**Status:** per `AGENTS.md` (“Passkey Testing on Linux”) and R-1, the `passkeys`
package does not support Linux desktop, so `PasskeyPlatform.isSupported == false`
here. The happy path **cannot be exercised** in this environment. What follows is
the **graceful-degradation behavior** observed in code.

**Observed degradation (code-grounded):**
- `PasskeyManagementScreen._loadPasskeys` short-circuits when
  `!PasskeyPlatform.isSupported` (`passkey_management_screen.dart:33`) and sets an
  error message; `_buildUnsupportedPlatformError` (`:227`) then renders
  “Passkeys require a browser on Linux” plus a monospace command block
  `flutter run -d chrome` and bullets for KeePassXC / phone (hybrid) / hardware
  key.
- `AccountProfileScreen._buildPasskeysRow` routes to `_buildLinuxPasskeyRow`
  (`account_profile_screen.dart:606` → `:651`) — an `ExpansionTile` “Requires
  browser on Linux” that **also** shows `flutter run -d chrome` (`:703`).
- `AccountRegistrationWizard._registerAccount` only offers the post-registration
  passkey prompt when `widget.isPasskeySupported()` — which defaults to
  `PasskeyPlatform.isSupported` = **false** on Linux
  (`account_registration_wizard.dart:573`). So the prompt is correctly skipped;
  registration resolves with the `Account` as expected.

**Friction / correctness points:**
- **The in-app unsupported instructions advertise a broken command.** `flutter
  run -d chrome` is **unreachable** today: the Web build cannot compile because of
  the unconditional `dart:ffi` import (R-1 / `TODO.md` F-0). This appears in
  **three** places: `passkey_management_screen.dart:37`, `:228`, and
  `account_profile_screen.dart:703`. Users who follow the instruction hit a hard
  build failure with no in-app recourse. (See Bugs §4-B2.)
- The “copy the command” affordance on the unsupported screen is a **no-op stub**
  (`passkey_management_screen.dart:282`–`292`, “For now, just a visual hint”).

**Reduction/correctness proposals (ranked):**

| # | Proposal | Impact | Effort | Grounding |
|---|----------|--------|--------|-----------|
| 6.1 | **Fix the stale instructions** — stop advertising `flutter run -d chrome` until R-1 resolves. State passkeys are supported on macOS/Windows/Android, or remove the command block. Aligns with `PROD_READINESS_PLAN` FC-3. | **HIGH** (correctness) | Low | `passkey_management_screen.dart:37/228`; `account_profile_screen.dart:703` |
| 6.2 | Implement the **copy-to-clipboard** affordance (currently a stub) so users can at least copy whatever command is shown. | LOW | Low | `passkey_management_screen.dart:282` |

**Proposed target:** N/A (environment-blocked). A real-device review (macOS /
Windows / Android, or after R-1 restores Web) would measure the genuine
registration → passkey-enrollment flow and the vault-password setup
(`vault_password_setup_screen.dart`) that is unreachable here.

---

## 3. Cross-Cutting Findings

1. **First-run has no on-ramp.** A zero-profile user lands on an empty Scripts
   screen with no path to identity creation (`scripts_screen.dart:894`;
   `onboarding_service.dart:42` always returns false). The empty-state CTAs
   (“Create Script” / “Browse Marketplace”) presuppose a keypair the user doesn’t
   have.
2. **Dead-end / silent no-op CTAs.** Beyond the passkey stub, the most serious is
   “My Account” doing nothing when there is no active profile
   (`profile_menu.dart:255`). Silent no-ops violate the project’s “fail loud”
   rule (`AGENTS.md`).
3. **Stale instructions pointing at a broken target.** `flutter run -d chrome` is
   advertised in 3 in-app surfaces despite R-1 making it unbuildable.
4. **Orphaned production code.** `UnifiedSetupWizard` (the *designed* onboarding)
   is reachable only from tests. Either wire it in or delete it — currently it is
   both a UX miss and dead code.
5. **Post-action SnackBars rarely carry actions.** Download (“added to your
   library” — `scripts_screen.dart:419`) and create (“Script created
   successfully!” — `:551`) both stop at a message; adding `SnackBarAction`s
   (“Run” / “Share”) would cut a tap off two core loops at near-zero cost.
6. **Publish path lacks a sandbox-validation gate** (`quick_upload_dialog.dart:176`
   validates form fields only). The Rust sandbox rejects `eval`/`Function`/
   `import`/`Intl.*` at execution; the Dart publish UI does not pre-check.
7. **Hover-reveal actions are the fast path on desktop but undiscoverable on
   touch.** The fastest download/publish affordances live in `HoverRevealActions`
   (`scripts_screen.dart:1244`/`1392`). Fine for desktop; verify the touch
   fallback is obvious on Android.
8. **Three-button permission dialog** for `icp_call` (`script_app_host.dart:430`)
   is slightly heavy; “Always allow” is already the default, which is right.

---

## 4. Bugs / Blockers Observed (documented, NOT fixed — observational scope)

- **B1 — First-run “My Account” is a silent no-op.**
  `ProfileMenuWidget._handleAction(ProfileMenuAction.createAccount)` guards
  `if (profile != null)` (`profile_menu.dart:255`). On a true first run there is
  no active profile, so tapping the highlighted “My Account / Register to publish
  scripts” tile does **nothing** — no navigation, no error, no feedback.
  (FIXED in `4e5e728`: the My Account tile always renders; with no active
  profile it routes to profile creation/selection instead of no-op’ing.)
- **B2 — In-app instructions advertise an unreachable command.** Three surfaces
  tell users to run `flutter run -d chrome` for passkeys
  (`passkey_management_screen.dart:37`, `:228`;
  `account_profile_screen.dart:703`), but the Web build is unbuildable (R-1:
  unconditional `dart:ffi` import in `lib/main.dart:11` and
  `lib/rust/native_bridge.dart:2`). Following the instruction yields a hard build
  failure.
  (FIXED in `5116b27`: removed `flutter run -d chrome` everywhere; passkey
  surfaces now state macOS/Windows/Android support and reference R-1, since no
  command — not even `flutter run -d linux` — enables passkeys on this box.)
- **B3 — Orphaned onboarding wizard.** `UnifiedSetupWizard`
  (`unified_setup_wizard.dart`) is the designed single-screen first-run flow but
  is constructed **only in tests** (`test/screens/unified_setup_wizard_test.dart`)
  and **never in `lib/`**. First-run users never see it; the production first-run
  path is the 4-tap manual profile creation in Flow 1.
  (FIXED in `4b1ce93`: the wizard is complete and coherent, so it was WIRED as
  the first-run gate via `showFirstRunSetupIfNeeded()` when no profile exists —
  not deleted.)
- **B4 — “Export” is a clipboard stub.** `_exportScript`
  (`scripts_screen.dart:709`) copies the bundle to the clipboard with the comment
  “For now, just copy the source code to clipboard // In a real implementation,
  you might want to export as a file.” It is exposed in the UI as “Copy Source”
  (context menu `scripts_screen.dart:1139`, overflow menu `:1329`) — functional
  but mislabeled (the action is a clipboard copy, not an export).
  (FIXED in `1660033`: real file export isn’t trivially available (no
  share_plus/file_picker dep), so the action was made self-consistent — renamed
  `_exportScript`→`_copyScriptSource`, action id `export`→`copy_source`, stub
  comment dropped, behavior extracted to a unit-tested
  `copyScriptSourceToClipboard()`.)
- **B5 — Publish dialog performs no bundle-sandbox validation.**
  `QuickUploadDialog._uploadScript` (`quick_upload_dialog.dart:176`) validates
  form fields only; it signs and uploads the bundle without calling
  `ScriptValidationService`. An invalid/escaping bundle can be published (caught
  only later at execution by the Rust sandbox).
  (FIXED in `5e5a7a6`: `_uploadScript` now runs the authoritative
  `ScriptValidationService` over the bundle before signing; invalid bundles are
  refused with a dedicated, selectable error panel showing the specific rejected
  primitive.)

---

## 5. Prioritized Summary Table

| # | Flow | Current taps | Proposed taps | Confidence | Top lever |
|---|------|--------------|---------------|------------|-----------|
| 1 | Onboarding → first profile | 4 (+1 entry), no guidance | **2** (+1 entry) | 9/10 | Wire `UnifiedSetupWizard` as first-run gate (1.1) + fix dead-end (1.2) |
| 2 | Browse → download → run | 2 (fast) / **4** (dialog) | **2**, no dialog | 9/10 | “Run” SnackBarAction after download (2.1); tap-row=download (2.2) |
| 3 | Author → validate → publish | 4 (+authoring) | **3** (+authoring) | 8/10 | “Create & Publish” chain (3.1); **add validation gate (3.2)** |
| 4 | Run → interact → `icp_call` | 2 first / **1** after allow | **1** (unchanged) | 9/10 | Already meets target after “Always allow” |
| 5 | Profile / keypair mgmt | switch **3**; add key ~4 | switch **2**; add ~3 | 9/10 | Inline profile list (5.1) |
| 6 | Passkey setup | N/A — env-blocked on Linux | N/A | 10/10 (block) | Fix stale `chrome` instructions (6.1); real review needs macOS/Win/Android |

> **Remediation status (2026-07-01):** bugs B1, B2, B3, B4, B5 are all fixed
> (see §4 for commit hashes). That covers proposals 1.1 (wizard first-run gate),
> 1.2 (first-run dead-end), 3.2 (publish validation gate), and 6.1 (stale
> `chrome` instructions). The remaining click-reduction proposals (2.1/2.2/3.1,
> 5.x) are deferred — they are UX polish, not the bugs in scope.

### Top 5 highest-impact reduction proposals
1. **(1.1)** Wire the orphaned `UnifiedSetupWizard` as the first-run gate — collapses onboarding from 4 taps / no guidance to 2 taps / guided. **Impact HIGH, Effort Low.**
2. **(3.2)** Add a `ScriptValidationService` gate to the publish dialog — not a click saving but closes a real safety hole (invalid bundles can be published today). **Impact HIGH (correctness), Effort Low.**
3. **(1.2 + B1)** Fix the silent first-run “My Account” no-op — redirect to profile creation. **Impact HIGH, Effort Low.**
4. **(2.1)** Add a “Run” `SnackBarAction` to the post-download SnackBar (and/or auto-open the run sheet) — cuts the common download→run path from 4 taps to 2. **Impact HIGH, Effort Low.**
5. **(6.1 + B2)** Remove/fix the stale `flutter run -d chrome` instructions across 3 surfaces — stops sending users down a broken path. **Impact HIGH (correctness), Effort Low.**

---

## 6. Environment Note (passkey flow, R-1 / AGENTS.md)

Per `AGENTS.md` “Passkey Testing on Linux” and `PROD_READINESS_PLAN` R-1, the
passkey authenticator cannot be exercised on a Linux desktop box: the `passkeys`
package reports `PasskeyPlatform.isSupported == false`, and the would-be supported
target (Flutter Web) is **unbuildable** because of the unconditional `dart:ffi`
import. A genuine passkey review (registration, login, hybrid QR, vault-password
setup in `vault_password_setup_screen.dart` / `vault_unlock_screen.dart`, recovery
codes in `recovery_codes_screen.dart`) must happen on **macOS / Windows / Android**
or after R-1 restores the Web target. This review therefore documents only the
**graceful-degradation** behavior of the unsupported surfaces (Flow 6) plus the
correctness bug that those surfaces advertise the broken `flutter run -d chrome`
command (B2).
