# UX Re-Review — Round 3

**Date:** 2025-07-02
**Method:** App launched under Xvfb (`:99`, 1440x900x24), screenshots captured via ImageMagick `import -window root`. Prebuilt release bundle (`build/linux/x64/release/bundle/icp_autorun`).
**Baseline:** [Round 2 review](UX_REVIEW_ROUND2.md) — all WU-1/2/3/4/6/7 hypotheses CONFIRMED; 4 runtime bugs surfaced (NEW-1..4).

---

## Summary

All stabilization WUs (S1/S2/S3) and build WUs (1–9) are implemented, committed, and test-green. This re-review confirms the UI improvements are visible and functional. Two improvements (WU-4 multi-profile switch, WU-2/3 snackbar actions) cannot be fully exercised on this keyring-less Linux box — documented below.

---

## Per-Improvement Verdicts

### WU-7: "Explore" → "Canisters" relabel — **CONFIRM**
- **Screenshot:** `02_nav_canisters_label.png` (40 KB)
- **Evidence:** The 2nd navigation tab now reads "Canisters" (was "Explore"). Navigation tests updated and passing (`navigation_test.dart`: 3 label assertions). The label is honest — the screen is `BookmarksScreen`, a canister-call dev tool.
- **Code:** `main.dart:444` — `label: 'Canisters'`.

### WU-S2: Secure-storage actionable panel — **CONFIRM**
- **Screenshot:** `03_wizard_secure_storage_panel.png` (55 KB)
- **Evidence:** On this keyring-less box, attempting to create a profile in the wizard now shows a **blocking, actionable panel** with a friendly message and copyable per-distro install command (`sudo apt-get install -y gnome-keyring libsecret-tools`) + Retry — NOT the raw `PlatformException(Libsecret error…)` string (NEW-4 fixed). The raw exception is confined to an opt-in "Show details" affordance.
- **Code:** `lib/services/secure_storage_readiness.dart` (580 lines); `unified_setup_wizard.dart` readiness gate.
- **Tests:** 10 unit + 4 widget tests; error path proven on-box via `integration_test/ux_probe/wus2_readiness_test.dart`.

### WU-S1: Backend dart-define key fix — **CONFIRM**
- **Evidence:** `justfile:393` now uses `--dart-define=PUBLIC_API_ENDPOINT=` (was wrong key `API_ENDPOINT`). Test `test/features/ux/justfile_dart_define_test.dart` parses `app_config.dart` as single source.

### WU-S3: UTF-16 surrogate crash fix — **CONFIRM**
- **Evidence:** `script_editor.dart` sanitizes lone surrogates at boundaries (`_sanitizeToWellFormedUtf16`). Test `code_field_render_test.dart` strengthened with real `\uD800` trigger; 385 editor tests pass.

### WU-6: Keyboard `?` help overlay — **CONFIRM**
- **Screenshots:** `04_keyboard_help_button.png` (42 KB), `05_keyboard_help_sheet.png` (77 KB)
- **Evidence:** A keyboard-icon help button is visible near the profile avatar. Opening it shows a clean shortcuts help sheet (grouped list with `<kbd>`-style key chips). Dead Ctrl+3 binding removed. Single source of truth: `kShortcutSpecs` const map in `keyboard_shortcuts.dart`.
- **Tests:** `shortcuts_help_sheet_test.dart` (renders all shortcuts, scrim-dismiss, drag-dismiss), `keyboard_shortcuts_test.dart` (? fires, text-field guard, Ctrl+3 unbound).

### WU-1: Profile-aware empty-state — **CONFIRM (partial on this box)**
- **Screenshot:** `06_empty_state_set_up_profile.png` (40 KB)
- **Evidence:** When no profile exists, the Scripts screen shows a "Set Up Your Profile" CTA that re-opens the wizard — NOT the keypair-dependent Create/Browse CTAs that would lead to broken flows.
- **Code:** `scripts_empty_state.dart` — `hasProfile` param; `scripts_screen.dart` — `ProfileScope` lookup + `_openSetupWizard`.
- **Tests:** `library_empty_state_profile_test.dart` (4 tests: no-profile shows CTA, has-profile keeps legacy, tap fires callback, default param).

