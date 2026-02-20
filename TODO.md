# ICP Script Marketplace - TODO

**Last Updated:** 2026-02-21 (evening session)

## Current Focus

**Goal:** Polish UX and complete test coverage. Core marketplace is now user-friendly.

**Reality Check:** Major UX overhaul complete:
- **NEW:** 2-Tab navigation (Home, Discover) with Profile menu in app bar
- **NEW:** Simplified first-run experience (just "What's your name?")
- **NEW:** Services renamed to "Explore" with subtitle
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

**Next Wave:** Expose hidden backend features (reviews, featured scripts, trending).

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
| Account Registration | Complete | 100% |
| Passkey Auth (backend) | Complete | 95% |
| Marketplace Browse/Search | Needs Testing | 90% |
| Marketplace Upload | Needs Testing | 95% |
| Script Execution (Lua) | Partial | 85% |
| Testing Coverage | Improved | ~90% |

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

**Missing:**
- [ ] AccountProfileScreen widget tests

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
- [ ] Lua Engine tests in Rust crate (MISSING)
- [ ] Account Profile Screen tests (MISSING)
- [ ] Integration tests for complete user flows

**Cannot Test (requires hardware):**
- WebAuthn passkey registration/authentication (use FakePasskeyAuthenticator for CI; real device for final validation)

---

## MEDIUM Priority

### Multi-Device & Recovery
- [ ] QR code import for multi-device sync

### Expose Hidden Backend Features

**1. Script Reviews UI** ⭐ MEDIUM IMPACT, MEDIUM EFFORT
- [ ] Add "Reviews" tab to ScriptDetailsDialog
- [ ] Show rating distribution chart
- [ ] Add "Write Review" button for downloaded scripts
- **Service:** `MarketplaceOpenApiService.getScriptReviews()`
- **Impact:** Users can make informed decisions about scripts

**2. Featured/Trending Scripts** ⭐ MEDIUM IMPACT, LOW EFFORT
- [ ] Add "Featured" section to Scripts screen
- [ ] Call `getFeaturedScripts()` and `getTrendingScripts()`
- **Service:** `MarketplaceOpenApiService.getFeaturedScripts()`
- **Impact:** Improves script discovery

**3. Script Version History** ⭐ LOW IMPACT, MEDIUM EFFORT
- [ ] Add "Versions" tab to ScriptDetailsDialog
- [ ] Allow installing specific versions
- **Service:** `MarketplaceOpenApiService.getScriptVersions()`
- **Impact:** Users can rollback to previous versions

### UX Improvements - Phase 2

**4. Prominent Publish Button** ⭐ HIGH IMPACT, LOW EFFORT
- [ ] Add "Share to Marketplace" FAB or banner when viewing local scripts
- [ ] Show publish count on scripts screen ("Share your first script!")
- **Impact:** Makes publishing discoverable (currently hidden in 3-dot menu)
- **File:** `lib/screens/scripts_screen.dart`

**5. Download History Visibility** ⭐ MEDIUM IMPACT, LOW EFFORT
- [ ] Add "Recent Downloads" section at top of Scripts list
- [ ] Or add filter chip: "All | Local | Marketplace | Downloaded"
- **Impact:** Users can find their downloaded scripts easily
- **File:** `lib/screens/scripts_screen.dart`

**6. Quick Actions Prominence** ⭐ MEDIUM IMPACT, LOW EFFORT
- [ ] Make Quick Actions cards larger with gradient backgrounds
- [ ] Add "See All" link to expanded view
- **Impact:** Increases discoverability of ICP tools
- **File:** `lib/screens/bookmarks_screen.dart`

**7. Passkey Quick Access** ⭐ HIGH IMPACT, LOW EFFORT
- [ ] Add "Add Passkey" button to profile menu (before needing to view account)
- [ ] Show passkey status on main profile menu
- **Impact:** Reduces 4+ taps to add passkey
- **File:** `lib/widgets/profile_menu.dart`

**8. Single-Page Script Creation** ⭐ HIGH IMPACT, MEDIUM EFFORT
- [ ] Remove tabs from ScriptCreationScreen
- [ ] Single scrollable page with code editor at top
- [ ] Template selection as prominent cards, not dropdown
- [ ] "Create Script" as sticky bottom button
- **Impact:** Simplifies script creation flow
- **File:** `lib/screens/script_creation_screen.dart`

**9. Canister Client as Full Screen** ⭐ MEDIUM IMPACT, MEDIUM EFFORT
- [ ] Make full screen instead of modal
- [ ] Add "What is a Canister?" explainer link
- [ ] Simplify: Canister → Function → Call (3 numbered steps)
- **Impact:** Reduces cognitive load for ICP interaction
- **File:** `lib/screens/bookmarks_screen.dart`

### Content Moderation
- [ ] API key authentication for admin endpoints
- [ ] Basic content moderation system

---

## LOW Priority

### Script Reviews (Backend)
- [ ] `POST /api/v1/scripts/{id}/reviews` - Submit review
- [ ] `PUT /api/v1/scripts/{id}/reviews/{reviewId}` - Update review
- [ ] `DELETE /api/v1/scripts/{id}/reviews/{reviewId}` - Delete review

### Canister Interaction
- [ ] Canister autocomplete/search by ID or name
- [ ] Smart input forms based on Candid interface
- [ ] Response viewer with multiple formats (JSON, Table, Raw)
- [ ] Interaction history with replay capability

### Script Automation
- [ ] Script scheduler UI (cron-like but user-friendly)
- [ ] Trigger system (time-based initially)
- [ ] Automation logs with filtering and search

### Discovery
- [ ] Trending algorithm based on recent downloads + ratings
- [ ] Personalized recommendations
- [ ] Trust system: verified author badges, reputation score

### Future UX Enhancements
- [ ] Search history for marketplace
- [ ] Quick actions menu (long-press on script cards)

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
| ProfileController.ensureLoaded() called during didChangeDependencies causes setState during build errors in tests | `lib/main.dart:134-138` | LOW |

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
