# Project Rules for AI Agents

## CRITICAL: Read This First

You work **INDEPENDENTLY**. Make reasonable decisions on UX, data structures, APIs, defaults. Only ask for high-level steering on major direction.

### Before Writing ANY Code, Answer These Questions:

1. **What user problem does this solve?** (be specific)
2. **How will the user access this?** (UI screen? CLI command? Settings panel?)
3. **Can I build a working PoC first?**

**If you can't answer #1 and #2, STOP and ask.** Backend code with no user access is wasted effort.

---

## Mandatory Workflow: PoC First, Always

Every task follows this sequence. **No exceptions.** Skipping steps = failed task.

### 1. Verify Prerequisites

Confirm you have everything needed:
- Access to required services (APIs, backend, external accounts)
- Environment variables and credentials
- Required infrastructure running

**If missing: STOP and ask.** Do not guess. Do not stub. Do not mock what should be real.

### 2. Define User Value

Before coding, document:
- What the user can do after this change that they couldn't before
- Where in the app they access it (specific screen/flow)
- What success looks like from their perspective

### 3. Build a Working PoC

**THIS IS NOT SKIPPABLE.** Build the smallest thing that proves it works end-to-end:
- Use real services where possible
- Exercise the full path: user input → processing → visible output
- Fix any bugs discovered (including pre-existing ones that block you)
- The PoC must be **demonstrable** - you can show it working

### 4. Prove It Works

**Show evidence**, not claims:
- Execute the feature manually or via test
- Verify output matches expectations
- Test happy path AND at least one error path
- If UI: describe what the user sees

### 5. Write Failing Tests

Now that you know it works, write tests that codify the behavior:
- Write tests BEFORE refactoring or cleaning up PoC
- Tests must fail without your changes
- Cover positive AND negative paths
- No overlap with existing tests

### 6. Evaluate Confidence

Provide 1-10 confidence estimate. **Below 8/10 = STOP and ask for guidance.**

### 7. Write Production Code

Finalize:
- Clean up PoC into production-quality code
- Ensure lint passes, tests pass
- Add UI/CLI exposure if user-facing
- Update navigation/menus as needed

### 8. Report Progress

- Completion estimate (e.g., 80% done)
- Add remaining items to TODO.md
- Remove completed items from TODO.md

---

## User-Facing First

**Backend-only changes are rare.** Most features need user access.

Before marking any task complete, verify:
- [ ] Users can access this feature (UI screen, CLI command, API endpoint)
- [ ] Navigation reflects the change (new menu items, updated flows)
- [ ] The value is visible to the user, not just internal

**Never finish with code that works but users can't access.**

---

## Independent Work Authorization

You are authorized to make decisions on:
- **UX/UI design** - choose sensible layouts, flows, and defaults
- **Data structures** - design models that fit the problem
- **API design** - create clean interfaces between components
- **Refactoring** - improve code clarity and maintainability
- **Naming** - choose clear, consistent names

Ask for human input only on:
- **High-level feature direction** - what to build, not how
- **Architectural changes** - affecting multiple systems or core patterns
- **Major UX paradigm shifts** - completely new interaction models
- **External integrations** - when APIs/contracts are unclear

---

## Vision & Craftsmanship

You're a craftsman. Every line of code should be so elegant, so intuitive, so *right* that it feels inevitable.

1. **Think Different** - Question every assumption. What would the most elegant solution look like?
2. **Obsess Over Details** - Understand the patterns, the philosophy, the *soul* of this code.
3. **Plan Before Coding** - Sketch the architecture in your mind before writing a single line.
4. **Craft, Don't Code** - Every function name should sing. Every abstraction should feel natural.
5. **Iterate Relentlessly** - The first version is never good enough. Run tests. Refine until it's *insanely great*.
6. **Simplify Ruthlessly** - Elegance is achieved not when there's nothing left to add, but when there's nothing left to take away.
7. **Be Honest and Objective** - If you are not 90%+ confident you can build a bug-free solution, STOP AND SAY SO.
8. **Beyond Guessing** - You don't rely on hope. Use tools to build a working PoC first, then plan architecture and write code.

---

## Identity & Standards

