# Architecture Overview

**Read this first.** 30 seconds to understand the entire system.

## System Map

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              FRONTEND (Flutter)                          │
├─────────────────────────────────────────────────────────────────────────┤
│  FEATURES                                                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  MARKETPLACE │  │   SCRIPTS   │  │   PROFILE   │  │   PASSKEY   │    │
│  │  (browse,    │  │  (run, edit)│  │  (keys,acc) │  │   (auth)    │    │
│  │   upload)    │  │             │  │             │  │             │    │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘    │
│         │                │                │                │            │
│  ┌──────▼────────────────▼────────────────▼────────────────▼──────┐    │
│  │                     RUST FFI BRIDGE                             │    │
│  │  libicp_core.so: crypto, ICP calls, Lua runtime, Candid parse  │    │
│  └────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ HTTP/REST
┌─────────────────────────────────────────────────────────────────────────┐
│                           BACKEND (Rust/Poem)                            │
│  https://icp-mp.kalaj.org/api/v1                                        │
│  Endpoints: /scripts, /accounts, /marketplace-stats, /passkey           │
└─────────────────────────────────────────────────────────────────────────┘
```

## Feature → File Mapping

| Feature | Screen | Controller | Service | Model | Test |
|---------|--------|------------|---------|-------|------|
| **Marketplace Browse** | `scripts_screen.dart` | `script_controller.dart` | `marketplace_open_api_service.dart` | `marketplace_script.dart` | `test/features/marketplace/` |
| **Marketplace Upload** | `script_upload_screen.dart` | - | `script_signature_service.dart` | - | `test/features/marketplace/` |
| **Script Execution** | - | - | `script_runner.dart` | - | `test/features/scripts/` |
| **Profile Management** | `profile_home_page.dart` | `profile_controller.dart` | `profile_repository.dart` | `profile.dart`, `profile_keypair.dart` | `test/features/profile/` |
| **Account Registration** | `account_registration_wizard.dart` | `account_controller.dart` | `account_signature_service.dart` | `account.dart` | `test/features/profile/` |
| **Passkey Auth** | - | - | `passkey_service.dart` | - | `test/features/passkey/` |
| **Bookmarks** | `bookmarks_screen.dart` | - | `bookmarks_service.dart` | `canister_method.dart` | `test/features/bookmarks/` |

## Data Flow (Read This to Understand How Things Connect)

### 1. Marketplace Browse Flow
```
User opens app
    → ScriptsScreen.build()
    → ScriptController.loadMarketplaceScripts()
    → MarketplaceOpenApiService.searchScripts()
    → HTTP POST /api/v1/scripts/search
    → List<MarketplaceScript>
    → ScriptCard widgets
```

### 2. Script Upload Flow
```
User fills upload form
    → ScriptUploadScreen._submit()
    → ScriptSignatureService.signScriptUpload(keypair, payload)
    → Ed25519 signature (or secp256k1 via Rust FFI)
    → MarketplaceOpenApiService.uploadScript(signedPayload)
    → HTTP POST /api/v1/scripts
```

### 3. Script Execution Flow
```
User runs script
    → ScriptRunner.execute(luaSource, input)
    → Rust FFI: icp_lua_exec()
    → Effects returned (icp_call, icp_batch)
    → Host executes effects via Rust FFI
    → Results injected back to Lua
    → UI rendered via UiV1Renderer
```

### 4. Profile/Account Flow
```
User creates profile
    → ProfileController.createProfile()
    → ProfileKeypair.generate()
    → Rust FFI: icp_generate_keypair()
    → ProfileRepository.save() (local storage)
    
User registers account
    → AccountController.registerAccount()
    → AccountSignatureService.signRegistration()
    → MarketplaceOpenApiService.registerAccount()
    → HTTP POST /api/v1/accounts
```

## Key Files by Responsibility

### State Management
- `profile_controller.dart` - Current profile, keypairs, switching
- `account_controller.dart` - Backend account operations
- `script_controller.dart` - Local scripts, marketplace scripts

### API Layer
- `marketplace_open_api_service.dart` - All backend communication
- `script_signature_service.dart` - Cryptographic signing for scripts
- `account_signature_service.dart` - Cryptographic signing for accounts

### Local Storage
- `profile_repository.dart` - Profiles + keypairs (FlutterSecureStorage)
- `script_repository.dart` - Local scripts (JSON file)

### Rust FFI (Native)
- `native_bridge.dart` - Dart bindings to Rust library
- Rust crate: `crates/icp_core/`

## Test Structure

```
test/
├── features/                    # Feature-based E2E tests
│   ├── marketplace/
│   │   ├── browse_scripts_test.dart
│   │   ├── upload_script_test.dart
│   │   └── download_script_test.dart
│   ├── scripts/
│   │   ├── execute_test.dart
│   │   └── lua_effects_test.dart
│   ├── profile/
│   │   ├── create_profile_test.dart
│   │   ├── manage_keypairs_test.dart
│   │   └── register_account_test.dart
│   └── passkey/
│       └── authentication_test.dart
├── shared/                      # Test helpers
│   ├── test_keypair_factory.dart
│   ├── test_signature_utils.dart
│   └── fake_repositories.dart
└── unit/                        # Pure unit tests (utils, models)
```

## Quick Commands

```bash
just test-feature marketplace   # Test marketplace features
just test-feature scripts       # Test script execution
just test-feature profile       # Test profile/account
just test-all                   # Full test suite
```

## Critical Constraints

1. **Profile-Centric**: Every keypair belongs to exactly ONE profile
2. **Fail Fast**: No fallbacks, no silent failures, no offline mode
3. **Backend = Truth**: Local state syncs from backend, never vice versa
4. **Signed Requests**: All mutations require cryptographic signatures