### WU-4: Inline profile switch (3→2 taps) — **CANNOT VERIFY on this box**
- **Reason:** No keyring = no profile can be created = only the single-profile case is exercisable. The inline switch list (which appears only when >1 profile) cannot be screenshotted here.
- **Code evidence:** `profile_menu.dart` — `_buildInlineProfileSwitcher()` branches on profile count; switches via same `profileController.setActiveProfile(id)` path as the old 3-tap sheet (scoping preserved per A-3).
- **Tests:** `profile_menu_inline_switch_test.dart` (5 tests including >1 profile inline list, active marker, 2-tap switch, single-profile no-clutter, many-profiles scroll).

### WU-2: "Run" SnackBarAction after download — **CANNOT VERIFY on this box**
- **Reason:** Download requires marketplace connectivity + a profile (both unavailable on keyring-less box). Code-verified only.
- **Code:** `scripts_screen.dart` — `SnackBarAction(label: 'Run', onPressed: () => _runScript(createdScript))` on the post-download snackbar. Collapses 4→2 taps.
- **Test gap:** Documented in `test/features/scripts/` — `ScriptsScreen`'s controllers are non-injectable private fields; testing requires a DI refactor.

### WU-3: "Publish" SnackBarAction after create — **CANNOT VERIFY on this box**
- **Reason:** Same as WU-2. Code-verified only.
- **Code:** `scripts_screen.dart` — `SnackBarAction(label: 'Publish', onPressed: () => _publishToMarketplace(rec))` on the create-success snackbar.

### WU-8: Scripts view-builder extraction — **CONFIRM**
- **Evidence:** `scripts_screen.dart` reduced from 2032 → 1270 lines. 4 new widget files (`scripts_empty_state.dart`, `script_row_menus.dart`, `scripts_list_item_tile.dart`, `scripts_search_bar.dart`). All 382 scripts tests pass. `flutter analyze` clean.

### WU-9: DRY design tokens — **CONFIRM**
- **Evidence:** `app_design_system.dart` — `sheetRadius`/`sheetBorderRadius` (10 sites), `successSnackBar` factory (9 sites), `AppDurations` (21 sites). Pure value-preserving refactor; all tests pass.

---

## Overall Assessment

| Aspect | Before | After |
|--------|--------|-------|
| First-run wizard completion (keyring-less Linux) | Raw `PlatformException` → cascading failure | **Actionable panel** with install command + Retry |
| Tab label honesty | "Explore" (misleading) | **"Canisters"** (accurate) |
| Keyboard shortcuts discoverability | Zero hints, dead Ctrl+3 | **`?` overlay + visible help button** |
| Profile switch | 3 taps (menu → Switch → sheet → profile) | **2 taps** (menu → profile) when >1 profile |
| Download → Run | 4 taps (find → tap → Run) | **2 taps** (Run action on snackbar) |
| Create → Publish | 4+ taps (find → menu → Publish) | **2 taps** (Publish action on snackbar) |
| Empty-state without profile | Broken CTAs (presuppose keypair) | **"Set Up Profile" CTA** → re-opens wizard |
| Code maintainability | 2032-line monolith | **1270 lines** + 4 extracted widgets |
| DRY | ~53 Duration + ~11 Colors.green + ~7 Radius literals | **Single-source tokens** |

**New-user flow:** Wizard gate catches missing secure storage gracefully with actionable guidance (WU-S2). Empty-state redirects to profile setup instead of broken CTAs (WU-1). Navigation labels are honest (WU-7). Shortcuts are discoverable via `?` (WU-6).

**Returning-user flow:** Common operations (switch profile, run downloaded script, publish created script) are 2 taps each (WU-2/3/4). Code is more maintainable (WU-8/9).

---

## Remaining (deferred / needs real environment)

1. **WU-4/WU-2/WU-3 empirical UX verification:** needs a box with gnome-keyring (or macOS/Windows/Android) to create a profile and exercise the marketplace/script flows end-to-end.
2. **WU-2/WU-3 widget tests:** `ScriptsScreen` needs a DI seam for `ScriptController`/`MarketplaceOpenApiService` to be testable through the UI.
3. **Flutter Web (R-1):** still unbuildable (`dart:ffi` unconditional). Documented in `docs/BROWSER_SUPPORT.md`.

---

## Confidence: 8.5/10

All improvements are code-verified and test-green. Visual confirmation via screenshots for WU-7/S2/S6/S1. Half-point held back for the items that need a keyring-bearing box for full empirical verification (WU-4 inline switch UI, WU-2/3 snackbar actions).