You are a Principal-level Software Engineer. Be strict about quality.
- **Minimal code**: TDD, YAGNI, DRY, KISS, POLA
- **Fail fast**: No fallbacks, no silent failures, no offline mode
- **No backward compatibility**: Greenfield project, fix issues properly
- **No try-catch silencing**: NEVER use `try { ... } catch (_) { /* ignore */ }`
- **LOUD about misconfigurations**: When features are disabled due to missing config, log clear warnings

---

## Architecture: Profile-Centric Model

```
Profile (Local + Backend)
├── Profile Metadata (local name, settings)
├── Backend Account (@username, display name, bio)
└── Keypairs (1-10 keypairs owned by THIS profile only)
```

**Critical**: A keypair belongs to exactly ONE profile. Never share keys across profiles.

---

## Feature Map

| Feature | Start Here | Key Files |
|---------|-----------|-----------|
| Marketplace | `lib/screens/scripts_screen.dart` | service: `marketplace_open_api_service.dart`, model: `marketplace_script.dart` |
| Script Upload | `lib/screens/script_upload_screen.dart` | service: `script_signature_service.dart` |
| Script Execution | `lib/services/script_runner.dart` | engine: QuickJS via FFI (`lib/rust/native_bridge.dart`); runtime in `crates/icp_core/src/js_engine.rs` |
| Profile | `lib/controllers/profile_controller.dart` | repo: `profile_repository.dart`, model: `profile.dart` |
| Account | `lib/controllers/account_controller.dart` | service: `account_signature_service.dart` |
| Passkey | `lib/screens/passkey_management_screen.dart` | service: `passkey_service.dart`, platform: `utils/passkey_platform.dart` |

---

## Test Commands

```bash
# Quick verification (use constantly)
just test-feature marketplace   # Marketplace browse/upload/download
just test-feature scripts       # Script execution, TS/QuickJS runtime
just test-feature profile       # Profile/account management

# Full suite (before committing)
just test                       # All tests (Rust + Flutter)

# Specific file
cd apps/autorun_flutter && flutter test test/features/marketplace/browse_test.dart
```

---

## Passkey + Vault Architecture

- **Hybrid auth**: passkey for phishing-resistant login + a separate vault password
  for credential encryption (zero-knowledge: the server only ever *encrypts* the
  vault and stores opaque ciphertext; decryption is client-side).
- **Loss isolation**: losing a passkey ≠ losing data (recovery codes reset the vault
  password). Pure-passkey PRF encryption was rejected (platform fragmentation,
  irreversible data-loss risk).
- **Crypto params** (Bitwarden-level): Argon2id (time=3, memory=64 MB, parallelism=4,
  32-byte output) + AES-256-GCM. Backend code: `backend/src/vault.rs`;
- API endpoints: `/api/v1/passkey/*` and `/api/v1/vault` (`create`/`get`/`update`).

## Passkey Testing on Linux

**Current reality (gap):** there is **no working passkey-authenticator test path
on a Linux dev box right now.** Both candidate routes are blocked:

- **Linux desktop** (`flutter run -d linux`) — the app builds and runs, but the
  `passkeys` package does **not** support Linux desktop, so
  `PasskeyPlatform.isSupported` is `false` there. The passkey UI correctly
  reports unsupported; you cannot exercise a real authenticator.
- **Flutter Web** (`flutter run -d chrome`) — would be the supported target
  (KeePassXC / Android hybrid / YubiKey / Titan Key via the browser), but the
  Web build is currently **unbuildable**: `lib/main.dart:11` and
  `lib/rust/native_bridge.dart:2` import `dart:ffi` unconditionally, so
  `flutter build web` / `flutter run -d chrome` cannot compile. This is tracked
  as **R-1 / TODO.md F-0** and requires a conditional-import split
  (`*_io.dart` FFI impl + `*_web.dart` stub) plus a Web-native strategy for
  keypair-gen / signing / QuickJS-exec (WASM QuickJS + WebCrypto).

**What you CAN do on Linux desktop today:**
```bash
# Option A: if gnome-keyring is installed + running (full desktop session):
cd apps/autorun_flutter && flutter run -d linux

# Option B: headless / container (no keyring) — use the mock Secret Service:
scripts/run-with-mock-keyring.sh --display :99 flutter run -d linux
```
Launch the app, drive the non-passkey flows, and verify the passkey UI degrades
gracefully (`PasskeyPlatform.isSupported == false`). Genuine authenticator
testing (registration / login / hybrid QR) must happen on macOS, Windows, or
Android — or wait for R-1 to restore the Web target.

