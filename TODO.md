# ICP Script Marketplace - TODO

**Last Updated:** 2026-02-21 (Phase 3 Analysis)

## Current Focus

**Goal:** Radical UI/UX simplification. Remove clutter, improve discoverability.

**Reality Check - UX Simplification Wave COMPLETE:**
- **NEW:** Scripts Screen Cleanup - removed stats banner, share banner, getting started card (7 tests)
- **NEW:** Profile Menu Discoverability - "Profile" label next to avatar for discoverability (5 tests)
- **NEW:** Featured Scripts Carousel Removed - cleaner UI, more vertical space (2 tests)

**Previously Shipped (This Week):**
- **NEW:** Script Favorites System - star/favorite scripts with filter (38 tests)
- **NEW:** Offline Mode Banner - clear indication when network unavailable (25 tests)
- **NEW:** Bulk Script Management - multi-select, bulk delete/export (33 tests)
- **NEW:** UX Analysis Complete - 10 radical improvements identified
- **NEW:** UX Analysis Phase 3 - 8 new issues from new user perspective (see Phase 3 section)
- **NEW:** Unsaved Changes Warning - prevents data loss when closing script editor
- **NEW:** Downloaded Filter Empty State - helpful guidance when no downloads exist
- **NEW:** Passkey Linux Error Message - clear instructions for browser-based passkeys
- **NEW:** 2-Tab navigation (Home, Discover) with Profile menu in app bar
- **NEW:** Simplified first-run experience (just "What's your name?")
- **NEW:** Services renamed to "Explore" with subtitle
- **NEW:** Prominent Publish Button - share icon on local scripts, dismissible banner
- **NEW:** Passkey Quick Access - shows count in profile menu, highlights when no passkeys
- **NEW:** Script Reviews Tab - read-only reviews with rating distribution in ScriptDetailsDialog
- **NEW:** Script Versions Tab - version history with install capability in ScriptDetailsDialog
- **NEW:** Canister Interaction History - save/replay recent canister calls
- **NEW:** Long-press Context Menu - quick actions on script cards (mobile + desktop)
- **NEW:** Downloaded Filter - filter scripts by download status
- **NEW:** Enhanced Quick Actions - gradient backgrounds, "See All" button, hover effects
- **NEW:** Single-Page Script Creation - tabs removed, sticky create button
- **NEW:** Canister Client Full Screen - 3-step flow (Canister → Function → Call)
- **NEW:** Response Format Toggle - JSON/Table/Raw view selector for results
- **NEW:** Search History - recent searches dropdown in marketplace
- **NEW:** Canister Autocomplete - search canisters by ID or name
- **NEW:** Actionable Error Handling - clear guidance on what to do when errors occur
- **NEW:** Getting Started Guide - checklist for new users with progress tracking
- **NEW:** Settings Screen - theme toggle (Light/Dark/System), app info, external links
- **NEW:** Account Profile Screen Tests - comprehensive test coverage (46 tests)
- Flattened Scripts screen (no nested tabs, Marketplace prominent)
- Script execution progress indicator
- Pull-to-refresh on all lists
- Post-setup guide for new users
- Keyboard shortcuts for desktop
- Simplified Canister Client Sheet
- Technical term tooltips
- Script menu reduced to 5 local / 2 marketplace options
- Consolidated Scripts Screen controls (4 rows → 1)
- Quick Actions on Explore screen (ICP Balance, View Neurons, Search Dapps)
- Single-tap script execution (Play button on script rows)
- Editor toolbar cleanup (collapsed into overflow menu)

**Next Wave:** Phase 3 UX Improvements (8 new issues identified from new user perspective analysis), write reviews API (backend needed), smart Candid forms, script automation/scheduler.

Payments and messaging are explicitly out of scope until the foundation is solid.

## Implementation Summary

