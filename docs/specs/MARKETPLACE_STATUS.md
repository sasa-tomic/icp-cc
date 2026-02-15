# Marketplace Implementation Status

**Last Updated:** 2025-02-15

## Overview

The marketplace has a **hybrid implementation**: core features (search, upload, browse) are functional but need testing, while monetization features are **explicitly blocked** until the core is production-ready.

**Current Focus:** Make free script marketplace fully usable with comprehensive tests.

## Not Implemented (BLOCKED)

> **DO NOT IMPLEMENT** until core marketplace is fully tested and production-ready.
> Free scripts must work perfectly before adding payment complexity.

### Payment Processing

**Status:** Not Started

Current behavior when user tries to buy paid script:
```dart
// script_card.dart:428-458
showDialog(
  builder: (context) => AlertDialog(
    title: const Text('Payments Coming Soon'),
    content: const Text(
      'Paid scripts will be available in the next update!',
    ),
  ),
);
```

**Missing:**
- ICP ledger canister integration
- Wallet connection
- Transaction signing for purchases
- Payment verification

### Purchase Records

**Status:** Model Only

The `PurchaseRecord` model exists (`lib/models/purchase_record.dart`) but:
- No API endpoints to create purchase
- No API to get user purchases
- No API to verify ownership

**Required Endpoints:**
```
POST /api/v1/purchases          - Create purchase
GET  /api/v1/purchases/{userId} - Get user purchases
GET  /api/v1/purchases/verify/{scriptId} - Verify ownership
```

### Script Reviews (Write)

**Status:** Read-Only

`getScriptReviews()` works, but no mutation endpoints:
- No `submitReview()` 
- No `updateReview()`
- No `deleteReview()`

**Required Endpoints:**
```
POST   /api/v1/scripts/{id}/reviews           - Submit
PUT    /api/v1/scripts/{id}/reviews/{reviewId} - Update
DELETE /api/v1/scripts/{id}/reviews/{reviewId} - Delete
```

### Favorites

**Status:** Model Field Only

`MarketplaceUser.favorites` field exists but no API:
- No add favorite
- No remove favorite
- No get favorites

### Shopping Cart

**Status:** Not Started

No cart model, service, or UI.

---

## API Endpoints Summary

**Base URL:** `https://icp-mp.kalaj.org/api/v1`

### Implemented Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/scripts/search` | POST | Search with filters |
| `/scripts/{id}` | GET | Script details |
| `/scripts` | POST | Upload new script |
| `/scripts/{id}` | PUT | Update script |
| `/scripts/{id}/delete` | POST | Delete script |
| `/scripts/featured` | GET | Featured scripts |
| `/scripts/trending` | GET | Trending scripts |
| `/scripts/category/{cat}` | GET | By category |
| `/scripts/{id}/reviews` | GET | Script reviews |
| `/scripts/compatible` | POST | Compatible scripts |
| `/marketplace-stats` | GET | Statistics |
| `/accounts` | POST | Register |
| `/accounts/{username}` | GET | Get account |
| `/accounts/{username}` | PATCH | Update account |
| `/accounts/by-public-key/{pk}` | GET | By public key |
| `/accounts/{username}/keys` | POST | Add key |
| `/accounts/{username}/keys/{id}` | DELETE | Remove key |

### Missing Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/purchases` | POST | Create purchase |
| `/purchases/{userId}` | GET | User purchases |
| `/scripts/{id}/reviews` | POST | Submit review |
| `/scripts/{id}/reviews/{id}` | PUT/DELETE | Modify review |
| `/users/{userId}/favorites` | GET/POST/DELETE | Favorites |

---

## Categories

12 predefined categories (code: `marketplace_open_api_service.dart:277-292`):

1. Example
2. Uncategorized
3. Gaming
4. Finance
5. DeFi
6. NFT
7. Social
8. Utilities
9. Development
10. Education
11. Entertainment
12. Business

---

## Data Flow

### Script Search
```
User Input → ScriptsScreen._searchQuery
    → MarketplaceOpenApiService.searchScripts()
    → POST /api/v1/scripts/search
    → MarketplaceSearchResult.scripts
    → ScriptsScreen._marketplaceScripts
    → ScriptCard widgets
```

### Script Upload
```
QuickUploadDialog → ScriptSignatureService.signScriptUpload()
    → MarketplaceOpenApiService.uploadScript()
    → POST /api/v1/scripts
    → MarketplaceScript returned
```

### Free Download
```
"Download FREE" click → MarketplaceOpenApiService.downloadScript()
    → GET /api/v1/scripts/{id} (checks price == 0)
    → ScriptRepository.saveScript() (local)
    → DownloadHistoryService.addToHistory()
```

### Paid Script (Current)
```
Price button click → Shows AlertDialog: "Payments Coming Soon"
    → (End - no actual payment)
```

---

## Test Coverage

| Area | Tests | Quality |
|------|-------|---------|
| MarketplaceScript model | `marketplace_script_test.dart` | Good |
| API Service | `marketplace_open_api_service_test.dart` | Good |
| Upload API | `script_upload_api_test.dart` | Good |
| Visibility E2E | `marketplace_visibility_test.dart` | Good |
| Upload Dialog | `quick_upload_dialog_test.dart` | Good |

**Missing Tests:**
- Payment flow (not implemented)
- Purchase records (not implemented)
- Favorites (not implemented)
