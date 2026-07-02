# UI Excellence Plan — New/Returning-User Simplicity

- **Status:** PLANNING deliverable (no application code changed). Seeds from
  `docs/specs/UX_REVIEW_FINDINGS.md` (proposals 1.3, 2.1, 2.2, 2.3, 3.1, 3.3,
  4.1, 4.2, 5.1, 5.2, 5.3, 6.2) plus a radical IA review and the unfinished
  TD-4 split.
- **Date:** 2026-07-01
- **Target:** Linux desktop (`flutter run -d linux`); Android parity where
  noted. Flutter Web remains **deferred (R-1)** — see Architectural Issues.
- **Goal (user):** "A simple and obvious to use and fully functional UI for both
  new and returning users." Radically improve DRY/KISS/YAGNI, cut clicks on the
  common operations, and make keyboard use **discoverable**. Greenfield: no
  backward-compat, no legacy, **one constant value in ONE place only**.

---

## 0. Grounding summary (what changed since the UX review)

`UX_REVIEW_FINDINGS.md` bugs **B1–B5 are all FIXED** (commit hashes in §4 of
that doc). Re-validation of each deferred proposal against current code:

| Proposal | Status after re-validation | Evidence |
|----------|---------------------------|----------|
| **1.1** wire `UnifiedSetupWizard` as first-run gate | **DONE (B3)** | `main.dart:453–470` `showFirstRunSetupIfNeeded()` pushes the wizard when `profiles.isEmpty`; `main.dart:306` calls it from `_checkAndShowOnboarding`. |
| **1.2** first-run dead-end "My Account" no-op | **DONE (B1)** | `profile_menu.dart:226–249` `_buildMyAccountTile` always renders; `:273–281` `_handleAction(createAccount)` routes to profile creation/selection instead of no-op. |
| **1.3** profile CTA in Scripts empty state | **STILL APPLICABLE** | Wizard is dismissable (`unified_setup_wizard.dart:85` close → `Navigator.pop` with **no result**). A user who closes it lands on the generic empty state (`scripts_screen.dart:892–900`) whose CTAs presuppose a keypair. |
| **2.1** "Run" `SnackBarAction` after download | **STILL APPLICABLE** | Download SnackBar at `scripts_screen.dart:419–436` has **no action**; `createdScript` (`:386`) is in scope and is exactly the `ScriptRecord` `_runScript` (`:469`) needs. |
| **2.2** single-tap = download | **OPTIONAL / LOW-ROI (see WU-2)** | `_handleAllScriptsItemTap` (`scripts_screen.dart:1527–1537`): local→run, marketplace→details. Changing tap semantics risks accidental downloads; WU-2 prefers 2.1. |
| **2.3** inline description/source badge | **PARTLY DONE** | `_buildItemSubtitle` (`scripts_screen.dart:1003`) + `source_badge_test.dart` exist. Residual is LOW-ROI cosmetic. Folded into WU-7. |
| **3.1** "Create & Publish" chain | **STILL APPLICABLE** | `script_creation_screen.dart` "Create Script" button returns to list; publish requires locating the new item. |
| **3.2** publish validation gate | **DONE (B5)** | `quick_upload_dialog.dart:210–213` now calls `ScriptValidationService().validateScript(bundle)` before signing. **Will NOT redo.** |
| **3.3** "Share" `SnackBarAction` after create | **STILL APPLICABLE** | Create SnackBar at `scripts_screen.dart:551–571` has no action; `rec` (`:542`) is the `ScriptRecord` `_publishToMarketplace` (`:580`) needs. |
| **4.1** collapse permission dialog 3→2 buttons | **LOW-ROI (see WU-5)** | `script_app_host.dart:442–453` three buttons (`Deny`/`allowOnce`/`allowAlways`). Honest eval in WU-5: recommend AGAINST. |
| **4.2** persist "Always allow" across restarts | **DEFERRED** | `script_app_host.dart` `_sessionAllow` is session-only. Med effort; not blocking. Out of scope unless profile-permissions feature is wanted. |
| **5.1** inline profile list in menu | **STILL APPLICABLE** | `profile_menu.dart:207–214` "Switch Profile" tile → `_showManageProfilesSheet` (`:349`) → tap profile (`:554–567`) = 3 taps. |
| **5.2** active-profile fast-switch in header | **STILL APPLICABLE** | `_buildProfileHeader` (`:108–196`) is non-interactive display only. |
| **5.3** quick "Add key" in menu | **OPTIONAL** | `account_profile_screen.dart` Add-Key FAB already exists. Skipped as low-ROI (YAGNI). |
| **6.2** copy-to-clipboard affordance | **DONE-ISH (B2)** | Passkey surfaces no longer advertise the broken `chrome` command (B2 fix). Residual clipboard stub is passkey-platform-blocked; out of scope on Linux. |

**Net:** the live WUs are **1.3, 2.1, 3.1, 3.3, 5.1, 5.2** plus a new
**keyboard-discoverability** WU, a **radical-IA** WU, the **TD-4 finish**, and a
**DRY/constants** track.

---

## 0b. Round-2 EMPIRICAL stabilization WUs (PRIORITY — do BEFORE click-reduction)

The empirical UX review (`docs/specs/UX_REVIEW_ROUND2.md`, run on the live app
under Xvfb) confirmed every WU-1..7 hypothesis **and** surfaced four real
runtime bugs. The first three are **functional blockers** — a broken app has no
UX, so these ship first. Evidence: `docs/specs/ux_screenshots/round2/`.