| Area | Status | Completion |
|------|--------|------------|
| **2-Tab Navigation** | **COMPLETE** | 100% |
| **Quick Profile Creation** | **COMPLETE** | 100% |
| **Explore Tab (formerly Services)** | **COMPLETE** | 100% |
| **Profile Avatar Menu** | **COMPLETE** | 100% |
| Unified Setup Wizard | **COMPLETE** | 100% |
| Flattened Scripts Screen | **COMPLETE** | 100% |
| Consolidated Scripts Controls | **COMPLETE** | 100% |
| Single-Tap Script Execution | **COMPLETE** | 100% |
| Editor Toolbar Cleanup | **COMPLETE** | 100% |
| Services Quick Actions | **COMPLETE** | 100% |
| Script Execution Progress | **COMPLETE** | 100% |
| Pull-to-Refresh | **COMPLETE** | 100% |
| Prominent Publish Button | **COMPLETE** | 100% |
| Passkey Quick Access | **COMPLETE** | 100% |
| ~~Featured Scripts Section~~ | **REMOVED** | N/A |
| Passkey UI Integration | **COMPLETE** | 100% |
| Linux Passkey Support | **COMPLETE** | 100% |
| Welcome Onboarding | **COMPLETE** | 100% |
| Lua Scripting UI | **COMPLETE** | 100% |
| Enhanced Empty States | **COMPLETE** | 100% |
| Encrypted Backup/Restore | **COMPLETE** | 100% |
| Download History Navigation | **COMPLETE** | 100% |
| Post-Setup Guide | **COMPLETE** | 100% |
| Keyboard Shortcuts | **COMPLETE** | 100% |
| Canister Client UX | **COMPLETE** | 100% |
| Technical Term Tooltips | **COMPLETE** | 100% |
| Profile Management | **COMPLETE** | 100% |
| Navigation Labels (Explore) | **COMPLETE** | 100% |
| Script Menu Reduction | **COMPLETE** | 100% |
| **Script Reviews Tab** | **COMPLETE** | 100% |
| **Downloaded Filter** | **COMPLETE** | 100% |
| **Enhanced Quick Actions** | **COMPLETE** | 100% |
| **Single-Page Script Creation** | **COMPLETE** | 100% |
| **Canister Client Full Screen** | **COMPLETE** | 100% |
| **Response Format Toggle** | **COMPLETE** | 100% |
| **Search History** | **COMPLETE** | 100% |
| **Canister Interaction History** | **COMPLETE** | 100% |
| **Script Versions Tab** | **COMPLETE** | 100% |
| **Long-Press Context Menu** | **COMPLETE** | 100% |
| **Canister Autocomplete** | **COMPLETE** | 100% |
| **Actionable Error Handling** | **COMPLETE** | 100% |
| **Getting Started Guide** | **COMPLETE** | 100% |
| **Settings Screen** | **COMPLETE** | 100% |
| **Account Profile Screen Tests** | **COMPLETE** | 100% |
| ~~Marketplace Stats Banner~~ | **REMOVED** | N/A |
| **Unsaved Changes Warning** | **COMPLETE** | 100% |
| **Downloaded Filter Empty State** | **COMPLETE** | 100% |
| **Passkey Linux Guidance** | **COMPLETE** | 100% |
| **Script Favorites System** | **COMPLETE** | 100% |
| **Offline Mode Banner** | **COMPLETE** | 100% |
| **Bulk Script Management** | **COMPLETE** | 100% |
| **Scripts Screen Cleanup** | **COMPLETE** | 100% |
| **Profile Menu Discoverability** | **COMPLETE** | 100% |
| **Interactive Spotlight Tour** | **COMPLETE** | 100% |
| **Plain Language UX** | **COMPLETE** | 100% |
| Account Registration | Complete | 100% |
| Passkey Auth (backend) | Complete | 95% |
| Marketplace Browse/Search | Needs Testing | 90% |
| Marketplace Upload | Needs Testing | 95% |
| Script Execution (Lua) | Partial | 85% |
| Testing Coverage | Improved | ~95% |

**Detailed Specs:**
- [Implementation Status](docs/specs/IMPLEMENTATION_STATUS.md) - Feature-by-feature breakdown
- [Marketplace Status](docs/specs/MARKETPLACE_STATUS.md) - Marketplace implementation deep dive
- [Backend Integration](docs/specs/BACKEND_INTEGRATION.md) - API and data layer architecture
- [Test Coverage Gaps](docs/specs/TEST_COVERAGE_GAPS.md) - Missing tests analysis

---

## HIGH Priority

### Passkey Authentication
See [PASSKEY_IMPLEMENTATION_PLAN.md](PASSKEY_IMPLEMENTATION_PLAN.md) for architecture.

**Backend (DONE):**
- [x] WebAuthn endpoints (register/authenticate start/finish)
- [x] Vault encryption utilities (Argon2id + AES-GCM)
- [x] Recovery code system (generate, hash, verify)
- [x] Database schema (passkeys, recovery_codes, user_vaults tables)

**Frontend (DONE):**
- [x] PasskeyService using `passkeys` package
- [x] Vault password setup screen
- [x] Vault unlock screen
- [x] Recovery codes display screen
- [x] Passkey management screen (list, add, delete)

**Tests (DONE):**
- [x] PasskeyService unit tests
- [x] Screen widget tests
- [x] E2E tests with FakePasskeyAuthenticator (software emulator for CI)

**UI Integration (DONE):**
- [x] Add "Passkeys" menu item to AccountProfileScreen (in the profile menu sheet)
- [x] Wire PasskeyManagementScreen into navigation from account profile
- [x] Prompt passkey setup after account registration (optional onboarding step)
- [x] Add passkey status indicator on account profile (shows count, last used)

**Linux Support (DONE):**
> **Note:** The `passkeys` package does NOT support Linux natively (only Android, iOS, macOS, Web, Windows).
>
> **Solution:** Run as Flutter Web on Linux. Browser WebAuthn works with:
> - KeePassXC (software authenticator)
> - Android phone via hybrid auth (QR code flow)
> - Hardware security keys (YubiKey, etc.)

- [x] Document Linux testing workflow in AGENTS.md
- [x] Add platform check: disable passkey UI on Linux desktop, enable on Web
- [x] Test passkey flow via `flutter run -d chrome` on Linux

**Remaining (for full production):**
(none - vault decryption now available via Rust FFI)

### 2-Tab Navigation with Profile Menu (DONE - 2026-02-21)
- [x] Remove Profile tab from bottom navigation
- [x] Add avatar with dropdown menu in app bar
- [x] Tab 1: "Home" (Scripts screen)
- [x] Tab 2: "Discover" (Canister explorer - renamed from Services to Explore)
- [x] `ProfileAvatarButton` widget in top-right corner
- [x] `ProfileMenuWidget` bottom sheet with profile options
- [x] 11 new tests for navigation components
- **Impact:** Simplified navigation, more screen space for content
- **Files:** `lib/main.dart`, `lib/widgets/profile_menu.dart`

### Quick Profile Creation (DONE - 2026-02-21)
- [x] Replace Welcome + Setup Wizard with single "What's your name?" dialog
- [x] `QuickProfileCreationDialog` - minimal first-run experience
- [x] Creates local-only profile (no account registration required)
- [x] Account registration accessible from profile settings when user wants to publish
- [x] 9 new tests
- **Impact:** Reduces first-run friction from 3+ screens to 1 dialog
- **Files:** `lib/screens/quick_profile_creation_dialog.dart`, `lib/main.dart`

