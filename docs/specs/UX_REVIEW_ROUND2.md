# UX Review — Round 2 (Empirical)

**Date:** 2026-07-02 · **Method:** real Flutter app driven via `integration_test`
probes under Xvfb (no xdotool/tmux), plus direct code inspection. The prebuilt
release bundle was also launched against Xvfb to confirm clean boot.
**Hard constraint honored:** `git diff apps/autorun_flutter/lib` is **empty** —
no production code was modified. Only `pubspec.yaml` (`integration_test`
dev-dep), the probe files under `integration_test/ux_probe/`, this doc, and the
screenshots changed.

---

## TL;DR — verdict matrix

| ID | Claim | Verdict | Evidence basis |
|----|-------|---------|----------------|
| B3 | First-run wizard gate (`UnifiedSetupWizard`) | ✅ CONFIRM | driven (shot 01) |
| WU-1 | Empty state presupposes identity that doesn't exist | ✅ CONFIRM | driven (shot 02) |
| WU-2 | Download SnackBar has no "Run" action | ✅ CONFIRM | code (`scripts_screen.dart:419-436`) + browse (shot 05) |
| WU-3 | Create SnackBar has no "Share" action | ✅ CONFIRM | driven end-to-end, green bar, no action (shot 06) |
| WU-4 | Profile switch is a 3-tap flow | ✅ CONFIRM | menu driven (shot 07) + code (`profile_menu.dart:207,513-568`) |
| WU-6 | Ctrl+3 dead + shortcuts not discoverable | ✅ CONFIRM | driven (`keyboard_shortcuts.dart:73-75`); shot 11 |
| A-1 | "Explore" tab is a canister dev tool, not marketplace | ✅ CONFIRM | driven (shot 09); rename→"Canisters" validated |
| B2 | Passkey surfaces honest about Linux-unsupported | ✅ CONFIRM | code (`passkey_management_screen.dart:33-37,227-259`) |
| **NEW-1** | justfile dart-define key mismatch | ✅ CONFIRM | code + driven with correct key |
| **NEW-2** | Secure storage broken on bare Linux (no keyring) | ✅ CONFIRM | driven — `createProfile` THROWS (shot 03) |

**Headline:** the Round-1 UX fixes (B3 wizard gate, B2 passkey honesty) are
working as intended. **But a new, severe blocker — NEW-2 — makes the app
unusable for new users on a minimal Linux desktop:** profile creation throws a
`libsecret` `PlatformException`, so the wizard can never complete and no
identity/keypair can ever be established. This cascades into every
identity-dependent flow (share, publish, passkey, multi-profile). NEW-2 must be
fixed (or worked around with a documented fallback keystore) before any
returning-user UX work is meaningful on Linux.

---

## Setup (what ran)

- **Display:** `Xvfb :99 -screen 0 1440x900x24` (verified via
  `import -window root` → 1440×900). `xdpyinfo`/`xdotool`/`tmux` are absent by
  design.
- **Prebuilt binary:** `apps/autorun_flutter/build/linux/x64/release/bundle/icp_autorun`
  launches cleanly against Xvfb. Only harmless GTK/Atk headless warnings:
  `atk_socket_embed: assertion 'plug_id != NULL' failed` and
  `fl_gnome_settings_set_interface_settings: assertion 'G_IS_SETTINGS(settings)'`
  — both cosmetic, app renders normally.
- **Driving:** Flutter `integration_test` (`integration_test:
  {sdk: flutter}` added under `dev_dependencies`). This Flutter checkout (3.38.3,
  user branch) uses the older class name
  **`IntegrationTestWidgetsFlutterBinding`** (not `…TesterBinding`). The
  `integration_test` method-channel `takeScreenshot` is unserviced without a
  driver, so probes capture straight from the layer tree via
  `RenderView.layer.toImage(...)` (see `integration_test/ux_probe/ux_helpers.dart`).
- **Backend (flows B):** `just api-dev-up` → healthy at `http://127.0.0.1:45959`
  (`/api/v1/health` ok; seeds marketplace scripts, verified via `curl`).
- FFI (`libicp_core.so`) loads in the test build via the `build/linux/x64/debug/bundle/lib/` path.

> **Storage-path correction.** The execution plan assumed profile data at
> `~/.local/share/com.example.icp_autorun/profiles.json`. `path_provider`'s
> `getApplicationSupportDirectory()` on this Linux build actually resolves to
> **`~/.cache/data/com.example.icp_autorun/`**. The plan's path was never
> created; this is noted but not a bug per se.

---

## NEW-1 — justfile dart-define key mismatch (CONFIRMED)

