# ICP Script Marketplace - TODO

**Last Updated:** 2025-02-15

## Current Focus

**Goal:** Make marketplace and scripts fully usable (free scripts only) with comprehensive test coverage.

**Reality Check:** The marketplace is NOT production-ready. Core features lack tests, screens are untested, and the script execution flow needs work. Payments and messaging are explicitly out of scope until the foundation is solid.

## Implementation Summary

| Area | Status | Completion |
|------|--------|------------|
| Profile Management | Complete | 95% |
| Account Registration | Complete | 95% |
| Passkey Auth | Complete | 95% |
| Marketplace Browse/Search | Needs Testing | 90% |
| Marketplace Upload | Needs Testing | 95% |
| Script Execution (Lua) | Partial | 80% |
| Testing Coverage | Incomplete | ~60% |

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

**Remaining (for full production):**
- [ ] Client-side vault decryption via Rust FFI (Argon2id + AES-GCM)
- [ ] Integration flow: prompt passkey setup after account registration
- [ ] E2E tests on real device (WebAuthn requires hardware authenticator)

### Profile Management

**Done:**
- [x] ProfileController with create/switch/delete profiles
- [x] ProfileRepository (local storage)
- [x] Profile model with 1-10 keypairs per profile

**Missing:**
- [ ] ProfileController tests (MISSING - critical)
- [ ] Add key labels (e.g., "Mobile", "Desktop") to `account_public_keys` table

### Account Registration

**Done:**
- [x] AccountController (register, add/remove keys, update profile)
- [x] AccountSignatureService (Ed25519 signing)
- [x] AccountRegistrationWizard screen
- [x] Account profile screen

**Missing:**
- [ ] Full AccountController test coverage (only `removePublicKey` tested)
- [ ] AccountProfileScreen widget tests
- [ ] Integration: redirect to passkey setup after registration

### Script Management
- [ ] Add secp256k1 script signing via Rust FFI (throws `UnimplementedError` in `script_signature_service.dart:163`)
- [ ] Implement SHA256 checksums for script integrity verification
- [ ] Add support for installing specific script versions locally

### Lua Scripting UI
- [ ] Add tables with columns to UI elements
- [ ] Support paginated lists with loading states driven by Lua
- [ ] Add menu to pick common UI elements in script editor

### Testing (CRITICAL - Blocking Production)
- [ ] Profile Controller tests (MISSING)
- [ ] Account Controller full coverage (only `removePublicKey` tested)
- [x] Passkey Service tests (DONE)
- [ ] Scripts Screen widget tests (MISSING - largest screen, 0 tests)
- [ ] Lua Engine tests in Rust crate (MISSING)
- [ ] Account Profile Screen tests (MISSING)
- [ ] Bookmarks Screen tests (MISSING)
- [ ] Integration tests for complete user flows

**Cannot Test (requires hardware):**
- WebAuthn passkey registration/authentication (needs real authenticator)

---

## MEDIUM Priority

### Multi-Device & Recovery
- [ ] QR code import for multi-device sync
- [ ] Encrypted keypair export for disaster recovery
- [ ] Encrypted backup file generation/restore

### UX Improvements
- [ ] Create hybrid view combining local and marketplace scripts
- [ ] Add source badges (Local/Marketplace) to distinguish origins
- [ ] Display usage statistics (run count, last used)

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
| secp256k1 script signing throws `UnimplementedError` | `lib/services/script_signature_service.dart:163` | HIGH |
| Key sharing across profiles allowed (architecture violation) | `lib/models/account.dart:18-21` | MEDIUM |
| Returns empty arrays on connection failure (anti-pattern) | `lib/services/marketplace_open_api_service.dart:168,196` | MEDIUM |

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

---

## Update Guidelines

- Remove completed tasks immediately
- Break complex tasks into subtasks
- Empty sections: use `(none)`
- Priority: HIGH = MVP/critical, MEDIUM = significant UX, LOW = nice-to-have
