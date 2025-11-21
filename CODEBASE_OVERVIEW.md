# ICP Autorun - Comprehensive Codebase Overview

## Executive Summary

This is a **Flutter + Rust + Poem REST API** cross-platform application for managing ICP (Internet Computer Protocol) scripts with a marketplace system. The app enables users to create, store, execute, and publish scripts locally, while discovering and downloading scripts from a decentralized marketplace.

**Current Status**: Phase 1 complete with basic marketplace and identity management. User facing in multiple areas requiring UX improvements.

---

## 1. Project Architecture & Tech Stack

### Frontend
- **Framework**: Flutter (Dart)
- **State Management**: ChangeNotifier controllers + provider pattern
- **Local Storage**:
  - `path_provider` for file-based script/identity storage
  - `flutter_secure_storage` for cryptographic keys (platform-native encryption)
  - `shared_preferences` for app settings
- **HTTP Client**: `http` package for API communication
- **Cryptography**:
  - `cryptography` package (Dart) for Ed25519 signing
  - Integration with Rust FFI bridge for complex operations
- **UI**: Material Design 3, responsive layouts
- **Code Editor**: `flutter_code_editor` + `flutter_highlight` for Lua script editing

### Backend
- **Framework**: Rust + Poem (async web framework)
- **Database**: SQLite (file-based, no external dependencies)
- **Async Runtime**: Tokio
- **ORM/Query Builder**: sqlx (compile-time checked SQL)
- **Serialization**: serde + serde_json
- **Cryptography**:
  - `ed25519-dalek` for Ed25519 signature verification
  - `k256` for secp256k1 ECDSA signature verification
  - `sha2` for message hashing
  - `base64` for encoding/decoding
- **Logging**: tracing + tracing-subscriber
- **Port**: 58000 (configurable via `PORT` env var)

### Native Bridge
- **Rust FFI Crate**: `crates/icp_core` (cdylib)
- **Compiled for**: Linux, Android (multiple ABIs), macOS, iOS, Windows
- **Build Tool**: `justfile` (replaces Makefile)

### Deployment
- **Local Dev**: Docker Compose (SQLite)
- **Production**: Docker + Cloudflare Tunnel
- **CI/CD**: Just recipes for build automation

---

## 2. Current Project Structure

```
icp-cc/
├── apps/
│   └── autorun_flutter/              # Main Flutter app
│       ├── lib/
│       │   ├── main.dart             # App entry + navigation
│       │   ├── config/
│       │   │   └── app_config.dart   # API endpoint configuration
│       │   ├── controllers/          # State management
│       │   │   ├── identity_controller.dart
│       │   │   └── script_controller.dart
│       │   ├── models/               # Data models
│       │   │   ├── identity_profile.dart
│       │   │   ├── marketplace_script.dart
│       │   │   ├── script_record.dart
│       │   │   ├── script_template.dart
│       │   │   ├── canister_method.dart
│       │   │   ├── profile_keypair.dart
│       │   │   └── purchase_record.dart
│       │   ├── screens/              # UI pages
│       │   │   ├── scripts_screen.dart (1624 lines) - LOCAL SCRIPTS + MARKETPLACE
│       │   │   ├── marketplace_screen.dart (676 lines) - STANDALONE MARKETPLACE
│       │   │   ├── identity_home_page.dart (806 lines) - IDENTITY MANAGEMENT
│       │   │   ├── script_creation_screen.dart
│       │   │   ├── script_upload_screen.dart
│       │   │   ├── bookmarks_screen.dart
│       │   │   └── download_history_screen.dart
│       │   ├── services/             # Business logic
│       │   │   ├── marketplace_open_api_service.dart - HTTP API CLIENT
│       │   │   ├── script_signature_service.dart - ED25519/SECP256K1 SIGNING
│       │   │   ├── secure_identity_repository.dart - ENCRYPTED STORAGE
│       │   │   ├── script_repository.dart - LOCAL SCRIPT STORAGE
│       │   │   ├── script_runner.dart
│       │   │   ├── download_history_service.dart
│       │   │   ├── bookmarks_service.dart
│       │   │   ├── candid_service.dart
│       │   │   ├── script_validation_service.dart
│       │   │   └── data_transformer.dart
│       │   ├── widgets/              # Reusable UI components
│       │   ├── utils/
│       │   ├── theme/
│       │   └── rust/                 # Rust FFI bridge
│       └── pubspec.yaml
├── backend/                     # Rust REST API
│   ├── src/
│   │   └── main.rs (2795 lines)      # ALL BACKEND CODE IN ONE FILE
│   ├── Cargo.toml
│   ├── .env
│   ├── data/
│   │   └── dev.db                    # SQLite database
│   ├── migrations/
│   └── docker-compose.{dev,prod,base}.yml
├── crates/
│   └── icp_core/                     # Rust FFI library
├── scripts/                          # Build helpers
├── justfile                          # Build automation
└── TODO.md                           # Feature roadmap
```