- `apps/autorun_flutter/lib/config/app_config.dart:6` reads **`PUBLIC_API_ENDPOINT`**.
- `justfile:393` defines **`API_ENDPOINT`** (the run-recipe `--dart-define=API_ENDPOINT=…`).

The app therefore **ignores** the justfile recipe and falls back to the baked-in
prod default `https://icp-mp.kalaj.org`. Running `just`-style against a local
backend silently points the app at production.

**Empirical proof (correct key works):**
```
flutter test integration_test/ux_probe/a_first_run_test.dart \
  --dart-define=PUBLIC_API_ENDPOINT=http://127.0.0.1:45959
→ === App Configuration ===
  API Endpoint: http://127.0.0.1:45959
  Environment: Local Development
  Is Local Development: true
```
**Fix:** change `justfile:393` `API_ENDPOINT` → `PUBLIC_API_ENDPOINT` (or make
`app_config.dart` accept both). One-line change in `justfile` (not in `lib/`).

---

## NEW-2 — Secure storage throws on a minimal Linux desktop (CONFIRMED, severe)

On this box there is **no secret service**: `gnome-keyring-daemon` and
`secret-tool` are absent, and `DBUS_SESSION_BUS_ADDRESS` is unset. `flutter_secure_storage`
9.2.2 (→ `flutter_secure_storage_linux` → libsecret) therefore cannot store
anything.

**Decisive probe** (`integration_test/ux_probe/new2_diagnostic_test.dart`),
exercising the *exact* path the wizard uses
(`ProfileController.createProfile` → `ProfileRepository.persistProfiles` →
`FlutterSecureStorage.write`):

```
NEW2_SECURE_STORAGE: secureStorage.write: PlatformException code=Libsecret error
  message=Failed to unlock the keyring details=null
NEW2_SECURE_STORAGE: secureStorage.read: THREW PlatformException:
  PlatformException(Libsecret error, Failed to unlock the keyring, null, null)
NEW2_CREATE_PROFILE: createProfile: THREW PlatformException:
  PlatformException(Libsecret error, Failed to unlock the keyring, null, null)
NEW2_CREATE_PROFILE: profiles.json EXISTS, length=27, hasProfile=false
NEW2_CREATE_PROFILE: profiles.json head: {"version":1,"profiles":[]}
NEW2_CREATE_PROFILE: profiles.json leaks private/mnemonic data: false
```

Consequences (all verified):
1. **`createProfile` throws.** The wizard's `_finish`
   (`unified_setup_wizard.dart:582`) → `createProfile`
   (`profile_controller.dart:120`) → `persistProfiles`
   (`profile_repository.dart:167`) writes secure storage **before** the public
   file, so it throws and the profile is **never persisted** (`profiles.json`
   stays `{"version":1,"profiles":[]}`).
2. **The wizard cannot complete on Linux desktop.** `_handleCreate`
   (`unified_setup_wizard.dart:611`) catches the error and surfaces it.
3. **Cascades into every identity flow:** share/publish (need a keypair to
   sign), passkey registration, and multi-profile switching are all unreachable
   because no profile can ever exist. This is why flows B (WU-2/3/4) were
   partially obstructed and WU-4's full 3-tap path is code-confirmed only.
4. **No data leak:** the private key is correctly *not* written to the plaintext
   `profiles.json` — but it is also not stored anywhere, so a profile created
   here would silently lose its key (moot, since creation throws first).

**Fix direction (human decision):** either (a) document that Linux desktop
requires a running keyring (`gnome-keyring-daemon` + D-Bus) and fail loud at
startup with a setup hint, or (b) implement a fallback keystore (e.g.
password-encrypted file, consistent with the existing vault model) when
libsecret is unavailable. This is architectural — do **not** paper over with a
silent plaintext fallback.

---

## NEW-3 — `code_text_field` CodeField render crash (new, observed)

While the Scripts screen is mounted, `ScriptEditor` → `CodeField`
(`widgets/script_editor.dart:475`) throws **`ArgumentError … while building a
TextSpan`** during `drawFrame`, reproducibly, once real script/marketplace
content loads (it does not fire when the backend is unreachable and no content
renders). Flutter recovers sibling widgets (the green success SnackBar still
rendered in WU-3 despite it), but the framework collects the exception and marks
the test failed. This makes the Scripts surface unstable whenever code content
is shown. Root cause is inside the `code_text_field` package's highlighter
building a `TextSpan`; recommend a defensive fix in `ScriptEditor` or an
upstream issue. Not in scope to fix here (would touch `lib/`).

---

## NEW-4 — Wizard surfaces a raw `PlatformException` to the user (new)

