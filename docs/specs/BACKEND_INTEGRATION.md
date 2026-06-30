# Backend Integration Status

**Last Updated:** 2025-02-15

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         DATA LAYER                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  REMOTE DATA (Cloudflare Workers)                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         MarketplaceOpenApiService                        │   │
│  │         https://icp-mp.kalaj.org/api/v1                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                     │
│                            ▼                                     │
│  LOCAL STORAGE                                                  │
│  ┌─────────────────┐  ┌─────────────────────────────┐          │
│  │ ScriptRepository│  │ ProfileRepository            │          │
│  │ (scripts.json)  │  │ (profiles.json + SecureStore)│          │
│  └─────────────────┘  └─────────────────────────────┘          │
│                                                                  │
│  RUST FFI BRIDGE (Native)                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  libicp_core.so/.dylib/.dll                              │   │
│  │  - Keypair generation, signing, ICP calls, TS/QuickJS    │   │
│  │    runtime, Candid parse                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## API Client

**Service:** `MarketplaceOpenApiService`
**File:** `lib/services/marketplace_open_api_service.dart`
**Base URL:** `${AppConfig.apiEndpoint}/api/v1`
- Production: `https://icp-mp.kalaj.org/api/v1`
- Tests: `http://127.0.0.1:$MARKETPLACE_API_PORT/api/v1`

**HTTP Client:** `package:http/http.dart`

---

## Authentication

### Cryptographic Signing

All authenticated requests include:
- **Timestamp**: Unix timestamp (5-minute window)
- **Nonce**: UUID v4 (replay prevention)
- **Signature**: Ed25519 or secp256k1
- **Public Key**: Must be active for account

### Signature Process

```
1. Construct canonical JSON (sorted keys, no whitespace)
2. UTF-8 encode
3. Sign:
   - Ed25519: Sign directly
   - secp256k1: SHA-256 hash then ECDSA (via Rust FFI)
4. Base64 encode signature
```

### Signing Services

| Service | Purpose | File |
|---------|---------|------|
| `ScriptSignatureService` | Script operations | `lib/services/script_signature_service.dart` |
| `AccountSignatureService` | Account management | `lib/services/account_signature_service.dart` |

---

## Data Sources

### Remote (API)

| Data | Service | Status |
|------|---------|--------|
| Scripts (CRUD) | `MarketplaceOpenApiService` | Live |
| Accounts | `MarketplaceOpenApiService` | Live |
| Public Keys | `MarketplaceOpenApiService` | Live |
| Reviews (read) | `MarketplaceOpenApiService` | Live |
| Stats | `MarketplaceOpenApiService` | Live |

### Local (Storage)

| Data | Repository | Storage |
|------|------------|---------|
| Scripts (cache) | `ScriptRepository` | `scripts.json` |
| Profiles | `ProfileRepository` | `profiles.json` + FlutterSecureStorage |
| Keypairs | `ProfileRepository` | FlutterSecureStorage |
| Bookmarks | `BookmarksService` | `icp_bookmarks.json` |
| Download History | `DownloadHistoryService` | SharedPreferences |

### Native (Rust FFI)

| Feature | Function |
|---------|----------|
| Keypair Generation | `icp_generate_keypair` |
| Principal Derivation | `icp_principal_from_public_key` |
| Message Signing | `icp_sign_message` |
| Candid Interface | `icp_fetch_candid`, `icp_parse_candid` |
| Canister Calls | `icp_call_anonymous`, `icp_call_authenticated` |
| Script Execution | `icp_js_exec`, `icp_js_lint`, `icp_js_validate_comprehensive` |
| App Lifecycle | `icp_js_app_init`, `icp_js_app_view`, `icp_js_app_update` |

---

## Error Handling

### Pattern 1: Fail Fast (Primary)
```dart
if (response.statusCode < 200 || response.statusCode > 299) {
  throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
}
```

### Pattern 2: Detailed Error Extraction
```dart
String _extractErrorMessage(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map && decoded.containsKey('error')) {
    return decoded['error'] as String;
  }
  return body;
}
```

### Pattern 3: Graceful Degradation (Non-critical only)
```dart
// Only for featured/trending scripts
Future<List<MarketplaceScript>> getFeaturedScripts() async {
  try { ... }
  catch (e) { return []; }  // Acceptable for non-critical
}
```

---

## Test Infrastructure

### Real Cryptography

Per project rules, tests MUST use real keypairs:
- `TestKeypairFactory.getEd25519Keypair()` - Random keypair
- `TestKeypairFactory.fromSeed(N)` - Deterministic from seed
- `TestSignatureUtils.createTestScriptRequest()` - Signed request
- `FakeSecureKeypairRepository([keypairs])` - In-memory storage

### Mock Services

| Mock | Purpose | Location |
|------|---------|----------|
| `MockMarketplaceOpenApiService` | Unit tests | `test/test_helpers/mock_marketplace_service.dart` |
| `FakeSecureKeypairRepository` | Widget tests | `test/test_helpers/fake_secure_keypair_repository.dart` |
| `PoemScriptRepository` | E2E tests (REAL API) | Integration tests |

---

## Key Observations

### Strengths
1. Clean separation: API services, repositories, controllers
2. Real backend integration with Cloudflare Workers
3. Cryptographic authentication (Ed25519/secp256k1)
4. Profile-centric design (keys belong to profiles)

### Design Decisions
1. **No GraphQL**: Pure REST API
2. **No Offline Mode**: FAIL FAST by design
3. **No Retry Logic**: Single attempt with timeout
4. **Rust FFI**: Heavy reliance for crypto/ICP operations

### Issues
1. Graceful degradation in `getFeaturedScripts()` (acceptable for non-critical)
2. Deprecated `SecureKeypairRepository` still exists (migration layer)
3. Some endpoints return empty arrays on failure (anti-pattern)