---

## 3. Authentication & Security Mechanisms

### Frontend Security
1. **Private Key Storage** (`SecureIdentityRepository`):
   - Private keys stored in platform-native secure storage (Android Keychain, iOS Keychain)
   - Mnemonics also encrypted in secure storage
   - Non-sensitive data in regular JSON files

2. **Signature Generation** (`ScriptSignatureService`):
   - Signs script operations (upload, update, delete, publish) with author's private key
   - Creates canonical JSON payload (alphabetically sorted keys) for deterministic signatures
   - Supports both Ed25519 and secp256k1 algorithms
   - Timestamp included in all signatures

3. **Identity Management** (`IdentityController`):
   - Multiple identity support
   - Active identity selection
   - Identity profiles with extended metadata

### Backend Security
1. **Signature Verification Functions**:
   - `verify_ed25519_signature()` - Verifies Ed25519 signatures against payload
   - `verify_secp256k1_signature()` - Verifies secp256k1 ECDSA signatures
   - `create_canonical_payload()` - Ensures deterministic JSON for verification
   - **Dual-support**: Tries Ed25519 first, then secp256k1 for compatibility

2. **Operation-Specific Verification**:
   - `verify_script_upload_signature()` - Upload payload with title, description, category, lua_source, version, tags
   - `verify_script_update_signature()` - Update payload with optional fields only
   - `verify_script_deletion_signature()` - Delete payload with script_id, author_principal
   - `verify_script_publish_signature()` - Publish payload (is_public = true)

3. **Credential Validation**:
   - `validate_credentials()` - Checks principal and public key patterns
   - `validate_signature()` - Initial signature presence/format check
   - **Test Bypass**: `test-auth-token` bypasses verification in development

4. **Database-Level Security**:
   - No explicit user roles/permissions stored
   - Script ownership determined by `author_principal` + signature verification
   - Profile access: anyone can read via principal, but updates require verification

---

## 4. Database Schema (SQLite)

### Scripts Table
```sql
CREATE TABLE scripts (
  id TEXT PRIMARY KEY,                    -- UUID (LIMITATION: should be slug)
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL,
  tags TEXT,                              -- JSON array or comma-separated
  lua_source TEXT NOT NULL,               -- Lua script source code
  author_name TEXT NOT NULL,              -- User-provided name
  author_id TEXT,                         -- User ID (optional)
  author_principal TEXT,                  -- ICP principal ID
  author_public_key TEXT,                 -- Base64-encoded public key
  upload_signature TEXT,                  -- Signature of upload
  canister_ids TEXT,                      -- JSON array of canister IDs
  icon_url TEXT,                          -- Script icon/avatar
  screenshots TEXT,                       -- JSON array of screenshot URLs
  version TEXT,                           -- Semantic versioning
  compatibility TEXT,                     -- Compatible IC SDK versions
  price REAL DEFAULT 0.0,                 -- Price in USD
  is_public INTEGER DEFAULT 1,            -- Boolean (0/1)
  downloads INTEGER DEFAULT 0,
  rating REAL DEFAULT 0.0,                -- Average rating
  review_count INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,               -- ISO 8601 timestamp
  updated_at TEXT NOT NULL
);
```

### Reviews Table
```sql
CREATE TABLE reviews (
  id TEXT PRIMARY KEY,
  script_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE
);
```

