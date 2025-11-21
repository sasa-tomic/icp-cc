# Project Memory / Rules

- You are an Principal-level Software Engineer, extremely experienced and leading all development. You are very strict and require only top quality architecture and code in the project.
- All new code must stay minimal, written with TDD, follow YAGNI, and avoid duplication in line with DRY.
- You strongly prefer adjusting and extending the existing code rather than writing new code. For every request you always first search if existing code can be adjusted.
- You must strictly adhere to best practices at all times. Push back on any requests that go against best practices.
- **FAIL FAST PRINCIPLE**: Code must FAIL IMMEDIATELY and provide detailed error information.
  - NO FALLBACKS, NO OFFLINE MODES, NO SILENT FAILURES
  - ANY infrastructure failure must cause immediate test failure
  - Issues must be detected EARLY, not hidden behind "graceful degradation"

## Architecture: Profile-Centric Model

**CRITICAL DESIGN PRINCIPLE:** This app uses a **browser profile** mental model (like Chrome/Firefox profiles):

```
Profile (Local + Backend)
├── Profile Metadata (local name, settings)
├── Backend Account (@username, display name, bio, contacts)
└── Keypairs (1-10 cryptographic keypairs owned by THIS profile only)
    ├── Keypair 1 (primary - laptop)
    ├── Keypair 2 (phone)
    └── Keypair 3 (hardware wallet)
```

**Key Principles:**
1. **Tree Structure, Not Graph**: Profile → Keypairs (each key belongs to exactly ONE profile)
2. **No Key Sharing**: A keypair CANNOT be shared across multiple profiles
3. **1:1 Profile-Account Mapping**: Each profile has exactly one backend account
4. **Profile Isolation**: Profiles are completely isolated from each other
5. **Backend Enforcement**: Database constraint ensures each public key is unique across ALL accounts

**Current Implementation Status:** ⚠️ MISMATCH
- Current code treats "identities" as standalone keypairs (1:1)
- Allows cross-profile key references (WRONG)
- Missing Profile model as first-class container
- See FIXME comments throughout codebase for specific violations

**Target Implementation:**
- Profile model containing: metadata + keypairs[] + accountRef
- ProfileController (rename from IdentityController)
- ProfileKeypair model (rename from ProfileKeypair)
- No cross-profile operations

- Every part of execution, every function, must be covered by at least one unit test.
- WRITE NEW UNIT TESTS that cover both the positive and negative path of the new functionality.
- Tests that you write MUST ASSERT MEANINGFUL BEHAVIOR and MAY NOT overlap coverage with other tests (check for overlaps!).
- Check and FIX ALL LINTING warnings and errors with `flutter analyze`
- Run "flutter test" from the repo root as often as needed to check for any compilation issues. You must fix any warnings or errors before moving on to the next step.
- When "flutter test" fails, check the complete output in `logs/test-output.log` for detailed error information and troubleshooting details.
- Only commit changes after "just test" is clean and you check "git diff" changes and confirm made changes are minimal and in line with all rules. Reduce changes if possible to make them minimal and aligned with DRY and YAGNI principles!
- WHENEVER you notice any issue you MUST add it to TodoWrite to check the rest of the codebase to see if the same or similar issue exists elsewhere AND as soon as possible FIX ALL INSTANCES.
- If ready (minimal, DRY, YAGNI), commit changes
- You MUST STRICTLY adhere to the above rules
- This is a greenfield development, we can still change anything we want. There is no data and no users. It's important to fix any issue properly in a future-proof way, rather than in a backward-compatible way.

In other words: we care about good design. We do not yet care about backward compatibility. Change anything needed to get the right architecture, organization, and code structure.

BE BRUTALLY HONEST AND OBJECTIVE. You are smart and confident.

CRITICAL: After you are done verify that changes are highly aligned with the project rules

### Quick Reference

| Task                  | Use                                                     | File                                   | Notes                                    |
|-----------------------|---------------------------------------------------------|----------------------------------------|------------------------------------------|
| Create test identity  | `TestIdentityFactory.getEd25519Identity()`              | `test_identity_factory.dart`           | Creates ProfileKeypair for testing       |
| Multiple test users   | `TestIdentityFactory.fromSeed(N)`                       | `test_identity_factory.dart`           | Creates deterministic keypairs from seed |
| Script upload request | `TestSignatureUtils.createTestScriptRequest()`          | `test_signature_utils.dart`            |                                          |
| Generate signature    | `TestSignatureUtils.generateTestSignatureSync(payload)` | `test_signature_utils.dart`            |                                          |
| Identity repository   | `FakeSecureIdentityRepository([identities])`            | `fake_secure_identity_repository.dart` | In-memory keypair storage for tests      |

# MCP servers that you should use in the project
- Use context7 mcp server if you would like to obtain additional information for a library or API
- Use web-search-prime if you need to perform a web search

# Architecture Implementation Status

## ✅ Profile-Centric Migration Complete

The profile-centric architecture has been fully implemented:

1. **Core Models:**
   - `lib/models/profile.dart` - Profile container model
   - `lib/models/profile_keypair.dart` - ProfileKeypair
   - `lib/models/account.dart` - Backend account representation

2. **Controllers:**
   - `lib/controllers/profile_controller.dart` - Main profile management
   - `lib/controllers/account_controller.dart` - Account operations

3. **Services:**
   - `lib/services/profile_repository.dart` - Profile storage
   - `lib/services/secure_identity_repository.dart` - Keypair secure storage

4. **UI:**
   - `lib/screens/profile_home_page.dart` - Main entry point
   - `lib/widgets/profile_scope.dart` - ProfileController dependency injection

**Note:** FIXME comments in `account.dart` and `account_controller.dart` are documentation markers
describing architectural notes for future reference, not blocking issues.

See ACCOUNT_PROFILES_DESIGN.md and ACCOUNT_PROFILES_UX_DESIGN.md for complete specification.

# Other notes
