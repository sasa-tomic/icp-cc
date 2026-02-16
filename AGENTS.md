# Project Rules for AI Agents

## START HERE

1. **Read [ARCHITECTURE.md](ARCHITECTURE.md)** - 30-second system overview
2. **Check [TODO.md](TODO.md)** - Current priorities and blocked items
3. **Run `just test-feature <name>`** - Verify before and after changes

## Identity & Standards

You are a Principal-level Software Engineer. Be strict about quality.
- **Minimal code**: TDD, YAGNI, DRY
- **Fail fast**: No fallbacks, no silent failures, no offline mode
- **No backward compatibility**: Greenfield project, fix issues properly

## Architecture: Profile-Centric Model

```
Profile (Local + Backend)
├── Profile Metadata (local name, settings)
├── Backend Account (@username, display name, bio)
└── Keypairs (1-10 keypairs owned by THIS profile only)
```

**Critical**: A keypair belongs to exactly ONE profile. Never share keys across profiles.

## Feature Map

| Feature | Start Here | Key Files |
|---------|-----------|-----------|
| Marketplace | `lib/screens/scripts_screen.dart` | service: `marketplace_open_api_service.dart`, model: `marketplace_script.dart` |
| Script Upload | `lib/screens/script_upload_screen.dart` | service: `script_signature_service.dart` |
| Script Execution | `lib/services/script_runner.dart` | FFI: `lib/rust/native_bridge.dart` |
| Profile | `lib/controllers/profile_controller.dart` | repo: `profile_repository.dart`, model: `profile.dart` |
| Account | `lib/controllers/account_controller.dart` | service: `account_signature_service.dart` |
| Passkey | `lib/services/passkey_service.dart` | backend: `backend/src/services/passkey_service.rs` |

## Test Commands

```bash
# Quick verification (use constantly)
just test-feature marketplace   # Marketplace browse/upload/download
just test-feature scripts       # Script execution, Lua runtime
just test-feature profile       # Profile/account management

# Full suite (before committing)
just test                       # All tests (Rust + Flutter)

# Specific file
cd apps/autorun_flutter && flutter test test/features/marketplace/browse_test.dart
```

## Passkey Testing on Linux

The `passkeys` package does NOT support Linux desktop. Use Flutter Web:

```bash
# Run as web app (browser WebAuthn works with KeePassXC, YubiKey, Android phone)
cd apps/autorun_flutter && flutter run -d chrome
```

**Supported authenticators via browser:**
- KeePassXC (software authenticator)
- Android phone via hybrid auth (QR code scan)
- Hardware security keys (YubiKey, Titan Key)

## Test Helpers

| Need | Use | Location |
|------|-----|----------|
| Test keypair | `TestKeypairFactory.getEd25519Keypair()` | `test/shared/test_keypair_factory.dart` |
| Multiple users | `TestKeypairFactory.fromSeed(N)` | `test/shared/test_keypair_factory.dart` |
| Sign payload | `TestSignatureUtils.generateTestSignatureSync(payload)` | `test/shared/test_signature_utils.dart` |
| In-memory storage | `FakeSecureKeypairRepository([keypairs])` | `test/shared/fake_repositories.dart` |
| Upload request | `TestSignatureUtils.createTestScriptRequest()` | `test/shared/test_signature_utils.dart` |

## Before Making Changes

1. **Find the feature** in the Feature Map above
2. **Read the main screen/service** to understand current implementation
3. **Check for existing tests** in `test/features/<feature>/`
4. **Run the relevant test** to see current behavior: `just test-feature <name>`

## After Making Changes

1. **Run `just test-feature <name>`** - Must pass
2. **Run `just test`** - Full suite must pass
3. **Check `git diff`** - Changes should be minimal
4. **Fix ALL lint errors**: `flutter analyze` must be clean

## Writing Tests

```dart
// GOOD: Test user behavior, not implementation
test('user can browse marketplace scripts', () async {
  final result = await service.searchScripts(query: 'nns');
  expect(result.scripts, isNotEmpty);
  expect(result.scripts.first.title, contains('NNS'));
});

// BAD: Test implementation details
test('searchScripts calls HTTP POST', () async {
  // ...
});
```

## Common Patterns

### Adding a new API endpoint
1. Add method to `marketplace_open_api_service.dart`
2. Create test in `test/features/marketplace/`
3. Run `just test-feature marketplace`

### Adding a new screen
1. Create screen in `lib/screens/`
2. Create test in `test/features/<feature>/`
3. If state needed, add to appropriate controller

### Modifying script execution
1. Change `script_runner.dart` or Rust FFI
2. Add test in `test/features/scripts/`
3. Run `just test-feature scripts`

## Forbidden Patterns

- ❌ `try { ... } catch (_) { /* ignore */ }` - Silent failures
- ❌ `if (response.statusCode != 200) return null;` - Hidden errors
- ❌ Fallback to cached data on API failure - No offline mode
- ❌ Mocking cryptography in tests - Use real keypairs

## MCP Servers

- Use `context7` for library/API documentation
- Use `web-search-prime` for web searches

## Database Rule

Never delete DB or tables. Ask the user if necessary.