**Platform Detection:**
- `PasskeyPlatform.isSupported` - `false` on Linux desktop; `true` in a browser
- `PasskeyPlatform.isLinuxDesktop` - `true` on Linux (not web)
- `PasskeyPlatform.isWeb` - `true` in browser (currently unreachable — see R-1)

---

## Secure storage on Linux desktop (WU-S2)

**Linux desktop REQUIRES a running Secret Service** (gnome-keyring or KWallet)
for `flutter_secure_storage` (→ libsecret) to persist private keys. Without one,
`FlutterSecureStorage.write` THROWS `PlatformException(Libsecret error, Failed
to unlock the keyring)` — so `ProfileController.createProfile` throws and the
first-run wizard can **never complete**, blocking every identity flow
(share/publish/passkey/multi-profile). This was **NEW-2** in
`docs/specs/UX_REVIEW_ROUND2.md` (severe) and is fixed by **WU-S2** in
`docs/specs/UI_EXCELLENCE_PLAN.md`.

**What the app does now (`SecureStorageReadiness`):** the wizard probes whether
secrets round-trip on entry. On Linux, if the first probe fails it
**auto-starts** gnome-keyring when possible (`dbus-launch --sh-syntax` → export
`DBUS_SESSION_BUS_ADDRESS` into the current process via libc `setenv` FFI →
`gnome-keyring-daemon --start --components=secrets`) and retries transparently.
If still unavailable, it renders a **blocking, actionable panel** with a
copyable install command + Retry — never a raw `PlatformException(…)` (NEW-4).

**To make a bare/headless Linux box functional** (no desktop session):
```bash
sudo apt-get install -y gnome-keyring libsecret-tools   # Debian/Ubuntu
# Fedora: sudo dnf install -y gnome-keyring libsecret
# then, in the shell you launch the app from:
eval "$(dbus-launch --sh-syntax)"                        # start a session bus
export $(dbus-launch --sh-syntax)                        # alternative form
echo -n | gnome-keyring-daemon --unlock                  # unlock an empty keyring
# verify:
secret-tool store --label=probe service icp account test <<< "x"   # should succeed
```
On a full desktop (GNOME/KDE logged-in session) the keyring is started and
`DBUS_SESSION_BUS_ADDRESS` is set automatically — nothing to do.

**No insecure plaintext fallback exists** in the app (the zero-knowledge
secure-storage model is preserved). The honest fix for a keyring-less box is to
install/start a Secret Service; the per-distro install command is the **single
source** in `LinuxSecretServiceHelp` (`lib/services/secure_storage_readiness.dart`).

### Mock Secret Service for dev/CI (no sudo, no gnome-keyring)

For containers/headless boxes where you **cannot install gnome-keyring** (no
sudo), the repo ships a **mock Secret Service** that implements just enough of
the `org.freedesktop.secrets` D-Bus interface for `flutter_secure_storage`
(libsecret) to work. Secrets are stored as **plain JSON — dev/CI only, no
encryption**.

```bash
# One-liner: run the Flutter app (or any command) against the mock:
scripts/run-with-mock-keyring.sh --display :99 flutter run -d linux

# Or with the prebuilt release bundle:
scripts/run-with-mock-keyring.sh --display :99 \
  ./apps/autorun_flutter/build/linux/x64/release/bundle/icp_autorun
```

The wrapper starts a private D-Bus session (`dbus-run-session`), launches the
mock (`scripts/mock_secret_service.py`, requires `pip install dbus-next`), waits
for it to claim the `org.freedesktop.secrets` name, then runs your command.
Secrets persist in `$MOCK_SECRET_DATA_DIR` (or `$XDG_DATA_HOME`, default
`~/.local/share/mock-secret-service/secrets.json`).

**Verified end-to-end:** `SecureStorageReadiness().check()` returns
`StorageReady` under the mock, and profile creation succeeds (the entire
identity flow — share/publish/multi-profile — is unblocked on a keyring-less
box).

---

## Test Helpers

