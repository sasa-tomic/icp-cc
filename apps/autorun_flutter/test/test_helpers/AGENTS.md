# Test Helpers - Agent Instructions

## Overview

This directory contains standardized test utilities for testing ICP AutoRun functionality. All tests MUST use these helpers to ensure consistency, real cryptographic signatures, and DRY principles.

## Core Testing Principles

### FAIL FAST - No Fallbacks in Tests
- Tests MUST fail immediately when infrastructure isn't available
- NO offline modes, NO mock fallbacks, NO silent failures
- If backend/Cloudflare Workers can't start, tests MUST fail
- Issues must be detected EARLY, not hidden behind "graceful degradation"

### Real Cryptography Required
- ALL tests communicating with the backend MUST use real cryptographic keypairs
- NO hardcoded mock signatures
- NO fake keys (e.g., `base64Encode(List.filled(32, 1))`)
- Use `TestKeypairFactory` for all keypair creation

### DRY Principle
- NEVER duplicate test helper code
- Use centralized helpers from this directory
- If you find yourself writing similar test setup code, extract it to a helper

## Standard Test Helpers

### 1. TestKeypairFactory (`test_keypair_factory.dart`)

**Purpose:** Create deterministic test keypairs with real cryptographic keys

**When to use:**
- Any test that needs to authenticate with the backend
- Tests that verify signature validation
- Tests that need multiple distinct keypairs

**Usage:**

```dart
import 'package:flutter_test/flutter_test.dart';
import '../test_helpers/test_keypair_factory.dart';

void main() {
  test('example test', () async {
    // Get the default test keypair (cached, consistent across tests)
    final keypair = await TestKeypairFactory.getEd25519Keypair();

    // Or create keypairs from seeds for multiple users
    final user1 = await TestKeypairFactory.fromSeed(1);
    final user2 = await TestKeypairFactory.fromSeed(2);

    // Use the keypair...
    final principal = PrincipalUtils.textFromRecord(keypair);
  });
}
```

**Key Methods:**
- `getEd25519Keypair()` - Get default Ed25519 test keypair (cached)
- `getSecp256k1Keypair()` - Get default secp256k1 test keypair (cached)
- `fromSeed(int seed)` - Generate deterministic keypair from seed
- `getKeypair(KeyAlgorithm algorithm)` - Get keypair by algorithm

**Important Notes:**
- All keypairs are cached for performance
- Same seed always produces the same keypair
- Generated keypairs use real BIP39 mnemonics
- Supports both Ed25519 and secp256k1 algorithms

### 2. TestSignatureUtils (`test_signature_utils.dart`)

**Purpose:** Generate real cryptographic signatures for backend communication

**When to use:**
- Tests that upload/update/delete scripts
- Tests that verify signature validation
- Any test that sends signed requests to the backend

**Setup (Required):**

```dart
void main() {
  setUpAll(() async {
    // Initialize once before all tests in the file
    await TestSignatureUtils.ensureInitialized();
  });

  test('example test', () {
    // Now you can use synchronous methods
    final signature = TestSignatureUtils.generateTestSignatureSync(payload);
    final principal = TestSignatureUtils.getPrincipal();
  });
}
```

**OR use global test config (Recommended):**

The project has a global `flutter_test_config.dart` that auto-initializes test signatures before all tests run. No manual initialization needed!

**Key Methods:**
- `generateTestSignatureSync(Map<String, dynamic> payload)` - Generate signature (sync, requires initialization)
- `generateTestSignature(Map<String, dynamic> payload)` - Generate signature (async)
- `getPrincipal()` - Get test principal (sync)
- `getPublicKey()` - Get test public key (sync)
- `getPrivateKey()` - Get test private key (sync)
- `createTestScriptRequest({Map<String, dynamic>? overrides})` - Create complete script upload request
- `createTestUpdateRequest(String scriptId, {Map<String, dynamic>? updates})` - Create script update request
- `createTestDeleteRequest(String scriptId)` - Create script delete request

**Usage Examples:**

```dart
// Create a complete upload request
final request = TestSignatureUtils.createTestScriptRequest(
  overrides: {
    'title': 'Custom Title',
    'description': 'Custom description',
  },
);

// Create update request
final updateRequest = TestSignatureUtils.createTestUpdateRequest(
  'script-id-123',
  updates: {'title': 'New Title'},
);

// Generate custom signature
final payload = {
  'action': 'upload',
  'title': 'Test Script',
  'timestamp': DateTime.now().toIso8601String(),
};
final signature = TestSignatureUtils.generateTestSignatureSync(payload);
```

### 3. FakeSecureKeypairRepository (`fake_secure_keypair_repository.dart`)

**Purpose:** In-memory implementation of SecureKeypairRepository for testing

**When to use:**
- Tests that need KeypairController
- Tests that verify keypair management logic
- Widget tests that require keypair state

**Usage:**

```dart
import '../test_helpers/fake_secure_keypair_repository.dart';
import '../test_helpers/test_keypair_factory.dart';

test('example test', () async {
  // Create test keypairs
  final keypair1 = await TestKeypairFactory.fromSeed(1);
  final keypair2 = await TestKeypairFactory.fromSeed(2);

  // Create repository with keypairs
  final repository = FakeSecureKeypairRepository([keypair1, keypair2]);

  // Use with KeypairController
  final controller = KeypairController(
    secureRepository: repository,
    marketplaceService: marketplaceService,
  );

  await controller.ensureLoaded();
});
```