When NEW-2 fires, the wizard's error banner
(`unified_setup_wizard.dart:300` `_buildErrorBanner`, fed by
`_handleCreate:613` `_errorMessage = e.toString().replaceAll('Exception: ', '')`)
shows the user the verbatim string:

> `PlatformException(Libsecret error, Failed to unlock the keyring, null, null)`

That is a developer-facing stacktrace-style message, not a human one. Confirmed
in the A3 probe (`bannerText=PlatformException(Libsecret error, Failed to unlock
the keyring, null, null)`). Map known platform errors to friendly copy
("Couldn't access the system keyring — see setup guide"), keeping the technical
detail behind a "show details" affordance.

---

## A — First-run (NEW USER)

### A1 — First-run wizard gate (B3 fix)  ✅ CONFIRM
- **Did:** clean state (no profile dir), launched app, pumped until the wizard
  route settled (`integration_test/ux_probe/a_first_run_test.dart` test A1).
- **Screenshot:** [`01_first_run_wizard.png`](ux_screenshots/round2/01_first_run_wizard.png)
- **Result:** `UnifiedSetupWizard` is pushed (`main.dart:453`
  `showFirstRunSetupIfNeeded`) when `profiles.isEmpty`. Asserted presence of
  heading "Create Your Profile", field "How should we call you?", and "Get
  Started". Indigo brand accent `#6366F1` + `#FAFAFA` background confirm the
  polished onboarding renders. **B3 is working.**

### A2 — Empty state dead-end (WU-1)  ✅ CONFIRM
- **Did:** dismissed the wizard via its `Icons.close` AppBar button
  (`unified_setup_wizard.dart:83`), pumped, captured the resulting Scripts
  screen.
- **Screenshot:** [`02_empty_state_no_profile.png`](ux_screenshots/round2/02_empty_state_no_profile.png)
- **Result:** `A2_WU1: guestShown=false hasNewScriptCta=true`. With **no profile
  and no keypair**, the empty Scripts screen still presents the **"New Script"**
  FAB (`scripts_screen.dart:804`) and other identity-dependent CTAs. A
  first-time user who dismisses the wizard is stranded on a surface that
  assumes an identity they were never able to create. **WU-1 confirmed.**
  (Combined with NEW-2, the dead-end is total on Linux: there is no working
  path to create the missing identity.)

### A3 — Wizard completion (NEW-2)  ✅ CONFIRM (errors)
- **Did:** entered a display name, tapped the `FilledButton` "Get Started"
  (`unified_setup_wizard.dart:334`), polled for the success screen
  ("Start Exploring" / "Success!") vs the error banner
  (`Icons.error_outline`).
- **Screenshot:** [`03_wizard_success.png`](ux_screenshots/round2/03_wizard_success.png)
  *(named per plan; actually shows the **error** state — the wizard cannot
  succeed on bare Linux.)*
- **Result:** `A3_NEW2_RESULT: sawError=true sawSuccess=false
  bannerText=PlatformException(Libsecret error, Failed to unlock the keyring, null, null)`.
  The wizard surfaces the libsecret failure and does **not** reach the success
  screen. See NEW-2 / NEW-4.

---

## B — Returning-user loops

> **Reachability note:** flows B need a profile/keypair. NEW-2 makes profile
> creation impossible on this box, so the full returning-user journey cannot be
> exercised end-to-end here. WU-2 is confirmed structurally by code; WU-3 is
> local and was driven in full; WU-4's full 3-tap path is code-confirmed with
> the first 2 taps driven.

### B / WU-2 — Download SnackBar has no "Run" action  ✅ CONFIRM (code + browse)
- **Code (decisive):** the download success `SnackBar`
  (`scripts_screen.dart:419-436`) declares **no `action:`** — only an
  icon+text row ("…added to your library!", green, 4s). After download the user
  is dropped back to the list with no immediate "Run" affordance; running the
  just-downloaded script requires locating it in "My Library" and tapping again
  (≥2 extra taps).
- **Driven (partial):** with the app pointed at the local backend
  (`--dart-define=PUBLIC_API_ENDPOINT=…`), the marketplace loaded
  (`WU2_DOWNLOAD: marketplaceLoaded=true`, 2 cards) and screenshot 05 was
  captured, but the green "added to your library" SnackBar did not surface in
  the headless probe: the per-card **Download action is hover-revealed**
  (`scripts_screen.dart:1411` `HoverRevealActions`, not hit-testable without a
  hover), the overflow-menu path tapped into local-script cards (whose menu is
  Edit/Delete, not Download), and the NEW-3 CodeField crash destabilised the
  frame. Backend path itself verified good via `curl`
  (`GET /api/v1/scripts/<id>` returns the seeded "Script to Publish", price 0).
