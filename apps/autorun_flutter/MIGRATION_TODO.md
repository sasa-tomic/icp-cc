# Profile-Centric Architecture Migration - Remaining Tasks

**Status:** Core architecture complete, UI migration pending
**Date:** 2025-11-21

## ✅ Completed

### Core Architecture
- [x] Profile model created (`lib/models/profile.dart`)
- [x] ProfileKeypair model (renamed from IdentityRecord with typedef)
- [x] ProfileRepository for profile-centric storage
- [x] ProfileController for profile management
- [x] IdentityController refactored as compatibility wrapper
- [x] AccountController fixed (cross-profile violations eliminated)
- [x] Test infrastructure updated (FakeProfileRepository, etc.)
- [x] All 447 tests passing
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

## 🔄 In Progress / Next Steps

### Phase 1: Update Test Files (Low Priority)
Tests are currently using deprecated methods but all pass. Can be updated when convenient.

**Files:**
- `test/controllers/account_controller_test.dart` (3 uses of deprecated `addPublicKey`)
  - Lines: 315, 347, 379, 412
  - Need to mock ProfileController and use `addKeypairToAccount`

**Effort:** Low (1-2 hours)
**Impact:** Low (tests already passing, just warnings)

### Phase 2: UI Migration to Profile-Centric (MOSTLY COMPLETE)

**Completed:**
- ✅ `lib/screens/profile_home_page.dart` - New profile-centric home page
- ✅ `lib/widgets/profile_scope.dart` - ProfileController dependency injection
- ✅ `lib/main.dart` - Uses ProfileController and ProfileHomePage
- ✅ `lib/widgets/add_account_key_sheet.dart` - Removed "import existing identity" option

**Remaining Work:**
1. **`lib/screens/account_registration_wizard.dart`**
   - Update to work with Profile context instead of raw IdentityRecord
   - Should update Profile.username after successful registration

2. **`lib/screens/account_profile_screen.dart`**
   - Update to receive Profile parameter
   - Use `addKeypairToAccount()` instead of deprecated `addPublicKey()`

3. **Remove old files when stable:**
   - `lib/screens/identity_home_page.dart` - Replaced by ProfileHomePage
   - `lib/widgets/identity_scope.dart` - Only needed for backward compatibility

**Effort:** Medium (1 day)
**Impact:** Medium (completes profile-centric UI)

### Phase 3: Remove Compatibility Layers (Future)
Once UI is fully migrated to profiles:

1. **Remove IdentityController wrapper**
   - Update all code to use ProfileController directly
   - Remove backward compatibility methods

2. **Remove SecureIdentityRepository wrapper**
   - Update all code to use ProfileRepository directly
   - Remove conversion logic

3. **Remove deprecated methods from AccountController**
   - Delete `accountForIdentity()`
   - Delete `addPublicKey()`
   - Keep only profile-centric methods

4. **Remove IdentityRecord typedef**
   - Rename all uses to ProfileKeypair
   - Delete identity_record.dart entirely

**Effort:** Medium (1-2 days)
**Impact:** High (clean architecture, removes technical debt)

## 📋 Detailed Task Breakdown

### UI Migration (Phase 2) - Step by Step

#### 1. Create ProfileHomePage (New File)
**File:** `lib/screens/profile_home_page.dart`

**Features:**
- List all profiles (not individual keypairs)
- Show profile metadata (name, @username, key count)
- Tap profile → show profile details with all keypairs
- Add profile button → create new profile wizard
- Profile menu: Rename, Delete, Manage keys

**Dependencies:**
- ProfileController
- AccountController
- ProfileScope (new widget)

#### 2. Update IdentityHomePage (Gradual Migration)
**File:** `lib/screens/identity_home_page.dart`

**Changes:**
- Replace `accountForIdentity()` calls with:
  ```dart
  // Old:
  final account = _accountController.accountForIdentity(record);

  // New:
  final profile = _profileController.findByKeypairId(record.id);
  final account = profile?.username != null
      ? await _accountController.getAccountForProfile(profile!)
      : null;
  ```

**Notes:**
- Need access to ProfileController
- More complex lookups (keypair → profile → account)
- Consider if it's worth migrating vs. creating new ProfileHomePage

#### 3. Update AddAccountKeySheet
**File:** `lib/widgets/add_account_key_sheet.dart`

**Changes:**
- Remove "Use existing identity" option entirely
- Update "Generate new keypair" flow:
  ```dart
  // Old:
  final newIdentity = await _identityController.createIdentity(...);
  final newKey = await _accountController.addPublicKey(
    username: account.username,
    signingIdentity: signingIdentity,
    newIdentity: newIdentity,
  );

  // New:
  final newKey = await _accountController.addKeypairToAccount(
    profile: currentProfile,
    algorithm: selectedAlgorithm,
    keypairLabel: 'Device key',
  );
  ```

**Dependencies:**
- Need current Profile object
- Need ProfileController reference
- Remove identity selection dropdown

#### 4. Create ProfileScope Widget
**File:** `lib/widgets/profile_scope.dart`

**Purpose:**
- Provide ProfileController to widget tree
- Similar to current IdentityScope
- Wraps app or specific screens

**Implementation:**
```dart
class ProfileScope extends InheritedWidget {
  final ProfileController controller;

  static ProfileController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    assert(scope != null, 'No ProfileScope found in context');
    return scope!.controller;
  }

  // ...
}
```

### Migration Strategy

**Option A: Big Bang (Recommended)**
1. Create new ProfileHomePage from scratch
2. Update main.dart to use ProfileHomePage instead
3. Keep old IdentityHomePage for reference
4. Delete old code once new code is stable

**Option B: Gradual Migration**
1. Update IdentityHomePage piece by piece
2. Add ProfileController alongside IdentityController
3. Migrate each feature individually
4. More complex, higher risk of bugs

**Recommendation:** Option A - cleaner, faster, easier to test

## 🎯 Success Criteria

### Phase 1 Complete When:
- [ ] No deprecation warnings in test files
- [ ] All tests still passing

### Phase 2 Complete When:
- [ ] UI works entirely with Profile objects
- [ ] No use of deprecated methods (ignores removed)
- [ ] Profile list shows profiles, not individual keypairs
- [ ] Adding keys generates within profile (no importing)
- [ ] All tests updated and passing
- [ ] No regression in functionality

### Phase 3 Complete When:
- [ ] IdentityController deleted
- [ ] SecureIdentityRepository deleted (or minimal wrapper)
- [ ] All compatibility layers removed
- [ ] Clean architecture with no technical debt
- [ ] Documentation updated
- [ ] All tests passing

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

## 🚀 Getting Started

To continue the migration:

```bash
# 1. Create new ProfileHomePage
touch lib/screens/profile_home_page.dart

# 2. Write tests first
touch test/screens/profile_home_page_test.dart

# 3. Implement ProfileScope
touch lib/widgets/profile_scope.dart

# 4. Update main.dart when ready
# Change: IdentityHomePage() → ProfileHomePage()
```

## 📚 References

- `ACCOUNT_PROFILES_DESIGN.md` - Backend specification
- `ACCOUNT_PROFILES_UX_DESIGN.md` - Frontend UX design
- `AGENTS.md` - Project architecture notes
- `lib/controllers/profile_controller.dart` - Main controller implementation
- `lib/models/profile.dart` - Profile data model