### Identity Profiles Table
```sql
CREATE TABLE identity_profiles (
  id TEXT PRIMARY KEY,
  principal TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  username TEXT,
  contact_email TEXT,                     -- Email validation required
  contact_telegram TEXT,
  contact_twitter TEXT,
  contact_discord TEXT,
  website_url TEXT,                       -- Must start with http(s)://
  bio TEXT,
  metadata TEXT,                          -- JSON object for extensions
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

### Key Indexes
- `idx_reviews_script_id` on reviews.script_id
- `idx_identity_profiles_principal` on identity_profiles.principal (UNIQUE)

---

## 5. API Endpoints

### Health & Status
- `GET /api/v1/health` - Server health check with environment info
- `GET /api/v1/ping` - Simple ping test

### Scripts (Read)
- `GET /api/v1/scripts` - List public scripts (pagination: limit, offset)
  - Query params: `limit`, `offset`, `category`
- `GET /api/v1/scripts/:id` - Get specific script by ID
  - Query param: `includePrivate` (requires signature verification if true)
- `GET /api/v1/scripts/count` - Total public scripts count
- `GET /api/v1/scripts/category/:category` - Scripts by category
- `GET /api/v1/scripts/trending` - Trending scripts (sorted by downloads DESC)
- `GET /api/v1/scripts/featured` - Featured scripts (hardcoded in backend)
- `GET /api/v1/scripts/compatible` - Scripts compatible with canister type
  - Query param: `compatibility`

### Scripts (Write) - **REQUIRE SIGNATURE VERIFICATION**
- `POST /api/v1/scripts` - Create/upload new script
  - Body: title, description, category, lua_source, author_name, version, tags, compatibility
  - Security: `signature`, `author_public_key`, `author_principal`
- `PUT /api/v1/scripts/:id` - Update existing script
  - Body: Any fields to update (optional fields)
  - Security: Same as create
- `DELETE /api/v1/scripts/:id` - Delete script
  - Body: Empty or with credentials
  - Security: Same as create
- `POST /api/v1/scripts/:id/publish` - Publish to marketplace (make public)
  - Body: Empty or confirmation fields
  - Security: Same as create

### Search
- `POST /api/v1/scripts/search` - Advanced search
  - Body: `query`, `category`, `canisterId`, `minRating`, `maxPrice`, `sortBy`, `sortOrder`, `limit`, `offset`
  - Returns: `scripts[]`, `total`, `limit`, `offset`

### Reviews
- `GET /api/v1/scripts/:id/reviews` - Get script reviews (pagination)
  - Query params: `limit`, `offset`
- `POST /api/v1/scripts/:id/reviews` - Create review
  - Body: `userId`, `rating` (1-5), `comment` (optional)

### Statistics
- `GET /api/v1/marketplace-stats` - Global marketplace statistics
  - Returns: `totalScripts`, `totalDownloads`, `averageRating`, `timestamp`
- `POST /api/v1/update-script-stats` - Update download/engagement counters
  - Body: `scriptId`, `incrementDownloads` (optional)

### Identity & Profiles
- `GET /api/v1/identities/:principal/profile` - Get identity profile by principal
  - Public read endpoint
- `POST /api/v1/identities/profile` - Create/update own profile
  - Body: principal, display_name, username, contact_email, contact_telegram, contact_twitter, contact_discord, website_url, bio, metadata
  - **NOTE**: No explicit signature requirement in current code (potential gap)

### Development (Dev-only)
- `POST /api/dev/reset-database` - Nuke all data and reinitialize
  - Environment check: only in development mode

---

## 6. Script Upload/Download Implementation

### Upload Flow (Frontend)
1. User creates/edits script locally via `ScriptCreationScreen` or editor
2. Script saved to local storage via `ScriptRepository`
3. User initiates "Publish to Marketplace" from script menu
4. `script_upload_screen.dart` handles upload workflow:
   - Collects metadata (title, description, category, tags, version, compatibility)
   - Calls `ScriptSignatureService.signScriptUpload()` to generate signature
   - POSTs to `/api/v1/scripts` with signature in body
5. Backend verifies signature via `verify_script_upload_signature()`
6. If valid, script inserted into database with author_principal and author_public_key
7. Response includes generated script ID

### Upload Security
- **Client**: Signs canonical JSON payload with private key
- **Server**: Verifies signature matches public key and payload hasn't been tampered
- **Supported Algorithms**: Ed25519 (primary), secp256k1 (fallback)

### Download Flow (Frontend)
1. User browses marketplace via `marketplace_screen.dart` or `scripts_screen.dart`
2. Marketplace UI fetches scripts via `MarketplaceOpenApiService.searchScripts()`
3. User clicks "Download" on script card
4. Downloaded script saved to `ScriptRepository` with metadata preserved
5. Download tracked in `DownloadHistoryService`
6. Backend increments `downloads` counter via `/api/v1/update-script-stats`

### Download Tracking
- `DownloadHistoryService` maintains local list of downloaded script IDs
- UI shows visual indicator (checkmark, "Downloaded" badge) on marketplace cards
- No user authentication required for downloads (public scripts only)

---

## 7. Marketplace Features Implemented

### Search & Discovery
- ✅ Full-text search (query on title, description, category)
- ✅ Category filtering
- ✅ Price range filtering (minPrice, maxPrice)
- ✅ Rating-based filtering (minRating)
- ✅ Multiple sort options: createdAt, rating, downloads, price, title
- ✅ Ascending/descending sort order
- ✅ Pagination with limit/offset
- ✅ Infinite scroll load-more pattern

### Script Metadata
- ✅ Title, description, category, tags, version
- ✅ Author info (name, principal, public key)
- ✅ Pricing (price, currency assumptions)
- ✅ Icon URL and screenshots
- ✅ Canister compatibility list
- ✅ Rating and review count
- ✅ Download counter
- ✅ Visibility flag (public/private)

### Review System
- ✅ 1-5 star rating system
- ✅ Optional comments/reviews
- ✅ User attribution
- ✅ Timestamp tracking
- ✅ Foreign key relationship to scripts

### Trending/Featured/Recommendations
- ✅ Trending scripts endpoint (sorted by downloads)
- ✅ Featured scripts endpoint (hardcoded list)
- ✅ Compatible scripts endpoint (by canister type)
- ⏳ Personalized recommendations (in TODO)

### Publishing
- ✅ Local-to-marketplace publishing (create_script)
- ✅ Publish (set is_public=true) with signature
- ✅ Update scripts with version management
- ✅ Delete scripts (with signature verification)

---

## 8. Profile Management Implementation

### Identity Model (`ProfileKeypair`)
- **Location**: Flutter local storage via `SecureIdentityRepository`
- **Fields**:
  - id (UUID)
  - label (user-friendly name)
  - principal (ICP principal)
  - algorithm (Ed25519 or secp256k1)
  - mnemonic (12-word seed phrase - encrypted)
  - privateKey (base64, encrypted)
  - publicKey (base64)
  - createdAt timestamp

### Profile Model (`IdentityProfile`)
- **Location**: Rust backend database (`identity_profiles` table)
- **Fields**:
  - id (UUID)
  - principal (unique, linked to identity)
  - displayName (required, max 120 chars)
  - username (optional)
  - contactEmail (optional, validated)
  - contactTelegram, contactTwitter, contactDiscord (optional)
  - websiteUrl (optional, requires http/https)
  - bio (optional)
  - metadata (JSON object for extensions)
  - timestamps (created_at, updated_at)

### Profile Management Flows

**Creating/Generating Identity** (Frontend):
1. User navigates to Identities tab
2. Clicks "Create New Identity"
3. Chooses algorithm (Ed25519 or secp256k1)
4. System generates: mnemonic, private key, public key
5. User optionally provides custom label
6. Saved to secure storage via `SecureIdentityRepository`

**Setting Up Profile** (Frontend → Backend):
1. User clicks "Edit Profile" on identity
2. `IdentityProfileSheet` widget opens
3. User fills in displayName (required) + optional social contacts
4. Frontend POSTs to `/api/v1/identities/profile`
5. Backend saves/updates profile via UPSERT (ON CONFLICT)
6. Response includes complete profile object

**Reading Profiles** (Frontend):
1. Can fetch by principal: `GET /api/v1/identities/{principal}/profile`
2. Backend returns profile or 404 if not found
3. Frontend displays on author cards in marketplace

### Key Limitations
- ⚠️ No explicit "signature requirement" for profile updates (potential security gap)
- ⚠️ Anyone can overwrite profile by knowing principal (should add signature requirement)
- ✅ Display name validation: required, max 120 chars
- ✅ Email validation: must contain @ and .
- ✅ URL validation: must start with http:// or https://
- ✅ Metadata: must be valid JSON object if provided

---

## 9. Existing Security Measures

### Cryptographic
1. ✅ **Signature Verification**: Ed25519 + secp256k1 support
2. ✅ **Canonical JSON**: Deterministic payload construction for signature verification
3. ✅ **Base64 Encoding**: All keys/signatures base64-encoded
4. ✅ **Multiple Hash Algorithms**: SHA-256 for secp256k1, raw for Ed25519

### Transport
1. ✅ **CORS Enabled**: Poem middleware handles CORS headers
2. ✅ **HTTPS Recommended**: Deployed behind Cloudflare Tunnel
3. ⚠️ **Test Auth Bypass**: `test-auth-token` bypasses verification (dev-only, but dangerous)

### Database
1. ✅ **Parameterized Queries**: sqlx uses bind parameters (no SQL injection)
2. ✅ **Foreign Keys**: Reviews linked to scripts with CASCADE delete
3. ✅ **Unique Constraints**: Principal must be unique in identity_profiles

### Input Validation
1. ✅ **Email Validation**: Simple @ and . check
2. ✅ **URL Validation**: Requires http/https scheme
3. ✅ **Display Name Length**: Max 120 characters
4. ✅ **Search Limit Bounds**: 1-100 results per query
5. ⚠️ **Tags Sorting**: Validates and sorts tags for canonical representation
6. ⚠️ **String Trimming**: Sanitizes optional fields

### Known Gaps
1. ⚠️ **No Profile Update Signature**: Profile endpoint doesn't verify signatures (anyone can update with just principal)
2. ⚠️ **No Rate Limiting**: Backend accepts unlimited requests
3. ⚠️ **No API Keys**: No admin authentication for dev endpoints
4. ⚠️ **Test Bypass**: `test-auth-token` should not be in production
5. ⚠️ **No HTTPS Enforcement**: Development allows HTTP

---

## 10. Current UI/UX Status

### Implemented Screens
1. **Scripts Screen** (1624 lines)
   - ✅ Tabbed interface: "My Scripts" + "Marketplace"
   - ✅ Local script listing with edit/delete/run/publish actions
   - ✅ Marketplace search and browse
   - ⚠️ **UI ISSUE**: Marketplace feels disconnected from local scripts
   - ⚠️ **UX ISSUE**: No unified "all my content" view

2. **Marketplace Screen** (676 lines)
   - ✅ Dedicated marketplace tab
   - ✅ Search, filter, sort
   - ✅ Script cards with metadata
   - ⚠️ **REDUNDANT**: Duplicates marketplace functionality from scripts_screen
   - ⚠️ **UX ISSUE**: Users unclear which view to use

3. **Identity Management** (806 lines)
   - ✅ Create identities
   - ✅ View identity details (principal, keys, mnemonic)
   - ✅ Edit profiles (display name, social contacts)
   - ✅ Rename/delete identities
   - ⚠️ **UX ISSUE**: Profile completion not enforced or incentivized
   - ⚠️ **UX ISSUE**: No visual indicator of profile completeness

4. **Script Upload** (736 lines)
   - ✅ Metadata form (title, description, category, tags, version)
   - ✅ Lua editor
   - ✅ Signature generation + upload
   - ⚠️ **UX ISSUE**: Multi-step form could be clearer

5. **Bookmarks & Download History** (337 + 1237 lines)
   - ✅ Download history tracking
   - ✅ Bookmark management
   - ⚠️ **UX ISSUE**: Limited filtering/organization

### UI Components
- ✅ Script cards (local and marketplace)
- ✅ Search bar with filters
- ✅ Loading indicators and shimmer effects
- ✅ Error displays
- ✅ Modern navigation bar
- ✅ Dialog-based forms (profile, script details)
- ⚠️ Inconsistent modal presentation

### Known UX Limitations
1. **No unified script management**:
   - Local scripts and marketplace scripts are siloed
   - Users must switch tabs to compare/publish

2. **Marketplace discoverability**:
   - Search results don't surface trending/popular scripts
   - No personalized recommendations
   - No "you might like" suggestions

3. **Script lifecycle gaps**:
   - No in-app update notifications for downloaded scripts
   - No version comparison between local and marketplace
   - No easy way to re-publish updated versions

4. **Profile management confusion**:
   - Profile is separate from identity creation
   - No clear "complete your profile" flow
   - No profile preview before saving

5. **Visual design**:
   - Inconsistent modal/dialog styling
   - No clear visual hierarchy for actions
   - Limited visual feedback for async operations

---

## 11. File Paths Reference (Key Components)

### Core Backend (Rust)
| File                   | Lines | Purpose                       |
|------------------------|-------|-------------------------------|
| `/backend/src/main.rs` | 2795  | All backend code (monolithic) |
| `/backend/Cargo.toml`  | 40    | Rust dependencies             |
| `/backend/.env`        | 376   | Environment configuration     |

### Core Frontend (Flutter)
| File                                               | Lines | Purpose                     |
|----------------------------------------------------|-------|-----------------------------|
| `/apps/autorun_flutter/lib/main.dart`              | 169   | App entry, navigation setup |
| `/apps/autorun_flutter/lib/config/app_config.dart` | 70    | API endpoint config         |
| `/apps/autorun_flutter/pubspec.yaml`               | 107   | Flutter dependencies        |

### Frontend Services
| File                                              | Lines | Purpose                         |
|---------------------------------------------------|-------|---------------------------------|
| `/lib/services/marketplace_open_api_service.dart` | ~200  | HTTP API client for marketplace |
| `/lib/services/script_signature_service.dart`     | ~300  | Ed25519/secp256k1 signing       |
| `/lib/services/secure_identity_repository.dart`   | ~300  | Encrypted key storage           |
| `/lib/services/script_repository.dart`            | 84    | Local script file storage       |
| `/lib/services/download_history_service.dart`     | ~150  | Download tracking               |

### Frontend Controllers
| File                                        | Lines | Purpose                           |
|---------------------------------------------|-------|-----------------------------------|
| `/lib/controllers/identity_controller.dart` | 6947  | Identity lifecycle management     |
| `/lib/controllers/script_controller.dart`   | 8919  | Local script lifecycle management |

### Frontend Screens (UI Pages)
| File                                        | Lines | Primary Purpose                      |
|---------------------------------------------|-------|--------------------------------------|
| `/lib/screens/scripts_screen.dart`          | 1624  | Local scripts + marketplace (tabbed) |
| `/lib/screens/marketplace_screen.dart`      | 676   | Dedicated marketplace view           |
| `/lib/screens/identity_home_page.dart`      | 806   | Identity management and profiles     |
| `/lib/screens/script_upload_screen.dart`    | 736   | Script publish workflow              |
| `/lib/screens/script_creation_screen.dart`  | 490   | Create new local script              |
| `/lib/screens/bookmarks_screen.dart`        | 1237  | Bookmarks + canister client          |
| `/lib/screens/download_history_screen.dart` | 337   | Download tracking                    |

### Frontend Data Models
| File                                  | Purpose                            |
|---------------------------------------|------------------------------------|
| `/lib/models/identity_profile.dart`   | Backend profile model + draft      |
| `/lib/models/marketplace_script.dart` | Script with all marketplace fields |
| `/lib/models/script_record.dart`      | Local script representation        |
| `/lib/models/script_template.dart`    | Script templates for creation      |
| `/lib/models/profile_keypair.dart`    | Local identity (keys, mnemonic)    |

### Frontend Widgets/Components
- `/lib/widgets/script_card.dart` - Script display card
- `/lib/widgets/marketplace_search_bar.dart` - Search + filters
- `/lib/widgets/identity_profile_sheet.dart` - Profile editor
- `/lib/widgets/script_details_dialog.dart` - Script details modal
- `/lib/widgets/script_app_host.dart` - Script execution host
- 15+ additional utility widgets

---

## 12. What Exists vs. What User Wants

### Current Marketplace Features ✅
- Full-text search with filters
- Category browsing
- Rating/review system
- Download tracking
- Script versioning
- Author attribution
- Signature-verified uploads

### UX Improvements Needed (From TODO.md)

| Feature                                    | Status      | Difficulty |
|--------------------------------------------|-------------|------------|
| **Unified Script Management**              | Not started | High       |
| Hybrid view of local + marketplace scripts |             |            |
| Source badges (Local vs Marketplace)       |             |            |
| Unified search across both                 |             |            |
| Smart filtering                            |             |            |
| ||||
| **Seamless Publishing** | Partial | Medium |
| Auto-populate metadata from local analysis | TODO | |
| Progressive disclosure for options | TODO | |
| ||||
| **Discovery & Recommendations** | Not started | High |
| "You might like" suggestions | TODO | |
| Trending in user's categories | TODO | |
| Similar script recommendations | TODO | |
| Collaborative filtering | TODO | |
| Personalized homepage | TODO | |
| ||||
| **Enhanced Script Creation** | Partial | Medium |
| Marketplace templates in creation | TODO | |
| "Based on your scripts" suggestions | TODO | |
| AI-powered suggestions | TODO | |
| ||||
| **Version Management** | Not started | Medium |
| Update notifications | TODO | |
| Version history & rollback | TODO | |
| Auto-update preferences | TODO | |
| Change logs | TODO | |
| ||||
| **Rich Script Cards** | Partial | Medium |
| Complexity indicators | TODO | |
| Usage statistics | TODO | |
| Quick action buttons | TODO | |
| Script preview | TODO | |
| Status indicators | TODO | |
| ||||
| **Collaborative Features** | Not started | Low |
| Shareable links | TODO | |
| Forking | TODO | |
| Collections/playlists | TODO | |
| Comments/discussions | TODO | |

### Key User Frustrations (Likely)
1. **Confusion between marketplace and local scripts** - No unified view
2. **Unclear publishing workflow** - Multiple steps, not guided
3. **No discovery beyond search** - Trending/recommendations missing
4. **Profile feels disconnected** - Separate from identity creation
5. **No guidance on script quality** - Complexity levels missing

---

## 13. Critical Implementation Notes

### Database Limitations
1. **Script IDs are random UUIDs** - Should be user-provided slugs for stable marketplace links
   - This is documented in `/backend/README.md` line 164
   - Must fix before production

2. **Profile updates unprotected** - Anyone knowing a principal can update profile
   - Should add signature requirement to POST `/api/v1/identities/profile`

### Backend Monolithic Design
- All 2795 lines of backend code in single `main.rs`
- Makes it harder to add new features incrementally
- Consider refactoring into modules in future phases

### Frontend State Management
- Uses ChangeNotifier + provider pattern (not the latest Provider syntax)
- Controllers directly manage file I/O and network calls
- Could benefit from cleaner separation of concerns

### Signature System Details
- **Canonical JSON**: Keys sorted alphabetically, no extra whitespace
- **Test Bypass**: `test-auth-token` in signature field bypasses all verification
- **Dual Algorithm Support**: Ed25519 tried first, then secp256k1
- **Timestamp**: Included in signature payload for replay protection

### Build System
- Uses `justfile` for cross-platform builds
- Scripts in `/scripts/` directory handle platform-specific compilation
- All platforms build to standard locations for Flutter integration

---

## 14. Summary Table

| Aspect                 | Status     | Notes                                                               |
|------------------------|------------|---------------------------------------------------------------------|
| **Core Functionality** | ✅ Complete | Scripts, marketplace, identity management working                   |
| **Security**           | ⚠️ Mostly  | Signature verification implemented, but profile updates unprotected |
| **Database**           | ✅ Good     | SQLite with proper schema, but needs slug IDs                       |
| **API**                | ✅ Complete | 20+ endpoints implemented with proper validation                    |
| **Frontend UX**        | ⚠️ Basic   | Functional but confusing navigation, needs unification              |
| **Marketplace**        | ✅ Good     | Search, filter, download, publish all working                       |
| **Discovery**          | ⏳ Partial  | Search works, recommendations/trending stubbed                      |
| **Version Management** | ⏳ Partial  | Version field exists, but no update notifications                   |
| **Profile System**     | ✅ Good     | Full CRUD, but missing some validations and signature check         |
| **Testing**            | ⏳ Partial  | Backend has signature tests, frontend needs more coverage           |
| **Documentation**      | ⏳ Partial  | README files exist, API docs in progress                            |

---

## 15. Next Steps for User

Based on this overview, the app needs:

1. **UI/UX Consolidation** - Merge marketplace and local scripts views
2. **Profile Security** - Add signature verification to profile updates
3. **Discovery Features** - Implement trending, recommendations, personalization
4. **ID System Fix** - Replace UUIDs with user-supplied slugs
5. **Testing & QA** - Comprehensive testing before production
6. **Documentation** - API docs, user guide, deployment guide