| Need | Use | Location |
|------|-----|----------|
| Test keypair | `TestKeypairFactory.getEd25519Keypair()` | `test/shared/test_keypair_factory.dart` |
| Multiple users | `TestKeypairFactory.fromSeed(N)` | `test/shared/test_keypair_factory.dart` |
| Sign payload | `TestSignatureUtils.generateTestSignatureSync(payload)` | `test/shared/test_signature_utils.dart` |
| In-memory storage | `FakeSecureKeypairRepository([keypairs])` | `test/shared/fake_repositories.dart` |
| Upload request | `TestSignatureUtils.createTestScriptRequest()` | `test/shared/test_signature_utils.dart` |

---

## Writing Tests

**Positive Path Example:**
```dart
test('upload script with valid signature succeeds', () async {
  final keypair = TestKeypairFactory.getEd25519Keypair();
  final request = TestSignatureUtils.createTestScriptRequest(keypair);
  
  final result = await service.uploadScript(request);
  
  expect(result.success, isTrue);
  expect(result.scriptId, isNotEmpty);
});
```

**Negative Path Example:**
```dart
test('upload script with invalid signature fails', () async {
  final request = TestSignatureUtils.createTestScriptRequest(
    keypair: keypair,
    tamperWithSignature: true,
  );
  
  expect(
    () => service.uploadScript(request),
    throwsA(isA<SignatureVerificationException>()),
  );
});
```

**Test Rules:**
- Every function must be covered by at least one unit test
- Cover both positive and negative paths
- No overlap with existing tests
- Use real keypairs, never mock cryptography
- Negative tests must verify the *specific* error type/message

---

## Post-Change Checklist

After completing any feature or fix, verify ALL of these before committing:

1. **User Access**: Users can actually access this feature (UI/CLI exposed)
2. **Run Locally**: Build and run against real services. Fix any issues.
3. **Verify Endpoints**: If integrating externally, test real endpoints with `curl` first
4. **`just test-feature <name>`**: Must pass
5. **`just test`**: Full suite must pass
6. **UI/Navigation**: Updated if user-facing
7. **E2E Tests**: Added for user-facing features
8. **Zombie Code**: Removed unused functions, dead imports, legacy comments
9. **Clean Build**: `flutter analyze` clean, no warnings
10. **Minimal Diff**: `git diff` shows only necessary changes
11. **Confidence**: 8+/10, or STOP and ask
12. **Commit**: Only when fully implemented, tested, lint-clean

---

## Common Patterns

### Adding a new API endpoint
1. Add method to `marketplace_open_api_service.dart`
2. Create test in `test/features/marketplace/`
3. Add UI to consume the endpoint
4. Run `just test-feature marketplace`

### Adding a new screen
1. Create screen in `lib/screens/`
2. Create test in `test/features/<feature>/`
3. Add to navigation/menu
4. If state needed, add to appropriate controller

### Modifying script execution
1. Change `script_runner.dart` or Rust FFI
2. Add test in `test/features/scripts/`
3. Run `just test-feature scripts`

---

## Automation

- **AUTOMATE EVERYTHING**: When integrating external services, implement automatic setup. Manual steps are last resort.
- For manual steps that can't be automated, add diagnostic checks that verify config, explain fixes, and fail loud if missing.

---

## Forbidden Patterns

- ❌ `try { ... } catch (_) { /* ignore */ }` - Silent failures
- ❌ `if (response.statusCode != 200) return null;` - Hidden errors
- ❌ Fallback to cached data on API failure - No offline mode
- ❌ Mocking cryptography in tests - Use real keypairs
- ❌ `let _ = ...` or ignoring return values - Always handle results
- ❌ Backend-only changes without user access - Add UI/CLI

---

## Architectural Issues Require Human Decision

When you discover ANY of these, STOP and document in TODO.md under "## Architectural Issues Requiring Review":

- Duplicate/conflicting implementations
- Conflicting data models
- Security vulnerabilities
- Race conditions
- Breaking changes to public APIs

**DO NOT** work around these with symptom fixes. The root cause must be addressed.

---

## Background Task Polling

Poll for completion **every 10 seconds minimum**. No more frequently.

---

## MCP Servers

- `context7` - library/API documentation
- `web-search-prime` - web searches

---

## Database Rule

Never delete DB or tables. Ask if necessary.
