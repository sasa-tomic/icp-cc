# Test Coverage Gaps

**Last Updated:** 2025-02-15

## Summary

| Category | Files | Has Tests | Missing |
|----------|-------|-----------|---------|
| Controllers | 3 | 1 | 2 |
| Services | 10+ | 8 | 2+ |
| Screens | 7 | 3 | 4 |
| Widgets | 20+ | 10 | 10+ |
| Models | 10+ | 2 | 8+ |
| Rust (icp_core) | 7 | 5 | 2 |

---

## High Priority Gaps

### Controllers (CRITICAL)

| Controller | Status | Notes |
|------------|--------|-------|
| `ProfileController` | **MISSING** | Critical state management |
| `ScriptController` | **MISSING** | Critical state management |
| `AccountController` | Partial | Only `removePublicKey` tested |

### Services

| Service | Status | Notes |
|---------|--------|-------|
| `PasskeyService` | **MISSING** | New feature, 0 tests |
| `ProfileRepository` | **MISSING** | Data persistence layer |
| `ScriptValidationService` | **MISSING** | Validation logic |

### Screens (Widget Tests)

| Screen | Lines | Status | Notes |
|--------|-------|--------|-------|
| `ScriptsScreen` | 1844 | **MISSING** | Largest screen, 0 tests |
| `AccountProfileScreen` | ~600 | **MISSING** | Profile editing |
| `BookmarksScreen` | ~1000 | **MISSING** | Canister bookmarks |
| `DownloadHistoryScreen` | ~200 | **MISSING** | History display |
| `ProfileHomePage` | ~400 | **MISSING** | Main entry point |

### Rust (icp_core crate)

| Module | Status | Notes |
|--------|--------|-------|
| `lua_engine` | **MISSING** | Core execution engine |
| `wasm_exports` | **MISSING** | FFI boundary |
| `ffi` | **MISSING** | Native bridge |

---

## Medium Priority Gaps

### Models

| Model | Status | Notes |
|-------|--------|-------|
| `Profile` | **MISSING** | Core data structure |
| `Account` | **MISSING** | User account |
| `CanisterMethod` | **MISSING** | Canister interaction |
| `PurchaseRecord` | **MISSING** | Purchases |
| `MarketplaceUser` | **MISSING** | Marketplace profile |

### Widgets

| Widget | Status | Notes |
|--------|--------|-------|
| `ScriptAppHost` | Partial | Permission tests only |
| `empty_state` | **MISSING** | Simple |
| `error_display` | **MISSING** | Simple |
| `loading_indicator` | **MISSING** | Simple |
| `shimmer` | **MISSING** | Simple |
| `animated_fab` | **MISSING** | Simple |
| `page_transitions` | **MISSING** | Simple |

### Services

| Service | Status | Notes |
|---------|--------|-------|
| `CandidService` | **MISSING** | Candid parsing |

---

## Good Coverage Areas

### Well-Tested

| Component | Test File | Lines | Quality |
|-----------|-----------|-------|---------|
| Script Runner | `script_runner_test.dart` | 399 | Excellent |
| Script Signature | `script_signature_service_test.dart` | 304 | Excellent |
| Authentication | `authentication_test.dart` | - | Comprehensive |
| Marketplace API | `marketplace_open_api_service_test.dart` | 449 | Good |
| Script Card | `script_card_keypair_test.dart` | - | Good |
| Account Controller | `account_controller_test.dart` | - | Partial |

### Test Infrastructure (Excellent)

- `TestKeypairFactory` - Real keypairs for testing
- `TestSignatureUtils` - Cryptographic signing helpers
- `FakeSecureKeypairRepository` - In-memory storage
- `MockMarketplaceOpenApiService` - API mocking

---

## Backend Test Gaps

| Area | Status | Notes |
|------|--------|-------|
| Auth/Signature | Covered | Inline unit tests |
| Vault | Covered | Inline unit tests |
| Script Service | Covered | Inline unit tests |
| **Database Operations** | **MISSING** | No integration tests |
| **API Endpoints** | **MISSING** | No E2E tests |

---

## Recommendations

### Immediate (Next Sprint)
1. Add `ProfileController` tests
2. Add `ScriptController` tests
3. Add widget tests for `ScriptsScreen`
4. Add unit tests for `PasskeyService`

### Short-term
1. Add Rust tests for `lua_engine`
2. Add widget tests for `AccountProfileScreen`
3. Add widget tests for `BookmarksScreen`
4. Add model tests for `Profile`, `Account`

### Long-term
1. Backend integration tests for API endpoints
2. E2E tests for complete user flows
3. Performance tests for Lua execution

---

## Test Quality Standards

Per `AGENTS.md`:
- Every function must be covered by at least one test
- Tests MUST assert meaningful behavior
- Tests MAY NOT overlap coverage
- Must cover both positive and negative paths
- Must use real cryptography (no mock signatures)
- Backend unavailability must cause test FAILURE