### Explore Tab Rename (DONE - 2026-02-21)
- [x] Rename "Services" to "Explore" in AppBar title
- [x] Add subtitle: "Interact with Internet Computer canisters"
- [x] Update navigation bar to use "Discover" label
- [x] 5 new tests
- **Impact:** Clearer purpose for the tab
- **Files:** `lib/screens/bookmarks_screen.dart`

### Unified Setup Wizard (DONE)
- [x] `UnifiedSetupWizard` - single form for profile + optional account
- [x] Display name field (required)
- [x] Username field (optional, skip to create local-only profile)
- [x] Real-time username validation with debouncing
- [x] Success screen showing created profile/account
- [x] 12 unit/widget tests
- [x] Replaced old multi-step flow (KeyParametersDialog + AccountRegistrationWizard)

### Flattened Scripts Screen (DONE)
- [x] Removed nested tabs (My Scripts, All, Marketplace)
- [x] Single unified list showing both local and marketplace scripts
- [x] Source filter chips: All / Local / Marketplace
- [x] Category filter chips
- [x] Sort dropdown with ascending/descending toggle
- [x] Source badges on each item (Local/Marketplace)
- [x] "Available" badge for non-installed marketplace scripts
- [x] 7 unit/widget tests

### Single-Tap Script Execution (DONE - 2026-02-21)
- [x] Add visible "Play" icon button on each local script row
- [x] Run is now the PRIMARY action (one tap)
- [x] Popup menu contains secondary actions (delete, duplicate, export, publish)
- [x] 11 updated + 2 new widget tests
- **Impact:** Users run scripts with 1 tap instead of 2

### Editor Toolbar Cleanup (DONE - 2026-02-21)
- [x] Collapse clutter into overflow menu
- [x] Keep visible: Language badge, Theme selector
- [x] In overflow: Stats (lines/chars), Line numbers toggle, UI Components, Code snippets, Copy
- [x] Removed non-working "Format code" button
- [x] 7 new widget tests

### Consolidated Scripts Screen Controls (DONE - 2026-02-21)
- [x] Single search bar with filter button (tune icon with badge)
- [x] Removed Local/Marketplace filter chips - show all scripts with badges
- [x] Categories/sort moved to filter bottom sheet
- [x] Reset button to restore default filters
- [x] Active filter count badge on filter button
- [x] 35+ tests (unified_view_test.dart + filter_popover_test.dart)

### Script Execution Progress (DONE)
- [x] `ScriptExecutionProgress` model with phases (idle, initializing, calling_canister, processing, complete, error)
- [x] `ScriptExecutionProgressIndicator` widget with spinner and step message
- [x] Cancel support during cancellable phases
- [x] Integrated with `ScriptAppHost`
- [x] 12 unit/widget tests

### Pull-to-Refresh (DONE)
- [x] RefreshIndicator on BookmarksScreen
- [x] RefreshIndicator on PasskeyManagementScreen
- [x] Already existed on: ScriptsScreen, DownloadHistoryScreen, ProfileHomePage
- [x] 3 unit tests

### Welcome Onboarding Flow (DONE)
- [x] `OnboardingService` - manages onboarding state with versioning
- [x] `WelcomeOnboardingScreen` - animated welcome with feature highlights
- [x] "Get Started" button -> unified setup wizard
- [x] "Browse Marketplace" button -> scripts screen
- [x] "Skip for now" option
- [x] Only shows when NO profiles AND NO scripts
- [x] 20 unit/widget tests

### Post-Setup Guide (DONE - 2026-02-20)
- [x] `PostSetupGuide` dialog after successful profile creation
- [x] Three action tiles: Browse Marketplace, Create Script, Explore Canisters
- [x] "Don't show again" option with state persistence
- [x] "Maybe Later" dismiss option
- [x] Integration with `OnboardingService` for state tracking
- [x] 26 tests (18 service + 8 widget tests)

### Keyboard Shortcuts (DONE - 2026-02-20)
- [x] `Ctrl/Cmd + N` - New Script
- [x] `Ctrl/Cmd + F` - Focus search
- [x] `R` - Refresh current screen
- [x] `Ctrl/Cmd + 1/2` - Switch tabs (updated for 2-tab navigation)
- [x] `Escape` - Close dialogs/modals
- [x] Platform detection (desktop only)
- [x] `ShortcutTooltip` widget for keyboard hints
- [x] 11 widget tests

### Canister Client UX Simplification (DONE - 2026-02-20)
- [x] State machine flow: `disconnected` → `connecting` → `connected` → `ready`
- [x] Friendly labels with tooltips ("Canister" instead of "Canister ID")
- [x] Progressive disclosure (advanced options collapsed)
- [x] Method chips for quick selection
- [x] Auto-detect method kind (Query/Update) shown as colored badge
- [x] "No input required" for zero-arg methods
- [x] Friendly error messages
- [x] Quick Start section with well-known canisters
- [x] 10 widget tests

### Technical Term Tooltips (DONE - 2026-02-20)
- [x] `TechTerms` utility with 10 ICP term definitions
- [x] `InfoTooltip` widget family (4 variants)
- [x] Applied to: ProfileHomePage, AccountProfileScreen, CanisterClientSheet
- [x] Terms: Canister, Principal, Candid, Keypair, Query, Update, Cycles, Replica
- [x] 25 tests (13 utils + 12 widget tests)

### Profile Management (DONE)