- **Screenshot:** [`05_download_snackbar.png`](ux_screenshots/round2/05_download_snackbar.png)
  *(browse/marketplace state; the success bar itself is code-confirmed.)*
- **Verdict:** **WU-2 confirmed.** Add a `SnackBarAction(label: 'Run',
  onPressed: () => _runScript(createdScript))` to the download bar.

### B / WU-3 — Create SnackBar has no "Share" action  ✅ CONFIRM (driven)
- **Did:** dismissed the wizard, tapped "New Script" (`scripts_screen.dart:804`
  FAB), entered a title + source, tapped "Create Script"
  (`script_creation_screen.dart:510`). `createScript()`
  (`script_controller.dart:220`) is purely local (no keypair/backend), so this
  flow is **not** blocked by NEW-2.
- **Screenshot:** [`06_create_snackbar.png`](ux_screenshots/round2/06_create_snackbar.png)
  *(green success bar — `#43A047`, ~71k px — confirmed present.)*
- **Result:** `WU3_CREATE: snackbarShown=true hasShareAction=false`. The
  "Script created successfully!" `SnackBar` (`scripts_screen.dart:551-571`)
  declares **no `action:`** and returns the user to the list with no path to
  publish/share the freshly created script. **WU-3 confirmed.**
- *(Probe run ends in a framework-reported error from the NEW-3 CodeField
  crash, unrelated to WU-3 — the decisive `hasShareAction=false` assertion is
  printed before the exception is collected.)*

### B / WU-4 — Profile switch is a 3-tap flow  ✅ CONFIRM (menu driven + code)
- **Did:** tapped the always-visible `ProfileAvatarButton`
  (`main.dart:409`), captured the resulting bottom sheet.
- **Screenshot:** [`07_profile_menu.png`](ux_screenshots/round2/07_profile_menu.png)
- **Result:** `WU4_MENU: hasMyAccount=true hasSwitchProfile=true hasSettings=true`.
  The avatar sheet (`profile_menu.dart:198`) shows three tiles: **My Account**,
  **Switch Profile**, **Settings**. "Switch Profile"
  (`profile_menu.dart:207-214`) opens a *second* sheet
  (`ProfileMenuAction.manageProfiles`) where the actual profile rows live
  (`profile_menu.dart:513-568`, each row `onTap → setActiveProfile + pop`).
- **Tap count = 3:** (1) avatar → (2) "Switch Profile" → (3) target profile row.
  *(Screenshots 08_manage_profiles_sheet and the 3rd tap could not be captured
  because NEW-2 prevents creating a 2nd profile.)* **WU-4 confirmed by code +
  driven menu.**
- **Verdict:** the plan's "1-tap switch" target is **not** met. Recommend
  inlining the profile list directly in the avatar sheet (collapse to 2 taps:
  avatar → target profile), or a quick-switch row of avatar chips.

---

## C / A-1 — The "Explore" tab is a canister dev tool  ✅ CONFIRM (rename validated)
- **Did:** dismissed wizard, tapped the "Explore" nav item
  (`main.dart:442`, label "Explore", icon `Icons.dns_*`).
- **Screenshot:** [`09_explore_tab_is_canisters.png`](ux_screenshots/round2/09_explore_tab_is_canisters.png)
- **Result:** `C_A1: isCanisterTool=true`. The "Explore" tab renders
  `BookmarksScreen` (`main.dart:398`) with heading **"Explore ICP Services"**,
  sections **"Popular Canisters"**, **"Your Bookmarks"**, **"Recent Calls"**
  (`bookmarks_screen.dart:84-187`). This is a **canister-call developer tool**,
  not a marketplace browser. The "Explore" label is misleading — a user
  expecting marketplace discovery lands on RPC/candid tooling.
- **Verdict:** **the plan's rename "Explore → Canisters" is validated.** No
  counter-evidence. (Also note: there is no marketplace browse tab at all in
  the 2-tab nav — marketplace scripts surface inline within the Scripts tab;
  that is a separate discoverability concern.)

---

## D / WU-6 — Keyboard shortcuts: Ctrl+3 dead + not discoverable  ✅ CONFIRM
- **Did:** dismissed wizard, sent key events via `tester.sendKeyEvent`/`sendKey
  DownEvent`, and polled tab content.