### WU-S1 — Fix the backend-wiring key mismatch (NEW-1)
- **Bug:** `apps/autorun_flutter/lib/config/app_config.dart:6` reads
  `String.fromEnvironment('PUBLIC_API_ENDPOINT', …)`, but `justfile:393`
  (`flutter-dev-local`) launches with `--dart-define=API_ENDPOINT=…` — a
  **different key**. Result: `just flutter-dev-local` silently points the app at
  **production** (`icp-mp.kalaj.org`), not the local backend. The prebuilt bundle
  has the prod URL baked in too.
- **Fix:** change the justfile recipe(s) to `--dart-define=PUBLIC_API_ENDPOINT=…`
  (the key the app actually reads). Audit all `--dart-define=` sites in the
  justfile for the same class of mismatch. Single source of truth: the env-var
  name is defined by `app_config.dart` — reference it symbolically everywhere.
- **Acceptance:** `just api-dev-up` + the run recipe hits localhost (verify via
  the app's `AppConfig.debugPrintConfig()` log → "Local Development"); a test
  asserts `API_ENDPOINT` is no longer referenced as a dart-define.

### WU-S2 — Secure-storage readiness + human errors (NEW-2 + NEW-4)  [SEVERE]
- **Bug:** `unified_setup_wizard.dart:582` `_finish` → `createProfile` →
  `FlutterSecureStorage.write` THROWS `PlatformException(Libsecret error, Failed
  to unlock the keyring)` on a Linux box without a running Secret Service
  (no `gnome-keyring-daemon`/`kwallet`, `DBUS_SESSION_BUS_ADDRESS` unset). The
  wizard catches it (`:580/:612`) but (a) **`profiles.json` stays empty** → the
  wizard can **never complete** → cascades into ALL identity flows
  (share/publish/passkey/multi-profile); and (b) the raw `PlatformException(…)`
  string is shown to the user (`:300/:613`) — NEW-4.
- **Fix (fail-loud + automate, per AGENTS.md):**
  1. New `SecureStorageReadiness` service: probe whether `FlutterSecureStorage`
     can read/write (or detect a Secret Service via D-Bus). Expose
     `Future<StorageReadiness>` → `{ok | unavailable(reason, fixHint)}`.
  2. On `unavailable`, the wizard/first-run shows a **blocking, actionable**
     panel — NOT a raw exception: "Secure key storage is unavailable. On Linux,
     install gnome-keyring (or KWallet) and ensure it's running." with a
     **copyable install command** and a **Retry** button. (Matches AGENTS.md
     "be LOUD about misconfigurations" + "AUTOMATE EVERYTHING".)
  3. **Automate where possible:** if `gnome-keyring-daemon` is installed but not
     running, attempt to start it (D-Bus session + `--start --components=secrets`)
     and unlock; if that succeeds, proceed transparently.
  4. Do NOT add an insecure plaintext file fallback (would violate the
     zero-knowledge secure-storage model). The honest path is "install a Secret
     Service". Document the Linux requirement in `AGENTS.md` + `README.md`.
- **Acceptance:** on a keyring-less box the wizard shows the actionable panel
  (no raw exception, no silent swallow); with a keyring running, profile
  creation succeeds and `profiles.json` is written. Unit-test both readiness
  outcomes; widget-test the panel + retry.

### WU-S3 — Fix `code_text_field` `TextSpan` ArgumentError (NEW-3)
- **Bug:** the `CodeField` widget (`code_text_field`) throws
  `ArgumentError building a TextSpan` whenever the Scripts screen renders
  content — destabilizes frames (Flutter recovers sibling widgets).
- **Fix:** locate the malformed `TextSpan` construction (likely a null/non-String
  span child or invalid `style`), make it robust. Add a widget test that renders
  `CodeField` with non-empty content without throwing.
- **Acceptance:** Scripts screen renders content with no `ArgumentError` in the
  log; new focused widget test passes.

**Sequencing note:** WU-S1/S2/S3 are independent of WU-8 and each other (justfile
/ wizard+new service / code_text_field widget) — they run in the FIRST parallel
wave alongside WU-8 (foundation) and WU-4 (profile switch). WU-1 (empty-state)
moves to AFTER WU-8 (it touches the file WU-8 extracts).

---

## 1. Architectural issues REQUIRING a human decision (per AGENTS.md)

These are **flagged, not silently decided.** Each blocks or shapes a WU.

> **ORCHESTRATOR DECISIONS (recorded 2026-07-01, unblocking all tracks):**
> - **A-1 → RESOLVED: take the KISS floor.** Relabel the 2nd tab "Explore" →
>   **"Canisters"** (honest label, zero behavior change, removes the
>   expectation mismatch — the single biggest confusion for new users). The
>   paradigm shift of *promoting marketplace to its own tab* (option b) is
>   **deferred**: it restructures `ScriptsScreen` (high regression risk) and is
>   YAGNI until marketplace content volume warrants it. The empirical UX review
>   (Wave 1) will photograph + assess the Canisters tab to inform any future
>   IA move. **WU-7 is UNBLOCKED with the relabel scope.**
> - **A-2 → RESOLVED: keep Flutter Web deferred.** Reversing R-1 is a separate
>   multi-day initiative (conditional `*_io.dart`/`*_web.dart` split + WASM
>   QuickJS + WebCrypto). Desktop + Android remain the shipped, fully-functional
>   targets; Linux-desktop passkeys degrade gracefully (correct). No WU assumes
>   Web. Recorded in `docs/BROWSER_SUPPORT.md`.
> - **A-3 → RESOLVED: defer the model fix (documented debt), defend in the UI.**
>   WU-4's switcher MUST surface only the active profile's *own* keypairs (no
>   cross-profile bleed). The `account.dart` model tightening stays a tracked
>   architectural item; not half-fixed here.

### A-1 — "Explore" tab is a canister-call dev tool, not marketplace explore
- **Finding:** the second nav tab "Explore" (`main.dart:439–443`, label "Explore",
  icon `dns`) renders `BookmarksScreen` — the app's **largest screen at 1,865
  lines** — which is a **canister-call builder**: `_openInlineClient`
  (`bookmarks_screen.dart:52`), `CanisterClientSheet`, `popularCanisters`,
  `BookmarksService`, Candid arg builders. Marketplace browse already lives
  **inside** `ScriptsScreen` (unified local+marketplace list,
  `scripts_screen.dart:908–940`). So the 2nd-most-prominent nav slot is a niche
  power-user tool, while a "simple and obvious" app's second tab should be the
  social/discovery surface.
- **Decision needed:** (a) relabel "Explore"→"Canisters" and keep it (honest IA,
  no behavior change); (b) **promote marketplace/social to the 2nd tab** and
  demote the canister client to a profile/settings entry (radical simplification,
  WU-7's preferred path); or (c) collapse to a **single "Scripts" tab** and move
  canister-client behind the profile menu (most KISS, most disruptive).
- **Owner of decision:** human. WU-7 is written for option (b) but is **blocked**
  until this is chosen.

### A-2 — Is Flutter Web a supported target? (R-1)
- The Web build is **unbuildable** (`lib/main.dart:11` and
  `lib/rust/native_bridge.dart:2` import `dart:ffi` unconditionally; `TODO.md`
  HIGH-severity). Web is the route AGENTS.md specifies for passkey enrollment.
  "Fully functional" arguably requires Web for the passkey/vault UX (recovery
  codes, vault password) on a Linux dev box. R-1 needs a conditional-import
  split (`*_io.dart` FFI + `*_web.dart` stub) + WASM QuickJS + WebCrypto.
- **Decision needed:** fund R-1, or formally drop Web and accept macOS/Windows/
  Android as the only passkey-capable targets.
- **Impact on this plan:** none of WU-1..WU-9 assume Web. But "fully functional
  UI" is only *fully* true on non-Linux-desktop until A-2 is resolved.

### A-3 — Cross-profile key sharing allowed by client models (R-2)
- `lib/models/account.dart` (`FIXME` L18, L304; `TODO.md` MEDIUM) allows a keypair
  to belong to multiple profiles; the backend enforces uniqueness. This violates
  the profile-centric model and **undermines WU-4's profile-switch UX** (a
  keypair appearing under two profiles is confusing in a fast-switcher).
- **Decision needed:** tighten the client model to forbid cross-profile key
  sharing (correct, may surface latent bad data) or leave as documented debt.
- **Impact:** WU-4 proceeds regardless, but the fast-switcher must surface the
  active profile's *own* keypairs only.

---

## 2. Work Units

> Conventions: every WU follows the **PoC-first** workflow (AGENTS.md §"Mandatory
> Workflow"): build the smallest demonstrable change → prove it → write the
> failing test → then productionize. One commit per WU. Every commit leaves
> `flutter analyze` clean and the cited `just test-feature`/`flutter test` green.

---

### WU-1 — Profile-aware empty state & wizard-dismiss safety
- **User problem:** A new user who **dismisses** the first-run wizard (close
  button, `unified_setup_wizard.dart:85`) lands on the Scripts empty state
  (`scripts_screen.dart:892–900`) whose "Create Script" CTA presupposes a
  keypair that doesn't exist → dead-end, violates fail-loud.
- **Grounding:**
  - `apps/autorun_flutter/lib/screens/scripts_screen.dart:892–900` (`ModernEmptyState`
    generic CTAs: "Create Script" / "Browse Marketplace").
  - `apps/autorun_flutter/lib/screens/scripts_screen.dart:864` `hasNoContent`
    branch (only entered when both local + marketplace empty; for a returning
    user with content this path is skipped — correct).
  - `apps/autorun_flutter/lib/main.dart:453–470` `showFirstRunSetupIfNeeded`.
  - `apps/autorun_flutter/lib/screens/unified_setup_wizard.dart:85` dismiss path.
- **Concrete change:**
  1. In the empty-state builder, branch on `ProfileScope.of(context).activeProfile`:
     if **null**, render a `ModernEmptyState` titled "Set up your profile" with a
     single primary CTA **"Get Started"** → re-invoke
     `showFirstRunSetupIfNeeded(...)` (or push `UnifiedSetupWizard` directly).
     Drop the "Create Script"/"Browse Marketplace" CTAs in this branch (they
     require a keypair).
  2. Gate `_showCreateSheet` (`scripts_screen.dart:540`) and
     `_downloadScript` (`:356`) entry points: if `activeProfile == null`, route
     to the wizard instead. (One shared guard fn `_ensureProfileOrPrompt()`
     → reused by WU-3.)
- **Dependencies:** ideally after **WU-8** (extracts `_buildEmptyState` to its
  own file, reducing merge churn). Can proceed before if WU-8 deferred.
- **Risk:** LOW. Behavior change is additive (new branch for the no-profile
  case); existing with-profile path unchanged.
- **Commit:** `feat(ux): WU-1 profile-aware empty state + dismiss-safety`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter test test/features/onboarding/first_run_setup_gate_test.dart test/features/scripts/empty_state_secondary_action_test.dart test/features/scripts/new_user_default_view_test.dart`
  - `just test-feature onboarding` green.
  - New test: dismiss wizard → empty state shows "Set up your profile" (not
    "Create Script"); tapping it re-opens the wizard.

---

### WU-2 — "Run" SnackBarAction after download (+ optional tap=download)
- **User problem:** Download path is **4 taps** (details dialog → Download →
  close dialog → locate local row → run). The post-download SnackBar
  ("…added to your library!", `scripts_screen.dart:419`) carries **no action**.
- **Grounding:**
  - `apps/autorun_flutter/lib/screens/scripts_screen.dart:419–436` (download
    SnackBar, no `action`).
  - `scripts_screen.dart:386` `createdScript` — the `ScriptRecord` in scope.
  - `scripts_screen.dart:469` `_runScript(ScriptRecord)` — exactly the target.
  - `scripts_screen.dart:1527–1537` `_handleAllScriptsItemTap` (tap semantics).
- **Concrete change:**
  1. Add `action: SnackBarAction(label: 'Run', onPressed: () => _runScript(createdScript))`
     to the download SnackBar (`:419`). This alone collapses the dialog path
     **4 → 2 taps** (Download icon → Run action). **This is the HIGH-ROI win.**
  2. (Optional, **2.2**, lower ROI) Make single-tap on a marketplace row open
     details **only if not already downloaded**; if already downloaded, tap →
     run. Do **not** make tap=download unconditionally (accidental-download
     risk; the hover-reveal Download icon already exists at `:1053`/`:1396`).
- **Dependencies:** none (localized SnackBar edit). Conflicts only trivially
  with WU-8 (same file, different function).
- **Risk:** LOW for (1). MED for (2) — changes learned tap semantics; gate
  behind `one_tap_execution_test.dart` and `discoverable_actions_test.dart`.
- **Commit:** `feat(ux): WU-2 Run action on post-download snackbar`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter test test/features/scripts/one_tap_execution_test.dart test/features/scripts/discoverable_actions_test.dart test/features/scripts/script_menu_test.dart`
  - `just test-feature scripts` green.
  - New/updated test: after download, the SnackBar exposes a "Run" action that
    invokes `_runScript` with the created record.

---

### WU-3 — "Create & Publish" chain + "Share" SnackBarAction
- **User problem:** After authoring, the user returns to the **list** and must
  visually re-locate the new script to reach "Share" (publish). Two round-trips.
- **Grounding:**
  - `apps/autorun_flutter/lib/screens/script_creation_screen.dart` "Create
    Script" button (≈ `:510`, per UX review; **executor must confirm current
    line** — `rg -n "Create Script" apps/autorun_flutter/lib/screens/script_creation_screen.dart`).
  - `apps/autorun_flutter/lib/screens/scripts_screen.dart:540–573`
    `_showCreateSheet` (pushes `ScriptCreationScreen`, returns `ScriptRecord? rec`).
  - `scripts_screen.dart:551–571` create-success SnackBar (no action).
  - `scripts_screen.dart:580` `_publishToMarketplace(ScriptRecord)` — target.
  - `apps/autorun_flutter/lib/widgets/quick_upload_dialog.dart:213` — B5
    validation gate **already present**; do **not** re-add.
- **Concrete change:**
  1. Add a second primary action **"Create & Publish"** to `ScriptCreationScreen`
     that, on successful create, returns a richer result (e.g.
     `(ScriptRecord, bool wantsPublish)`) so `_showCreateSheet` can chain
     straight into `_publishToMarketplace(rec)`. Collapses author→publish from
     **4 → 3 taps** and removes the list round-trip.
  2. Independently (smaller, do even if (1) is deferred): add
     `action: SnackBarAction(label: 'Share', onPressed: () => _publishToMarketplace(rec))`
     to the create-success SnackBar (`:551`). 1-tap shortcut to publish.
  3. Reuse WU-1's `_ensureProfileOrPrompt()` guard so "Create & Publish" with no
     profile routes to the wizard, not a silent no-op.
- **Dependencies:** WU-1 (shares the profile guard). Independent of WU-8.
- **Risk:** MED. (1) changes the create-screen result contract — extend, don't
  break, the existing `ScriptRecord?` return (keep the plain "Create Script"
  button returning `ScriptRecord?` unchanged). B5 validation still gates publish.
- **Commit:** `feat(ux): WU-3 Create & Publish chain + Share snackbar action`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter test test/features/scripts/publish_button_test.dart test/features/scripts/publish_account_prompt_test.dart test/features/scripts/ts_validation_negative_test.dart`
  - `just test-feature scripts` green.
  - Test: "Create & Publish" chains to `QuickUploadDialog` without returning to
  the list; B5 validation still refuses an escaping bundle.

---

### WU-4 — Inline profile switch (3 → 2 taps)
- **User problem:** Switching the active profile is **3 taps** (avatar →
  "Switch Profile" tile → `_ManageProfilesSheet` → tap profile).
- **Grounding:**
  - `apps/autorun_flutter/lib/widgets/profile_menu.dart:108–196`
    `_buildProfileHeader` (non-interactive).
  - `profile_menu.dart:198–224` `_buildMenuItems` — renders the "Switch Profile"
    `_MenuTile` at `:207–214`.
  - `profile_menu.dart:349–367` `_showManageProfilesSheet`.
  - `profile_menu.dart:465–571` `_ManageProfilesSheet` (the inline-able list,
    `setActiveProfile` at `:558`).
- **Concrete change (5.1 + 5.2):**
  1. **(5.1)** When `profileController.profiles.length > 1`, render the profile
     `ListView` **directly inside the menu** (reusing `_ManageProfilesSheet`'s
     row builder) and drop the intermediary "Switch Profile" tile in that case.
     When only one profile exists, keep a single "Manage profiles" entry that
     opens the full sheet.
  2. **(5.2)** Make `_buildProfileHeader` tappable → opens the (now-direct)
     switch list. Avatar → profile = **2 taps**.
  3. Keep "Create New Profile" as the trailing row of the inline list (no extra
     sheet hop). Respect A-3: show only the active profile's own keypairs in any
     key surface (no cross-profile bleed).
- **Dependencies:** none (isolated to `profile_menu.dart`). Independent of WU-8.
- **Risk:** LOW–MED. The menu sheet must stay scrollable when many profiles;
  `isScrollControlled: true` already set (`main.dart:328`).
- **Commit:** `feat(ux): WU-4 inline profile switch + header fast-switch`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter test test/features/profile/manage_test.dart test/features/profile/screens`
  - `just test-feature profile` green.
  - New test: with ≥2 profiles, opening the menu shows the list directly; tapping
  a non-active profile switches (1 tap after open); header tap opens the same.

---

### WU-5 — icp_call permission dialog: **recommend NO CHANGE** (documented)
- **User problem (claimed):** 3-button permission dialog is "slightly heavy".
- **Grounding:** `apps/autorun_flutter/lib/widgets/script_app_host.dart:430–458`
  `_showPermissionDialog` — `Deny` / `allowOnce` (`:446`) / `allowAlways`
  (`:449`, `FilledButton` default). Session memory at `_sessionAllow`.
- **Honest evaluation:** **DROP proposal 4.1.** Rationale:
  - The first-call cost is already **2 taps** and **1 tap thereafter** for the
    session (UX review Flow 4 — "already meets target").
  - "Allow once" is genuinely useful for a cautious user trying an untrusted
    script's canister call once. Removing it **reduces safety clarity** with
    zero click-count benefit on the common path — directly contradicting the
    "only if it doesn't reduce safety clarity" guard in the brief.
  - "Always allow" is already the visual default (`FilledButton`).
- **Concrete change:** none. Optionally (cheap): make the dialog's three buttons
  visually clearer via `AppDesignSystem` button styles — but this is cosmetic
  and YAGNI. **Recommend DEFER.**
- **Dependencies:** none.
- **Risk:** N/A (no change).
- **Commit (if the cosmetic tweak is wanted):** `style(ux): WU-5 clarify permission dialog button hierarchy`
- **Acceptance:** `flutter test test/features/scripts/script_bottom_sheet_test.dart` (unchanged).

---

### WU-6 — Keyboard shortcuts audit + discoverable "?" help overlay
- **User problem:** Shortcuts exist but are **not discoverable** ("clearly
  indicated" is an explicit user requirement). `getShortcutLabel` and
  `ShortcutTooltip` exist but are barely wired; there is no help overlay.
- **Grounding:**
  - `apps/autorun_flutter/lib/widgets/keyboard_shortcuts.dart:5–88`
    `DesktopShortcuts` — binds `Cmd/Ctrl+N` (new), `Cmd/Ctrl+F` (search), `R`
    (refresh), `Cmd/Ctrl+1/2/3` (tabs). **`Cmd/Ctrl+3` is bound but there is no
    3rd tab** (`main.dart:433–444` has 2 items) — dead binding.
  - `keyboard_shortcuts.dart:28–50` `getShortcutLabel` — the single source of
    shortcut labels (good — reuse it).
  - `keyboard_shortcuts.dart:207–225` `ShortcutTooltip` — exists, underused.
  - `main.dart:354–359` `DesktopShortcuts(... )` + `EscapeHandler`.
  - No `Profile`/`?`/`Cmd+K`/`Esc`-to-close-menu shortcuts are bound.
- **Concrete change:**
  1. **Audit & fix:** remove the dead `Cmd/Ctrl+3` binding (or repurpose once
     WU-7/A-1 settles the tab count). Add intuitive shortcuts: **`?` → help
     overlay**, **`Cmd/Ctrl+,` → profile menu** (matches desktop convention for
     "settings"), **`Esc` → close topmost sheet/dialog** (extend
     `EscapeHandler`, currently only `maybePop` at `main.dart:271`).
  2. **Discoverability — "?" help overlay:** a new lightweight
     `ShortcutsHelpSheet` widget listing every binding (sourced from a single
     `const` map so the overlay and `getShortcutLabel` share ONE definition —
     satisfies the single-source rule). Triggered by `?` and by a small
     "⌘?" affordance in the profile menu / app bar.
  3. Surface shortcut hints on the key FABs/tiles via `ShortcutTooltip` (New
     Script FAB `scripts_screen.dart:806`, Search field `:1744`, tab bar
     `main.dart:426`).
- **Dependencies:** ideally after **WU-7** (so the tab count / `Cmd+1/2` mapping
  is final). Independent of WU-8.
- **Risk:** LOW. Purely additive overlay + tooltip hints.
- **Commit:** `feat(ux): WU-6 keyboard help overlay + shortcut audit`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter test test/features/navigation/navigation_test.dart`
  - `just test-feature navigation` green.
  - New widget test: pressing `?` opens `ShortcutsHelpSheet`; the listed bindings
  match the `DesktopShortcuts` map (single source — assert they're the same
  const).

---

### WU-7 — Visual consistency / IA: fix the "Explore" tab (BLOCKED on A-1)
- **User problem:** The 2nd nav tab is a 1,865-line canister-call dev tool
  (`BookmarksScreen`) occupying prime nav real estate, while marketplace/social
  discovery is buried *inside* the Scripts list. For a "simple and obvious" app
  this is the single biggest IA defect.
- **Grounding:**
  - `apps/autorun_flutter/lib/main.dart:394–400` `IndexedStack` (2 children:
    `ScriptsScreen`, `BookmarksScreen`).
  - `main.dart:426–446` `_buildModernNavigationBar` — labels "Scripts"/"Explore".
  - `apps/autorun_flutter/lib/screens/bookmarks_screen.dart:1–68` — confirm it's
    a canister client (`_openInlineClient`, `CanisterClientSheet`,
    `popularCanisters`); **1,865 lines** (largest screen in the app).
  - `scripts_screen.dart:908–940` — marketplace browse already inside Scripts.
- **Preferred change (option (b), pending A-1 approval):**
  1. Relabel tab[1] to reflect its true function (e.g. **"Canisters"**, icon
     `dns`), OR — preferred — **promote marketplace discovery to tab[1]** and
     move the canister client to a profile-menu entry ("Canister client"/
     "Developer tools").
  2. Whichever option is chosen: update `_buildModernNavigationBar`, the
     `IndexedStack`, the `_handleNavigateToTab` guard (`main.dart:265–269`
     hard-codes `index < 2`), and the `Cmd+1/2` bindings (WU-6).
  3. **Opinionated minimum (if A-1 defers):** at minimum **rename "Explore" →
     "Canisters"** so the label is honest — zero behavior change, removes the
     expectation mismatch. This is the KISS floor.
- **Dependencies:** **BLOCKED on architectural decision A-1.** Coordinate with
  WU-6 (tab shortcuts) and WU-8 (both touch the most-used screen region).
- **Risk:** MED (option b) — moves a 1,865-line screen's entry point; needs
  navigation tests updated. LOW (minimum relabel).
- **Commit:** `feat(ux): WU-7 honest IA — relabel/relocate Explore tab` (or
  `refactor(nav): WU-7 ...` for option b).
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter test test/features/navigation/navigation_test.dart test/features/scripts/navigation_test.dart`
  - `just test-feature navigation` green.
  - Manual: launch `-d linux`; the 2nd tab's label truthfully describes its
  content; canister client is reachable (wherever it now lives).

---

### WU-8 — Finish TD-4: extract `ScriptsScreenState` `_build*` view-builders
- **User problem (maintainability blocker):** `scripts_screen.dart` is **2,032
  lines** with a god-object `ScriptsScreenState` holding ~12 `_build*`/`_show*`
  view-builders. Every UI WU (1, 2, 3) touches this file → merge churn and
  regression risk. Unblocks clean UI work.
- **Grounding:**
  - `apps/autorun_flutter/lib/screens/scripts_screen.dart` (2,032 lines; was
    2,702 — TD-4 *partially* done per `PROD_READINESS_PLAN.md` §"TD-4 status
    (PARTIAL)" L809–816: the 4 sibling dialogs were extracted; the
    `_build*` view-builders were **deferred** as too invasive).
  - `apps/autorun_flutter/lib/screens/scripts_screen_state.dart` — the
    `ScriptsViewMachine` state object is **already extracted** (good template;
    follow its pattern).
  - View-builders to extract (confirmed via `rg`): `_buildEmptyState` cluster
    (`scripts_screen.dart:866–922`), `_buildUnifiedListContent` (`:924–940`),
    `_buildAllScriptsListItem` (`:942–1020`), `_showScriptContextMenu`
    (`:1022–1062`), `_buildLocalScriptMenu` (`:1238–`), `_buildMarketplaceScriptMenu`
    (`:1385–`), `_buildFavoriteStarButton`, `_buildItemSubtitle` (`:1003`),
    `_buildSearchBar` (`:1744` region).
- **Concrete change (pure MOVE, no logic change — per the TD-4 rule):**
  1. `NEW lib/widgets/scripts_list_item_tile.dart` ← `_buildAllScriptsListItem`
     + `_buildItemSubtitle` + `_buildSourceIcon` + `_buildFavoriteStarButton`
     (a stateless tile taking the `ScriptListItem` + a small callback bundle).
  2. `NEW lib/widgets/script_row_menus.dart` ← `_buildLocalScriptMenu` +
     `_buildMarketplaceScriptMenu` + `_showScriptContextMenu` (take callbacks:
     `onRun`, `onEdit`, `onPublish`, `onDownload`, `onViewDetails`, etc.).
  3. `NEW lib/widgets/scripts_empty_state.dart` ← the empty-state branch
     (`:866–922`). **(WU-1 then adds the profile-aware branch here.)**
  4. `NEW lib/widgets/scripts_search_bar.dart` ← the search-bar cluster.
  5. `scripts_screen.dart`: shrink to `ScriptsScreen` + `ScriptsScreenState`
     (data-loading, action handlers, SnackBars) + list composition. Target
     **≤ ~1,100 lines**.
  - Pass `ScriptRecord`/`MarketplaceScript` + callbacks; introduce a small
    `_ScriptsScreenActions` value object only if a tile genuinely needs >5
    callbacks (avoid passing the whole State).
- **Dependencies:** none. **Land FIRST** (Track A) so WU-1/WU-2/WU-3 rebase onto
  smaller files.
- **Risk:** MED–HIGH (high-churn move of the most-used screen). Mitigation: one
  commit per extracted file; pure move (no rename, no logic); strong existing
  test coverage gates it (`just test-feature scripts`, plus
  `scripts_view_machine_test.dart`, `script_list_visual_hierarchy_test.dart`,
  `section_separation_test.dart`, `simplified_actions_test.dart`).
- **Commit:** `refactor(scripts): WU-8 finish TD-4 — extract view-builders` (one
  commit per extracted file: `... scripts_list_item_tile`, `... script_row_menus`,
  `... scripts_empty_state`, `... scripts_search_bar`).
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter analyze` clean.
  - `cd apps/autorun_flutter && flutter test test/features/scripts --timeout=240s`
  - `just test-feature scripts` green.
  - `wc -l apps/autorun_flutter/lib/screens/scripts_screen.dart` ≤ ~1,100.
  - Manual (Linux desktop): list renders, long-press context menu, filter, edit,
  run — all unchanged.

---

### WU-9 — DRY / single-source constants (tech-debt, cross-cutting)
- **User problem (maintainability + the explicit "one constant in ONE place"
  rule):** magic numbers and identical UI fragments are duplicated across the
  lib, so a restyle touches many files and the "greenfield, no legacy" bar slips.
- **Grounding (measured counts in `apps/autorun_flutter/lib`):**
  - Sheet radius `BorderRadius.vertical(top: Radius.circular(20))` — **7 sites**
    (e.g. `main.dart:330`, `scripts_screen.dart:1025`, `profile_menu.dart`,
    `bookmarks_screen.dart:59`).
  - `backgroundColor: Colors.green` / `Colors.green.shade600` success SnackBars
    — **11 sites** (download `:433`, create `:565`, publish `:637`, etc.).
  - `SnackBarAction` used only **once** in the entire lib (post-WU-2/3 it grows;
    centralize a `successSnackBar(content, {action})` helper).
  - `Duration(seconds: N)` ×26 and `Duration(milliseconds: N)` ×27 literals.
- **Concrete change:**
  1. `lib/theme/app_design_system.dart`: add `AppDesignSystem.sheetRadius`
     (`= Radius.circular(20)`), `AppDesignSystem.successSnackBar(...)` factory,
     and `AppDurations` (`short=150ms`, `snackbar=4s`, etc.). Replace the
     duplicated literals with these symbolic names.
  2. Fold the repeated success-SnackBar pattern (icon + green + text) into the
     `successSnackBar` factory; WU-2/WU-3/WU-8 snackbars consume it.
  3. Dead-code sweep: `rg` for orphaned private helpers / unused imports after
     WU-8 lands; remove (AGENTS.md "Zombie Code").
- **Dependencies:** ideally **after WU-8** (so the view-builders are in focused
  files when their literals are swapped). Coordinate with WU-2/WU-3 (they add
  the `SnackBarAction`s that WU-9 centralizes).
- **Risk:** LOW (mechanical replacement), but wide-touch — do per-area commits.
- **Commit:** `refactor(theme): WU-9 single-source design tokens + snackbar factory`
- **Acceptance:**
  - `cd apps/autorun_flutter && flutter analyze` clean.
  - `just test` (full suite) green — this is a cross-cutting change.
  - `rg "Radius.circular\(20\)" apps/autorun_flutter/lib | wc -l` drops sharply
  (only the single token definition remains).

---

## 3. Dependency graph

```
            A-1 (decision) ──────────────┐
                  │                       │
                  ▼                       ▼
               WU-7 (IA)  ──────► WU-6 (shortcuts/help)  ◄── A-2, A-3 (decisions, informational)

  WU-8 (TD-4 split) ──┬──► WU-1 (empty state, profile-aware)
                      ├──► WU-2 (Run snackbar)   [weak: localized]
                      ├──► WU-3 (Create & Publish) ◄── WU-1 (profile guard)
                      └──► WU-9 (constants)        [after, to ease literal sweep]

  WU-4 (inline profile switch) ── (independent; respects A-3)

  WU-5 (permission dialog) ── RECOMMEND DEFER (no change)
```

- **Hard edges:** WU-7 → WU-6 (tab shortcuts must match final tab count);
  WU-3 → WU-1 (shares `_ensureProfileOrPrompt()`); WU-9 → WU-8 (constants sweep
  best after view-builders are extracted).
- **Soft edges (rebase-able conflicts only):** WU-1/WU-2/WU-3 ↔ WU-8 (same file,
  `scripts_screen.dart`).

---

## 4. Parallel build tracks (≈4–5 nearly-independent swarms)

| Track | Owns WUs | Touches (primary files) | Blocks |
|-------|----------|-------------------------|--------|
| **Track A — Foundation** | **WU-8** | `scripts_screen.dart` → 4 new widget files | Land **first**; unblocks B/C clean diffs. |
| **Track B — Scripts core loop** | **WU-2, WU-3** | `scripts_screen.dart` (snackbars), `script_creation_screen.dart` | Rebase onto Track A (weak); WU-3 needs WU-1's guard. |
| **Track C — Onboarding & Profile** | **WU-1, WU-4** | `scripts_screen.dart` empty-state (post-A), `profile_menu.dart` | WU-1 ideally after Track A; WU-4 independent. |
| **Track D — Discoverability & IA** | **WU-6, WU-7** | `keyboard_shortcuts.dart`, new `ShortcutsHelpSheet`, `main.dart` nav | **WU-7 BLOCKED on A-1.** WU-6 after WU-7. |
| **Track E — Cross-cutting DRY** | **WU-9, (WU-5 defer)** | `theme/app_design_system.dart`, wide literal sweep | After Track A (and folded into B/C snackbars). |

**Recommended launch order:**
1. Track A (WU-8) — land first, one commit per extracted file.
2. In parallel: Track C→WU-4, Track B→WU-2, Track E→prep tokens, **and escalate
   A-1 to the human** so Track D's WU-7 can unblock.
3. Once A-1 decided: Track D (WU-7 then WU-6).
4. Track B→WU-3 after WU-1's guard lands; Track E (WU-9) after Track A.

---

## 5. Commit cadence & conventions

- **One commit per WU** (WU-8 and WU-9: one commit *per extracted file / per
  area*). Each commit must leave `flutter analyze` clean and the cited
  `just test-feature`/`flutter test` green (AGENTS.md "Minimal Diff",
  "Post-Change Checklist").
- **Message convention** (matches `PROD_READINESS_PLAN.md` L717 repo history):
  - UI features: `feat(ux): WU-<n> <title>`
  - Refactors: `refactor(<area>): WU-<n> <title>`
  - Tokens/DRY: `refactor(theme): WU-<n> <title>`
  - Doc-only: `docs(ux): <title>`
- **Never** land a UI WU without its gating test (AGENTS.md "Write Failing
  Tests" first). Each WU's Acceptance section names the test file(s).

---

## 6. Definition of Done + acceptance checklist

A WU/track is DONE when **all** of:

- [ ] **User access:** the feature is reachable in the running app (UI/CLI),
  not just backend (`flutter run -d linux`).
- [ ] **PoC demonstrated:** the change was proven end-to-end before
  productionizing (AGENTS.md §3–4).
- [ ] **Tests:** the WU's named `flutter test <path>` and
  `just test-feature <name>` pass; a new test codifies the behavior (positive
  + negative where applicable).
- [ ] **Clean:** `cd apps/autorun_flutter && flutter analyze` is warning-clean.
- [ ] **Minimal diff:** `git diff` shows only necessary changes; no zombie code
  / dead imports / legacy comments.
- [ ] **Single source:** no new magic-number duplicate introduced; new constants
  live in ONE place (`AppDesignSystem` / `AppDurations`) and are referenced by
  symbolic name elsewhere.
- [ ] **Fail-loud:** no `try { … } catch (_) { /* ignore */ }`, no silent
  no-ops, no fallback-to-cache (AGENTS.md "Forbidden Patterns").
- [ ] **Confidence ≥ 8/10** (else STOP and ask).

### Full-gate command set (run before merge of the last WU)
```bash
# Per-feature, during each WU
just test-feature onboarding      # WU-1
just test-feature scripts         # WU-2, WU-3, WU-8
just test-feature profile         # WU-4
just test-feature navigation      # WU-6, WU-7

# Whole-app gate (before final sign-off)
cd apps/autorun_flutter && flutter analyze
just test                         # Rust + Flutter full suite
wc -l apps/autorun_flutter/lib/screens/scripts_screen.dart   # WU-8: ≤ ~1,100
rg "Radius.circular\(20\)" apps/autorun_flutter/lib | wc -l  # WU-9: ~1
```

---

## 7. Risk & ROI honesty

- **Highest ROI / lowest risk:** WU-2 (Run SnackBarAction), WU-4 (inline
  switch), WU-1 (profile-aware empty state), WU-6 (help overlay). Do these first.
- **Biggest user-visible win:** WU-7 (IA) — but **blocked on human decision A-1**.
- **Biggest maintainability win:** WU-8 (TD-4 finish) — unblocks clean UI work;
  med-high regression risk mitigated by strong existing tests.
- **Low-ROI / defer:** WU-5 (permission dialog — recommend no change), 2.2
  (tap=download — accidental-download risk), 5.3 (quick add-key — YAGNI).
- **Out of scope (tracked, not done):** 4.2 (persist Always-allow across
  restarts), R-1 (Flutter Web), R-2 (cross-profile key sharing model), B4 true
  file-export, passkey happy-path (needs macOS/Win/Android per AGENTS.md).
