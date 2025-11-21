# Profile-Centric Architecture Migration - Remaining Tasks

**Status:** ✅ COMPLETE - All phases done
**Date:** 2025-11-21 (completed)

## ✅ Completed

### Core Architecture
- [x] Profile model created (`lib/models/profile.dart`)
- [x] ProfileKeypair model (renamed from IdentityRecord with typedef)
- [x] ProfileRepository for profile-centric storage
- [x] ProfileController for profile management
- [x] IdentityController refactored as compatibility wrapper
- [x] AccountController fixed (cross-profile violations eliminated)
- [x] Test infrastructure updated (FakeSecureIdentityRepository with profile support)
- [x] All 441 tests passing
- [x] Production code deprecation warnings suppressed with `// ignore`

### Documentation
- [x] ACCOUNT_PROFILES_DESIGN.md updated with profile-centric model
- [x] ACCOUNT_PROFILES_UX_DESIGN.md updated with profile concepts
- [x] AGENTS.md updated with architecture notes
- [x] FIXME comments added throughout codebase marking violations
- [x] This MIGRATION_TODO.md file created

### UI Migration (Phase 2 - Partial)
- [x] ProfileScope widget created (`lib/widgets/profile_scope.dart`)
- [x] ProfileHomePage implemented (`lib/screens/profile_home_page.dart`)
- [x] main.dart updated to use ProfileController and ProfileHomePage
- [x] AddAccountKeySheet simplified (removed "Use existing identity" option)
- [x] All existing tests still passing

## ✅ Completed Phases

### Phase 1: Update Test Files - ✅ COMPLETE
Deprecation warnings in test files have been suppressed with `// ignore` comments.
These tests validate backward compatibility and will be removed in Phase 3.

**Completed:**
- `test/controllers/account_controller_test.dart` - All deprecation warnings suppressed
  - `accountForIdentity` usage (lines 125, 192) - ignored
  - `addPublicKey` usage (lines 317, 351, 384, 418) - ignored

**Effort:** Low (completed)
**Impact:** Low (no analyzer warnings)

### Phase 2: UI Migration to Profile-Centric (COMPLETE)

**Completed:**
- ✅ `lib/screens/profile_home_page.dart` - New profile-centric home page
- ✅ `lib/widgets/profile_scope.dart` - ProfileController dependency injection
- ✅ `lib/main.dart` - Uses ProfileController and ProfileHomePage
- ✅ `lib/widgets/add_account_key_sheet.dart` - Uses `addKeypairToAccount()` with Profile
- ✅ `lib/screens/account_profile_screen.dart` - Receives Profile parameter

**Effort:** Complete
**Impact:** High (profile-centric UI)

### Phase 3: Remove Compatibility Layers - ✅ COMPLETE

1. **IdentityController wrapper** - ✅ DELETED
   - Migrated all code to ProfileController
   - Deleted `lib/controllers/identity_controller.dart`

2. **IdentityScope widget** - ✅ DELETED
   - All widgets now use ProfileScope
   - Deleted `lib/widgets/identity_scope.dart`

3. **IdentityHomePage** - ✅ DELETED
   - ProfileHomePage is now the home page
   - Deleted `lib/screens/identity_home_page.dart`

4. **Widget migrations completed:**
   - `quick_upload_dialog.dart` → ProfileController
   - `script_upload_screen.dart` → ProfileController
   - `identity_session_banner.dart` → ProfileController
   - `identity_switcher_sheet.dart` → ProfileController (now shows profiles, not keypairs)

5. **Test file migrations completed:**
   - `test/widgets/quick_upload_dialog_test.dart`
   - `test/script_upload_screen_test.dart`
   - `test/screens/script_upload_screen_test.dart`

6. **Deprecated AccountController methods removed:**
   - `addPublicKey` - deleted
   - `accountForIdentity` - deleted
   - `getAccountForIdentity` - deleted
   - `fetchAccountForIdentity` - deleted
   - Tests for deprecated methods deleted (6 tests removed)
   - Unused imports cleaned up

**Remaining:**
- IdentityRecord typedef kept for convenience (maps to ProfileKeypair)

**Effort:** Complete
**Impact:** High (clean profile-centric architecture)

## 📋 Summary

All migration phases are complete. The codebase is now profile-centric:
- `ProfileController` manages profiles
- `ProfileHomePage` is the main UI entry point
- `ProfileScope` provides dependency injection
- `IdentityRecord` typedef kept for convenience (maps to ProfileKeypair)

## 🎯 Success Criteria

### Phase 1 Complete When:
- [x] No deprecation warnings in test files
- [x] All tests still passing

### Phase 2 Complete When:
- [x] UI works entirely with Profile objects
- [x] No use of deprecated methods (ignores removed)
- [x] Profile list shows profiles, not individual keypairs
- [x] Adding keys generates within profile (no importing)
- [x] All tests updated and passing
- [x] No regression in functionality

### Phase 3 Complete When:
- [x] IdentityController deleted
- [x] IdentityScope deleted
- [x] IdentityHomePage deleted
- [x] All widgets use ProfileController
- [x] Documentation updated
- [x] All 441 tests passing

## 📝 Notes

### Why Suppress Warnings Instead of Full Migration?
1. **Core architecture is solid** - profile-centric model is implemented
2. **Tests all pass** - no functional issues
3. **UI migration is separate concern** - can be done incrementally
4. **Backward compatibility** - old code still works perfectly
5. **Time management** - focus on architecture first, UI later

### Key Architectural Principles (Must Maintain)
- ✅ Profile → Keypairs (tree structure, not graph)
- ✅ No key sharing across profiles
- ✅ 1:1 Profile-Account mapping
- ✅ Keypairs generated within profile (never imported)
- ✅ Complete profile isolation

### Testing Strategy
1. Write tests for ProfileHomePage before implementation
2. Test profile CRUD operations
3. Test keypair generation within profile
4. Test profile-account registration flow
5. Test error cases (max 10 keys, etc.)

## 🚀 Migration Complete

All phases finished. The profile-centric architecture is fully implemented.

**Remaining documentation FIXMEs in lib/ are intentional markers** describing architecture notes
for future reference (not blocking issues).

## 📚 References

- `ACCOUNT_PROFILES_DESIGN.md` - Backend specification
- `ACCOUNT_PROFILES_UX_DESIGN.md` - Frontend UX design
- `AGENTS.md` - Project architecture notes
- `lib/controllers/profile_controller.dart` - Main controller implementation
- `lib/models/profile.dart` - Profile data model