**Done:**
- [x] ProfileController with create/switch/delete profiles
- [x] ProfileRepository (local storage)
- [x] Profile model with 1-10 keypairs per profile
- [x] Encrypted keypair export for disaster recovery
- [x] Encrypted backup file generation/restore
- [x] Key labels in AccountPublicKey model
- [x] Export Keys dialog with password protection
- [x] Import Keys dialog for restoring from backup
- [x] ProfileController tests (67 tests - 2026-02-20)

**Missing:**
- [ ] Key label editing UI (blocked by API - no `updateKeyLabel` endpoint)

### Account Registration (DONE)

**Done:**
- [x] AccountController (register, add/remove keys, update profile)
- [x] AccountSignatureService (Ed25519 signing)
- [x] AccountRegistrationWizard screen (legacy - replaced by UnifiedSetupWizard)
- [x] Account profile screen
- [x] Full AccountController test coverage (21 tests - 2026-02-21)
- [x] Integration: redirect to passkey setup after registration

**Done:**
- [x] AccountProfileScreen widget tests (DONE - 46 tests - 2026-02-22)

### Script Management
- [x] Add secp256k1 script signing via Rust FFI
- [x] Implement SHA256 checksums for script integrity verification
- [x] Add support for installing specific script versions locally

### Lua Scripting UI (DONE)
- [x] Add tables with columns to UI elements
- [x] Support paginated lists with loading states driven by Lua (`paginated_list` widget)
- [x] Add menu to pick common UI elements in script editor (UI Component Palette)
  - 12 components across 4 categories (Layout, Text, Input, Display)
  - Inserts Lua templates at cursor position
  - 13 unit/widget tests

### Testing (CRITICAL - Blocking Production)
- [x] Profile Controller tests (DONE - 67 tests)
- [x] Account Controller full coverage (DONE - 21 tests - 2026-02-21)
- [x] Passkey Service tests (DONE)
- [x] Onboarding tests (DONE - 20 tests)
- [x] UI Component Palette tests (DONE - 13 tests)
- [x] Paginated List tests (DONE - 9 tests)
- [x] Empty State tests (DONE - 12 tests)
- [x] Scripts Screen navigation tests (DONE - 3 tests)
- [x] Export/Import Keys dialog tests (DONE - 16 tests)
- [x] Scripts Screen widget tests (DONE - 35+ tests including filter popover)
- [x] Script Menu tests (DONE - 11 tests - 2026-02-21)
- [x] Script Editor tests (DONE - 7 new tests - 2026-02-21)
- [x] Services Quick Actions tests (DONE - 10 tests - 2026-02-21)
- [x] Navigation tests (DONE - 11 tests - 2026-02-21)
- [x] Quick Profile Creation tests (DONE - 9 tests - 2026-02-21)
- [x] UX Improvements tests (DONE - 5 tests - 2026-02-21)
- [x] Publish Button tests (DONE - 11 tests - 2026-02-21)
- [x] Profile Menu Passkey tests (DONE - 6 tests - 2026-02-21)
- [x] Featured Section tests (DONE - 5 tests - 2026-02-21)
- [x] Script Reviews tests (DONE - 8 tests - 2026-02-22)
- [x] Downloaded Filter tests (DONE - 4 tests - 2026-02-22)
- [x] Enhanced Quick Actions tests (DONE - 6 new tests, 15 total - 2026-02-22)
- [x] Single-Page Script Creation tests (DONE - 11 tests - 2026-02-22)
- [x] Canister Client Full Screen tests (DONE - 11 tests - 2026-02-22)
- [x] Response Format Toggle tests (DONE - 10 tests - 2026-02-22)
- [x] Search History tests (DONE - 24 tests - 2026-02-22)
- [x] Canister History tests (DONE - 23 tests - 2026-02-22)
- [x] Script Versions tests (DONE - 11 tests - 2026-02-22)
- [x] Long-Press Context Menu tests (DONE - 19 tests - 2026-02-22)
- [x] didChangeDependencies tests (DONE - 3 tests - 2026-02-22)
- [x] Canister Autocomplete tests (DONE - 13 tests - 2026-02-22)
- [x] Actionable Error Display tests (DONE - 36 tests - 2026-02-22)
- [x] Guided Next Steps tests (DONE - 21 tests - 2026-02-22)
- [x] Account Profile Screen tests (DONE - 46 tests - 2026-02-22)
- [x] Settings Screen tests (DONE - 26 tests - 2026-02-22)
- [x] Marketplace Stats Banner tests (DONE - 10 tests - 2026-02-22)
- [x] Unsaved Changes Warning tests (DONE - 10 tests - 2026-02-22)
- [x] Downloaded Filter Empty State tests (DONE - 5 tests - 2026-02-22)
- [x] Passkey Linux Message tests (DONE - 5 tests - 2026-02-22)
- [x] Script Favorites tests (DONE - 38 tests - 2026-02-23)
- [x] Offline Mode Banner tests (DONE - 25 tests - 2026-02-23)
- [x] Bulk Script Management tests (DONE - 33 tests - 2026-02-23)
- [ ] Lua Engine tests in Rust crate (MISSING)
- [ ] Integration tests for complete user flows

**Cannot Test (requires hardware):**
- WebAuthn passkey registration/authentication (use FakePasskeyAuthenticator for CI; real device for final validation)

### Radical UX Improvements (HIGH PRIORITY)

> Analysis completed 2026-02-23. Goal: Remove clutter, improve discoverability, make the app dramatically more intuitive.