**DO NOT:**
- Create local `_FakeSecureKeypairRepository` classes in test files
- Duplicate this implementation
- Use mock/stub repositories with fake data

**ALWAYS:**
- Import and use the centralized `FakeSecureKeypairRepository`
- Populate it with real keypairs from `TestKeypairFactory`

## Anti-Patterns to Avoid

### ❌ NEVER Do This:

```dart
// ❌ Hardcoded fake keys
ProfileKeypair(
  id: 'test-id',
  publicKey: base64Encode(List.filled(32, 1)),
  privateKey: base64Encode(List.filled(32, 2)),
  // ...
);

// ❌ Mock signature helpers
String _createFakeSignature() {
  return 'fake-signature-xyz';
}

// ❌ Local duplicate repository implementations
class _FakeSecureKeypairRepository implements SecureKeypairRepository {
  // ... duplicate code ...
}

// ❌ Hardcoded test principals
const testPrincipal = 'aaaaa-aa';
```

### ✅ ALWAYS Do This:

```dart
// ✅ Use TestKeypairFactory
final keypair = await TestKeypairFactory.getEd25519Keypair();

// ✅ Use TestSignatureUtils
final signature = TestSignatureUtils.generateTestSignatureSync(payload);

// ✅ Use centralized FakeSecureKeypairRepository
final repository = FakeSecureKeypairRepository([keypair]);

// ✅ Use real principals from keypairs
final principal = PrincipalUtils.textFromRecord(keypair);
```

## Backend Communication Testing

When testing code that communicates with the backend (API calls, script uploads, etc.):

1. **Always use real test keypairs:**
   ```dart
   final keypair = await TestKeypairFactory.getEd25519Keypair();
   ```

2. **Always use real signatures:**
   ```dart
   final request = TestSignatureUtils.createTestScriptRequest();
   ```

3. **Always test against real backend (when available):**
   - Tests should use the actual API services
   - Mock HTTP responses only when testing error handling
   - Backend unavailability should cause test failure (FAIL FAST)

4. **Never use offline/fallback modes in tests:**
   - If the backend can't be reached, the test should FAIL
   - NO graceful degradation in tests
   - This ensures infrastructure problems are caught early

## Testing Multiple Users

When testing scenarios with multiple users/keypairs:

```dart
test('multiple users scenario', () async {
  // Create distinct keypairs using different seeds
  final alice = await TestKeypairFactory.fromSeed(100);
  final bob = await TestKeypairFactory.fromSeed(200);
  final charlie = await TestKeypairFactory.fromSeed(300);

  // Each will have unique principal, keys, etc.
  expect(alice.id, isNot(equals(bob.id)));
  expect(alice.publicKey, isNot(equals(bob.publicKey)));
});
```

## Global Test Configuration

The project includes `/test/flutter_test_config.dart` which:
- Auto-initializes TestSignatureUtils before all tests
- Ensures consistent test environment setup
- Allows synchronous access to test signatures throughout the test suite

You generally don't need to manually initialize test utilities - it's done automatically.

## Debugging Test Failures

If tests fail with signature/authentication errors:

1. **Check initialization:**
   ```dart
   setUpAll(() async {
     await TestSignatureUtils.ensureInitialized();
   });
   ```

2. **Verify you're using real keypairs:**
   ```dart
   // Good
   final keypair = await TestKeypairFactory.getEd25519Keypair();

   // Bad
   final keypair = ProfileKeypair(...hardcoded values...);
   ```

3. **Check signature generation:**
   ```dart
   final payload = {...};
   final signature = TestSignatureUtils.generateTestSignatureSync(payload);
   // Signature should be non-empty base64 string
   ```

4. **Verify backend connectivity:**
   - Tests should fail fast if backend is unreachable
   - Check logs for connection errors
   - Ensure test infrastructure is running

## Contributing New Test Helpers

When adding new test helpers to this directory:

1. **Follow DRY:** Don't duplicate existing functionality
2. **Use real crypto:** No mock/fake signatures or keys
3. **Document clearly:** Add comprehensive comments and usage examples
4. **Update this AGENTS.md:** Add new helper documentation
5. **Ensure FAIL FAST:** Helpers should not hide infrastructure failures

## Summary: Quick Reference

| Need                  | Use                                                     | Import                                |
|-----------------------|---------------------------------------------------------|---------------------------------------|
| Test keypair          | `TestKeypairFactory.getEd25519Keypair()`                | `test_keypair_factory.dart`           |
| Multiple users        | `TestKeypairFactory.fromSeed(N)`                        | `test_keypair_factory.dart`           |
| Script upload request | `TestSignatureUtils.createTestScriptRequest()`          | `test_signature_utils.dart`           |
| Custom signature      | `TestSignatureUtils.generateTestSignatureSync(payload)` | `test_signature_utils.dart`           |
| Keypair repository    | `FakeSecureKeypairRepository([keypairs])`               | `fake_secure_keypair_repository.dart` |
| Test principal        | `TestSignatureUtils.getPrincipal()`                     | `test_signature_utils.dart`           |

## Remember

- **NO hardcoded keys or signatures**
- **NO duplicate repository implementations**
- **NO fallback/offline modes in tests**
- **ALWAYS use centralized test helpers**
- **ALWAYS fail fast when infrastructure is unavailable**
- **Tests should use REAL cryptographic keypairs and signatures**