- **Screenshot:** [`11_shortcut_undiscoverable.png`](ux_screenshots/round2/11_shortcut_undiscoverable.png)
- **Result:**
  ```
  D_WU6: exploreShownInitially=false
  D_WU6: exploreShownAfterCtrl2=true   ← Ctrl+2 works (→ Explore)
  D_WU6: exploreShownAfterCtrl1=false  ← Ctrl+1 works (→ Scripts)
  D_WU6: exploreShownAfterCtrl3=false  ← Ctrl+3 is DEAD (no 3rd tab; no change)
  D_WU6_discoverability: hasShortcutHelpOverlay=false
  ```
- **Code:** `keyboard_shortcuts.dart:73-75` registers
  `Ctrl+3 → _NavigateTabIntent(2)`, but `main.dart:394-399` only has **2**
  `IndexedStack` children. `Ctrl+3` therefore fires its action with no
  destination — a dead, undocumented shortcut.
- **Discoverability:** there is **no** "?" overlay, no shortcut legend, no
  always-on hint. `ShortcutTooltip` (`keyboard_shortcuts.dart:207`) only
  decorates individual controls on **hover** as a Material `Tooltip`, so a user
  cannot learn the shortcuts without hovering every widget. **WU-6 confirmed.**
- **Verdict:** remove the `Ctrl+3` binding (or add a 3rd tab); add a global "?"
  shortcut-cheatsheet overlay (and surface hints in the empty-state /
  command-palette-style).

---

## E — Runtime honesty

- **App launched cleanly** (prebuilt bundle and integration-test build). No red
  screen of death at startup. Only cosmetic GTK/Atk headless warnings and the
  NEW-3 `TextSpan` render exception (logged, recovered).
- **Passkey honesty (B2 fix) ✅ CONFIRM (code).** On Linux desktop
  `PasskeyPlatform.isSupported == false` (`utils/passkey_platform.dart:5-7`).
  `passkey_management_screen.dart:33-37` short-circuits to an explicit message:
  *"Use the app on macOS, Windows, or Android to manage passkeys (browser
  support is deferred — see R-1)"*, and `_buildUnsupportedPlatformError()`
  (`:227-259`) reiterates "Passkeys are supported on macOS, Windows, and
  Android … Browser support on Linux is deferred (R-1)". Honest, no
  `flutter run -d chrome` attempted. *(Screenshot `10_passkey_unsupported_honest`
  could not be captured: the passkey screen is reached via the avatar menu →
  account flow, which requires a profile, blocked by NEW-2.)*
- **Exceptions flagged:** NEW-2 (libsecret, fatal to onboarding), NEW-3
  (`code_text_field` TextSpan, destabilising), NEW-4 (raw exception copy in
  wizard). No other uncaught exceptions observed.

---

## What could NOT be driven (honest gaps)

| Step | Why blocked |
|------|-------------|
| `08_manage_profiles_sheet` + WU-4 3rd tap | NEW-2 — cannot create a 2nd profile |
| `10_passkey_unsupported_honest` | reached via profile/account flow → needs a profile → NEW-2 |
| WU-2 success-SnackBar screenshot | hover-revealed Download + NEW-3 CodeField crash; **code-confirmed instead** |

In every blocked case the verdict was still reached via direct code inspection
(cited with `file:line`) or via the local backend (`curl`).

---

## Confidence

**8.5 / 10.** Every Round-2 WU (1/2/3/4/6 + A-1) and both NEW items are
confirmed with cited evidence (driven where reachable, code where blocked).
The half-point hold-back is for the two screenshots that NEW-2 made unreachable
(08, 10) and the WU-2 success-bar visual (code-confirmed but not screenshotted);
none of these change any verdict.

## Probe index (`integration_test/ux_probe/`)
- `ux_helpers.dart` — launch real app, clean state, layer-tree screenshotter.
- `a_first_run_test.dart` — A1/A2/A3 (wizard, WU-1, NEW-2).
- `new2_diagnostic_test.dart` — decisive NEW-2 storage + `createProfile` probe.
- `b_create_test.dart` — WU-3 (create SnackBar).
- `b_download_test.dart` — WU-2 (download browse; needs local backend).
- `c_explore_test.dart` — A-1 (Explore = canisters).
- `d_keyboard_test.dart` — WU-6 (Ctrl+3 dead + not discoverable).
- `e_profile_menu_test.dart` — WU-4 (avatar menu structure).
- `_smoke_test.dart` — harness smoke test.

Reproduce any probe with, e.g.:
```bash
cd apps/autorun_flutter
DISPLAY=:99 flutter test integration_test/ux_probe/<file>.dart
# flows needing the backend:
just api-dev-up   # then --dart-define=PUBLIC_API_ENDPOINT=http://127.0.0.1:<port>
```