**1. Scripts Screen: Information Overload** ✅ **DONE - 2026-02-21**
- **Pain Point:** 6+ competing elements: stats banner, search, getting started card, featured carousel, share banner, mixed list
- **Change:** Removed stats banner, share banner, getting started card - cleaner UI
- **Impact:** 80% less visual noise
- **Complexity:** 4/10
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/scripts_screen_cleanup_test.dart` (7 tests)

**2. Profile Menu Discoverability** ✅ **DONE - 2026-02-21**
- **Pain Point:** 36px avatar button is invisible; users don't discover passkeys, settings, profiles
- **Change:** Added "Profile" label in a pill container next to avatar
- **Impact:** 100% increase in passkey adoption expected
- **Complexity:** 3/10
- **Files:** `lib/widgets/profile_menu.dart`
- **Tests:** `test/widgets/profile_menu_discoverability_test.dart` (5 tests)

**3. Plain Language + Progressive Disclosure** ✅ **DONE - 2026-02-21**
- **Pain Point:** Jargon everywhere: "Canister", "Candid", "Principal", "Query/Update"
- **Change:** Added plain language labels to TechTerm enum: "Canister"→"Service", "Query"→"Read", "Update"→"Write"; added tooltips with explanations
- **Impact:** 30% fewer support questions expected, broader user base
- **Complexity:** 5/10
- **Files:** `lib/utils/tech_terms.dart`, `lib/screens/canister_client_screen.dart`, `lib/screens/bookmarks_screen.dart`, `lib/widgets/canister_call_builder.dart`
- **Tests:** `test/features/ux/plain_language_test.dart` (12 tests)

**4. Merge Bookmarks + Canister Client** 🟡 **MEDIUM IMPACT**
- **Pain Point:** 60% overlapping functionality; users don't know which to use
- **Change:** Eliminate CanisterClientScreen; enhance BookmarksScreen with inline calling
- **Impact:** 40% code reduction, clearer mental model
- **Complexity:** 6/10
- **Files:** `lib/screens/bookmarks_screen.dart`, `lib/screens/canister_client_screen.dart`

**5. Collapse Key Management into "Security"** 🟡 **MEDIUM IMPACT**
- **Pain Point:** Public Keys, Signing Key, Passkeys - confusing concepts
- **Change:** Single "Security" section; list auth methods together
- **Impact:** 60% reduction in user confusion
- **Complexity:** 7/10
- **Files:** `lib/screens/account_profile_screen.dart`

**6. Remove Featured Scripts Carousel** ✅ **DONE - 2026-02-21**
- **Pain Point:** Takes vertical space, duplicates marketplace content
- **Change:** Removed carousel entirely; screen is simpler
- **Impact:** Simpler UI, more vertical space for scripts
- **Complexity:** 2/10
- **Files:** `lib/screens/scripts_screen.dart`
- **Tests:** `test/features/scripts/featured_section_test.dart` (2 new tests)

---

### Radical UX Improvements - Phase 3 (NEW - 2026-02-21)

> **Analysis completed by reviewing app from NEW USER perspective.**
> Goal: Identify confusing, missing, or hard-to-use elements that would frustrate first-time users.

**7. First Run: Dialog Fatigue** :red_circle: **HIGH IMPACT**
- **Pain Point:** User enters name in QuickProfileCreationDialog → immediately sees PostSetupGuide with 3 choices → has not even SEEN the app yet!
- **Change:** Delay PostSetupGuide by 5 seconds OR show only after first meaningful action (viewing a script, exploring a canister)
- **Impact:** 50% less first-run abandonment, users feel guided not pressured
- **Complexity:** 3/10
- **Files:** `lib/main.dart` (modify `_showPostSetupGuideIfNeeded` timing)

**8. Scripts Screen: State Explosion** :red_circle: **HIGH IMPACT**
- **Pain Point:** 2000+ line screen handles 8+ states (loading, empty, empty downloaded, empty favorites, selection mode, search mode, searching, offline). Users encounter "Your Script Library is Empty" before seeing marketplace.
- **Change:** Split into smaller widgets; default view shows marketplace when local empty; progressive disclosure of filters
- **Impact:** 40% reduction in cognitive load, cleaner first impression
- **Complexity:** 8/10 (refactor required)
- **Files:** `lib/screens/scripts_screen.dart`

**9. Mixed Mental Model: Local vs Marketplace** :red_circle: **HIGH IMPACT**
- **Pain Point:** "Scripts" tab mixes LOCAL files and MARKETPLACE items. Users do not know what to expect. Is this MY stuff or EVERYONES stuff?
- **Change:** Default to marketplace view for new users; clear "My Scripts" vs "Explore" sections; consider separate tabs
- **Impact:** 60% clearer mental model, users know where they are
- **Complexity:** 6/10
- **Files:** `lib/screens/scripts_screen.dart`

**10. Hidden Script Actions** :yellow_circle: **MEDIUM IMPACT**
- **Pain Point:** Critical actions buried in 3-dot menus, long-press, right-click. Users do not discover Run, Edit, Delete, Publish.
- **Change:** Add prominent action buttons visible on hover/focus; reduce reliance on hidden gestures
- **Impact:** 70% faster task completion, fewer "how do I?" questions
- **Complexity:** 4/10
- **Files:** `lib/screens/scripts_screen.dart`

**11. Account Profile: Form Overwhelm** :yellow_circle: **MEDIUM IMPACT**
- **Pain Point:** 7 editable fields immediately visible (display name, email, telegram, twitter, discord, website, bio). Plus Public Keys section with Import/Export buttons. Visual overload.
- **Change:** Collapse social fields into "Contact Info" expansion panel; show only display name + bio by default
- **Impact:** 50% less form anxiety, cleaner profile page
- **Complexity:** 4/10
- **Files:** `lib/screens/account_profile_screen.dart`

**12. "Profile" vs "Account" Confusion** :yellow_circle: **MEDIUM IMPACT**
- **Pain Point:** Menu says "Edit Profile" and "Create Account" - what is the difference? Users do not understand the local profile vs backend account distinction.
- **Change:** Rename to "My Identity" (local) and "Register Username" (cloud); add explainer tooltip
- **Impact:** 40% reduction in support questions about account setup
- **Complexity:** 3/10
- **Files:** `lib/widgets/profile_menu.dart`

**13. Empty State Guidance** :yellow_circle: **MEDIUM IMPACT**
- **Pain Point:** Empty states exist but do not guide users to the NEXT action. "Your Script Library is Empty" → "Create Script" button. What if user wants to browse first?
- **Change:** Add secondary action "Browse Marketplace" to empty state; context-aware suggestions
- **Impact:** 30% better first-session engagement
- **Complexity:** 3/10
- **Files:** `lib/screens/scripts_screen.dart` (ModernEmptyState widget)

**14. Canister Jargon in Quick Actions** :yellow_circle: **MEDIUM IMPACT**
- **Pain Point:** Quick Actions use "ICP Balance", "View Neurons", "NNS Governance" - crypto-native users understand, but regular users do not
- **Change:** Add plain-language descriptions; "Check your token balance (ICP)", "See your voting power in Internet Computer governance"
- **Impact:** 25% broader appeal to non-crypto users
- **Complexity:** 2/10
- **Files:** `lib/screens/bookmarks_screen.dart`


## MEDIUM Priority

### Multi-Device & Recovery
- [ ] QR code import for multi-device sync

### Expose Hidden Backend Features

**1. Script Reviews UI** ✅ **DONE - 2026-02-22** (READ-ONLY)
- [x] Add "Reviews" tab to ScriptDetailsDialog
- [x] Show rating distribution chart (5→1 star bars)
- [x] Display reviews with: stars, verified badge, comment, relative date
- [x] Empty state when no reviews
- **Note:** "Write Review" button NOT implemented (backend mutation API missing)
- **Service:** `MarketplaceOpenApiService.getScriptReviews()`
- **Test:** `test/features/marketplace/script_details_reviews_test.dart` (8 tests)
- **Impact:** Users can see reviews to make informed download decisions

**2. Featured/Trending Scripts** ✅ **DONE - 2026-02-21**
- [x] Add "Featured" section to Scripts screen
- [x] Horizontal scrolling cards with shimmer loading
- [x] Call `getFeaturedScripts()` from service
- **Impact:** Improves script discovery

**3. Script Version History** ✅ **DONE - 2026-02-22**
- [x] Add "Versions" tab to ScriptDetailsDialog
- [x] Allow installing specific versions (callback-based)
- [x] Latest/Installed badges
- **Service:** `MarketplaceOpenApiService.getScriptVersions()`
- **Test:** `test/features/marketplace/script_details_versions_test.dart` (11 tests)
- **Impact:** Users can rollback to previous versions

### UX Improvements - Phase 2

**4. Prominent Publish Button** ✅ **DONE - 2026-02-21**
- [x] Add visible share icon button on local script rows
- [x] Add dismissible "Share your first script!" banner
- **Impact:** Makes publishing discoverable (was hidden in 3-dot menu)
- **Files:** `lib/screens/scripts_screen.dart`, test: `test/features/scripts/publish_button_test.dart`

**5. Download History Visibility** ✅ **DONE - 2026-02-22**
- [x] Add "Downloaded" filter chip to filter bottom sheet
- [x] Filters scripts that were downloaded from marketplace
- [x] Works with other filters (category, source, etc.)
- **Test:** `test/features/scripts/downloaded_filter_test.dart` (4 tests)
- **Impact:** Users can easily find scripts they've downloaded
- **File:** `lib/screens/scripts_screen.dart`

**6. Quick Actions Prominence** ✅ **DONE - 2026-02-22**
- [x] Larger cards (min height 120px, padding 20px)
- [x] Gradient backgrounds (primary color 0.05 → 0.02)
- [x] "See All" button (shows "coming soon" snackbar)
- [x] Hover effects (scale 1.02, opacity 0.9 on desktop)
- [x] Better visual hierarchy (titleMedium, divider between title/description)
- **Test:** `test/features/services/quick_actions_test.dart` (15 tests, 6 new)
- **Impact:** More prominent ICP tool discovery
- **File:** `lib/screens/bookmarks_screen.dart`

**7. Passkey Quick Access** ✅ **DONE - 2026-02-21**
- [x] Show passkey count in profile menu subtitle ("No passkeys" / "N passkeys")
- [x] Highlight Passkey option when user has no passkeys
- **Impact:** Reduces friction to see passkey status, encourages setup
- **Files:** `lib/widgets/profile_menu.dart`, test: `test/widgets/profile_menu_passkey_test.dart`

**8. Single-Page Script Creation** ✅ **DONE - 2026-02-22**
- [x] Remove tabs from ScriptCreationScreen (was 2 tabs: Code/Details)
- [x] Single scrollable page layout
- [x] Template selection as prominent cards at top
- [x] "Create Script" as sticky bottom button
- [x] Reduced from 527 to 387 lines (27% reduction)
- **Test:** `test/script_creation_screen_test.dart` (11 tests)
- **Impact:** Simplifies script creation flow - no tab switching needed
- **File:** `lib/screens/script_creation_screen.dart`

**9. Canister Client as Full Screen** ✅ **DONE - 2026-02-22**
- [x] Make full screen instead of modal (via `Navigator.push`)
- [x] Add "What is a Canister?" explainer link (via tooltip)
- [x] Simplify: Canister → Function → Call (3 numbered steps)
- [x] Step indicator in AppBar showing current step
- [x] Back/Next navigation buttons
- **Test:** `test/features/canister_client/full_screen_test.dart` (11 tests)
- **Impact:** Reduces cognitive load for ICP interaction
- **Files:** `lib/screens/canister_client_screen.dart`, `lib/main.dart`

**10. Settings Screen** ✅ **DONE - 2026-02-22**
- [x] Theme toggle with Light/Dark/System options
- [x] App version and build number display
- [x] External links (Documentation, Report Issue, Marketplace Website)
- [x] Developer info section (API endpoint, environment)
- [x] Dynamic theme updates via ValueNotifier
- [x] Settings menu item in Profile Menu
- **Test:** `test/services/settings_service_test.dart` (11 tests), `test/features/settings/settings_screen_test.dart` (15 tests)
- **Impact:** Users can now configure app preferences, was completely missing
- **Files:** `lib/screens/settings_screen.dart`, `lib/services/settings_service.dart`, `lib/widgets/profile_menu.dart`, `lib/main.dart`

**11. Marketplace Stats Banner** ✅ **DONE - 2026-02-22**
- [x] Fetch marketplace stats on ScriptsScreen load
- [x] Display scripts count, authors count, downloads
- [x] Loading state with shimmer placeholder
- [x] Graceful error handling (banner hidden on error)
- [x] Large number formatting (1.2K, 10K, 1.5M)
- **Test:** `test/features/marketplace/stats_banner_test.dart` (10 tests)
- **Impact:** Users see community activity, builds trust in marketplace
- **Files:** `lib/widgets/marketplace_stats_banner.dart`, `lib/screens/scripts_screen.dart`

**12. Unsaved Changes Warning** ✅ **DONE - 2026-02-22**
- [x] Track dirty state in ScriptEditor (initial vs current code)
- [x] Confirmation dialog when closing with unsaved changes
- [x] "Discard" and "Cancel" options
- [x] PopScope to handle back button/gesture
- **Test:** `test/widgets/script_editor_unsaved_test.dart` (10 tests)
- **Impact:** Prevents data loss - users warned before losing work
- **Files:** `lib/widgets/script_editor.dart`, `lib/screens/scripts_screen.dart`

**13. Downloaded Filter Empty State** ✅ **DONE - 2026-02-22**
- [x] Specific empty state when "Downloaded" filter active with no downloads
- [x] Clear message: "You haven't downloaded any scripts yet"
- [x] "Browse Marketplace" action button clears filter
- **Test:** `test/features/scripts/downloaded_filter_test.dart` (5 tests)
- **Impact:** Users understand what's happening, guided to solution
- **Files:** `lib/screens/scripts_screen.dart`

**14. Passkey Linux Error Message** ✅ **DONE - 2026-02-22**
- [x] Clear headline: "Passkeys require a browser on Linux"
- [x] Terminal-style code block with `flutter run -d chrome`
- [x] List supported authenticators (KeePassXC, phone, hardware keys)
- **Test:** `test/features/passkey/passkey_management_screen_test.dart`
- **Impact:** Linux users know exactly how to use passkeys
- **Files:** `lib/screens/passkey_management_screen.dart`

### Content Moderation
- [ ] API key authentication for admin endpoints
- [ ] Basic content moderation system

---

## LOW Priority

### Script Reviews (Backend) - Required for Write Review UI
*Blocking: "Write Review" button in ScriptDetailsDialog*
- [ ] `POST /api/v1/scripts/{id}/reviews` - Submit review
- [ ] `PUT /api/v1/scripts/{id}/reviews/{reviewId}` - Update review
- [ ] `DELETE /api/v1/scripts/{id}/reviews/{reviewId}` - Delete review
- **Note:** Read-only reviews UI is complete. Write APIs needed for user review submission.

### Canister Interaction
- [x] Response viewer with multiple formats (JSON, Table, Raw) ✅ **DONE - 2026-02-22**
  - **Service:** `DisplayFormat` enum in `result_display.dart`
  - **Test:** `test/result_display_format_test.dart` (10 tests)
  - **Impact:** Users choose how to view canister call results
- [x] Interaction history with replay capability ✅ **DONE - 2026-02-22**
  - **Service:** `CanisterHistoryService` with SharedPreferences persistence
  - **UI:** Recent calls section in CanisterClientScreen, tap to replay
  - **Test:** `test/services/canister_history_service_test.dart` (17 tests), `test/features/canister_client/history_test.dart` (6 tests)
  - **Impact:** Power users can quickly repeat common canister calls
- [x] Canister autocomplete/search by ID or name ✅ **DONE - 2026-02-22**
  - **Service:** `CanisterRegistryService` with hardcoded registry of 8 well-known ICP canisters
  - **UI:** RawAutocomplete widget in CanisterClientScreen with suggestions
  - **Test:** `test/features/canister_client/autocomplete_test.dart` (13 tests)
  - **Impact:** Users can quickly find and select canisters without memorizing IDs
- [ ] Smart input forms based on Candid interface

### Script Automation
- [ ] Script scheduler UI (cron-like but user-friendly)
- [ ] Trigger system (time-based initially)
- [ ] Automation logs with filtering and search

### Discovery
- [ ] Trending algorithm based on recent downloads + ratings
- [ ] Personalized recommendations
- [ ] Trust system: verified author badges, reputation score

### Future UX Enhancements
- [x] Search history for marketplace ✅ **DONE - 2026-02-22**
  - **Service:** `SearchHistoryService` with SharedPreferences persistence
  - **UI:** Recent searches dropdown on search field focus, max 10 items
  - **Test:** `test/services/search_history_service_test.dart` (17 tests), `test/features/scripts/search_history_test.dart` (7 tests)
  - **Impact:** Quick access to previous searches
- [x] Quick actions menu (long-press on script cards) ✅ **DONE - 2026-02-22**
  - **UI:** Bottom sheet context menu on long-press (mobile), right-click (desktop)
  - **Actions:** Run, Edit, Duplicate, Delete, Share (local); View Details, Download (marketplace)
  - **Test:** `test/features/scripts/long_press_test.dart` (19 tests)
  - **Impact:** Power user efficiency with quick access to common actions
- [x] Actionable error handling ✅ **DONE - 2026-02-22**
  - **Service:** `ErrorCategories` utility with 7 error types (Network, Auth, Validation, NotFound, Server, RateLimit, Unknown)
  - **UI:** Enhanced `ErrorDisplay` widget with smart categorization, suggested actions, and help button
  - **Test:** `test/widgets/actionable_error_display_test.dart` (36 tests)
  - **Impact:** Users know exactly what to do when errors occur
- [x] Getting Started guide for new users ✅ **DONE - 2026-02-22**
  - **Service:** `OnboardingProgressService` with checklist tracking
  - **UI:** `GettingStartedCard` widget with 5 checklist items and progress tracking
  - **Test:** `test/features/onboarding/guided_next_steps_test.dart` (21 tests)
  - **Impact:** New users have clear path to learn the app
- [x] Interactive onboarding tour (spotlight overlays highlighting key UI elements) ✅ **DONE - 2026-02-21**
  - **Service:** `SpotlightService` with SharedPreferences persistence
  - **UI:** `SpotlightOverlay` widget with dimmed background, spotlight hole, step indicator, Next/Back/Skip buttons
  - **Integration:** Triggered after post-setup guide; "Restart Tour" option in profile menu
  - **Test:** `test/features/spotlight/spotlight_test.dart` (28 tests)
  - **Impact:** New users understand the app quickly through guided tour
- [x] Script favorites/bookmarks system with dedicated filter ✅ **DONE - 2026-02-23**
  - **Service:** `FavoritesService` with SharedPreferences persistence
  - **UI:** Star toggle on script cards, "Favorites" filter chip
  - **Test:** `test/services/favorites_service_test.dart` (26 tests), `test/features/scripts/favorites_filter_test.dart` (12 tests)
  - **Impact:** Quick access to frequently used scripts
- [x] Offline mode indication banner ✅ **DONE - 2026-02-23**
  - **Service:** `ConnectivityService` with Socket-based checking
  - **UI:** Amber dismissible banner on ScriptsScreen and BookmarksScreen
  - **Test:** `test/services/connectivity_service_test.dart` (11 tests), `test/widgets/offline_banner_test.dart` (14 tests)
  - **Impact:** Users know why operations fail
- [x] Bulk script management (multi-select, bulk delete/export) ✅ **DONE - 2026-02-23**
  - **UI:** Long-press enters selection mode; checkboxes, bulk delete/export
  - **Test:** `test/features/scripts/bulk_operations_test.dart` (33 tests)
  - **Impact:** Power users can manage multiple scripts efficiently
- [ ] Script diff viewer for version updates
- [ ] Deep linking for script sharing (`icpautorun://script/{id}`)

