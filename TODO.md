# ICP Script Marketplace - TODO

**Last Updated:** 2026-02-19

## Current Focus

**Goal:** Polish UX and complete test coverage. Core marketplace is now user-friendly.

**Reality Check:** Major UX overhaul complete:
- Unified setup wizard (profile + account in one step)
- Flattened Scripts screen (no nested tabs, Marketplace prominent)
- Script execution progress indicator
- Pull-to-refresh on all lists
- Navigation is simpler and more intuitive
Payments and messaging are explicitly out of scope until the foundation is solid.

## Implementation Summary

| Area | Status | Completion |
|------|--------|------------|
| Unified Setup Wizard | **COMPLETE** | 100% |
| Flattened Scripts Screen | **COMPLETE** | 100% |
| Script Execution Progress | **COMPLETE** | 100% |
| Pull-to-Refresh | **COMPLETE** | 100% |
| Passkey UI Integration | **COMPLETE** | 100% |
| Linux Passkey Support | **COMPLETE** | 100% |
| Welcome Onboarding | **COMPLETE** | 100% |
| Lua Scripting UI | **COMPLETE** | 100% |
| Enhanced Empty States | **COMPLETE** | 100% |
| Encrypted Backup/Restore | **COMPLETE** | 100% |
| Download History Navigation | **COMPLETE** | 100% |
| Profile Management | Complete | 98% |
| Account Registration | Complete | 95% |
| Passkey Auth (backend) | Complete | 95% |
| Marketplace Browse/Search | Needs Testing | 90% |
| Marketplace Upload | Needs Testing | 95% |
| Script Execution (Lua) | Partial | 85% |
| Testing Coverage | Incomplete | ~75% |

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

### Profile Management

**Done:**
- [x] ProfileController with create/switch/delete profiles
- [x] ProfileRepository (local storage)
- [x] Profile model with 1-10 keypairs per profile
- [x] Encrypted keypair export for disaster recovery
- [x] Encrypted backup file generation/restore
- [x] Key labels in AccountPublicKey model
- [x] Export Keys dialog with password protection
- [x] Import Keys dialog for restoring from backup

**Missing:**
- [ ] ProfileController tests (MISSING - critical)
- [ ] Key label editing UI (blocked by API - no `updateKeyLabel` endpoint)

### Account Registration

**Done:**
- [x] AccountController (register, add/remove keys, update profile)
- [x] AccountSignatureService (Ed25519 signing)
- [x] AccountRegistrationWizard screen (legacy - replaced by UnifiedSetupWizard)
- [x] Account profile screen

**Missing:**
- [ ] Full AccountController test coverage (only `removePublicKey` tested)
- [ ] AccountProfileScreen widget tests
- [x] Integration: redirect to passkey setup after registration

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
- [ ] Profile Controller tests (MISSING)
- [ ] Account Controller full coverage (only `removePublicKey` tested)
- [x] Passkey Service tests (DONE)
- [x] Onboarding tests (DONE - 20 tests)
- [x] UI Component Palette tests (DONE - 13 tests)
- [x] Paginated List tests (DONE - 9 tests)
- [x] Empty State tests (DONE - 12 tests)
- [x] Scripts Screen navigation tests (DONE - 3 tests)
- [x] Export/Import Keys dialog tests (DONE - 16 tests)
- [x] Scripts Screen widget tests (DONE - 7 unified view tests)
- [ ] Lua Engine tests in Rust crate (MISSING)
- [ ] Account Profile Screen tests (MISSING)
- [ ] Bookmarks Screen tests (MISSING)
- [ ] Integration tests for complete user flows

**Cannot Test (requires hardware):**
- WebAuthn passkey registration/authentication (use FakePasskeyAuthenticator for CI; real device for final validation)

---

## MEDIUM Priority

### Multi-Device & Recovery
- [ ] QR code import for multi-device sync

### UX Improvements (ONGOING)
Based on comprehensive UX analysis (2026-02-19):

**Completed:**
- [x] Create hybrid view combining local and marketplace scripts
- [x] Add source badges (Local/Marketplace) to distinguish origins
- [x] Display usage statistics (run count, last used)
- [x] Welcome onboarding flow for first-time users
- [x] Enhanced empty states with contextual guidance
- [x] Rename "Bookmarks" nav to "Explorer" (matches screen title)
- [x] Add Download History navigation from Scripts screen
- [x] Add Export/Import Keys buttons for disaster recovery
- [x] Flatten Scripts tab (remove nested tabs, elevate Marketplace)
- [x] Streamline profile creation (combine profile + account creation)
- [x] Script execution progress indicator
- [x] Pull-to-refresh on all list views

**Remaining (from UX analysis):**
- [ ] Post-onboarding call-to-action (guide users after profile creation)
- [ ] Rename "Explorer" tab to something more approachable (e.g., "Tools" or "Services")
- [ ] Simplify Canister Client Sheet (too many fields, technical jargon)
- [ ] Add tooltips/explanations for technical terms (canister, principal, candid)
- [ ] Reduce script item menu options (currently 7+ options)
- [ ] Keyboard shortcuts for desktop users

### Content Moderation
- [ ] API key authentication for admin endpoints
- [ ] Basic content moderation system

---

## LOW Priority

### Script Reviews
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
| Pre-existing test failures (passkey, script execution) | `test/features/passkey/`, `test/features/scripts/` | LOW |
| Dead code in scripts_screen.dart (unused methods from refactor) | `lib/screens/scripts_screen.dart` | LOW |

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