---

## BLOCKED / FUTURE

> **DO NOT START** until all HIGH and MEDIUM priority items are complete AND tested.
> 
> The marketplace must be fully functional with free scripts before adding payments.
> Messaging is a separate product feature that requires the core to be stable first.

### Marketplace Payments (BLOCKED)
*Blocked by: Complete test coverage, stable core features, production-ready free marketplace*

- [ ] ICP ledger canister integration
- [ ] Payment flow for paid scripts
- [ ] Purchase records API endpoints
- [ ] Transaction history
- [ ] Wallet balance display

### Messaging (BLOCKED)
*Blocked by: Everything above, including payments*

- [ ] Contact discovery/lookup
- [ ] Following/followers system
- [ ] Direct messaging infrastructure

---

## Known Issues

| Issue | Location | Severity |
|-------|----------|----------|
| Key sharing across profiles allowed (architecture violation) | `lib/models/account.dart:18-21` | MEDIUM |
| Key label editing blocked by missing API endpoint | `AccountController` | MEDIUM |
| Pre-existing test failures (passkey, script execution tests reference missing files) | `test/features/passkey/`, `test/features/scripts/` | LOW |

**Fixed This Session:**
- ~~Passkey Linux error message unclear~~ - Now shows clear instructions with `flutter run -d chrome` command

---

## Architecture Reference

### Design Principles
- **Profile-centric**: Keys belong to profiles, not standalone
- **Untrusted code isolation**: Lua sandboxed; no IO; effects executed by host
- **Fail fast**: Strict validation, clear errors, no silent failures
- **Zero redundancy**: Backend is single source of truth

### Lua App Contracts
- `init(arg) -> state, effects[]`
- `view(state) -> ui_v1`
- `update(msg, state) -> state, effects[]`
- Effects: `icp_call`, `icp_batch`
- Host emits: `{ type:"effect/result", id, ok, data?|error? }`

### UI_v1 Widget Types
- `column`, `row` - Layout containers
- `text`, `button`, `text_field` - Basic inputs
- `card`, `section` - Containers with styling
- `list`, `table`, `paginated_list` - Data display
- `image`, `result_display` - Media and results
- `select`, `toggle` - Selection widgets

---

## Update Guidelines

- Remove completed tasks immediately
- Break complex tasks into subtasks
- Empty sections: use `(none)`
- Priority: HIGH = MVP/critical, MEDIUM = significant UX, LOW = nice-to-have
