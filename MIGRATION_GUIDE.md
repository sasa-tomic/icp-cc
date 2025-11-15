# Migration Guide: Removing Proxy API Server

## Overview

This migration removes the unnecessary Node.js proxy API server and implements a **direct Flutter → Appwrite Functions** architecture.
This eliminates a security vulnerability where API keys were hardcoded in the Flutter app.

## Architectural Change

### Before (❌ Insecure)
```
Flutter App (with API keys) → Node.js API Server → Appwrite Functions → Database
```

### After (✅ Secure)
```
Flutter App (no API keys) → Appwrite Functions with public endpoint (with private environment variables) → Database
```

Appwrite functions URL should have format similar to https://64d4d22db370ae41a32e.appwrite.global

## Impact Analysis

### 🗂️ Directories Impacted

#### 1. **REMOVE ENTIRELY**:
```
/home/sat/projects/icp-cc/appwrite-api-server/
├── src/
│   └── server.js          # ❌ DELETE - Unnecessary proxy
├── package.json
├── tests/
└── node_modules/
```

#### 2. **MODIFY**:

All user-controlled code (such as flutter or rust library) that tries to send some appwrite confidential material to the appwrite endpoint(s).
Having a project id in the function URL is perfectly fine - project id is not a secret. Having a default project id is also fine. Having a fixed project id that cannot be overriden is NOT fine.

#### 3. **NEW**:
```
/home/sat/projects/icp-cc/appwrite-functions/   # ✅ NEW - Temporary function examples
└── stats.js                                     # ✅ NEW - Example function
```

#### 4. **DOCUMENTATION**:
```
/home/sat/projects/icp-cc/
├── TODO.md                                      # ✅ UPDATED - Security fix documented
├── LOCAL_DEVELOPMENT.md                         # ❌ UPDATE NEEDED - Remove proxy server steps
├── AGENTS.md                                    # ❌ UPDATE NEEDED - New architecture
└── MIGRATION_GUIDE.md                           # ✅ NEW - This file
```

#### 6. **BUILD SCRIPTS**:
```
/home/sat/projects/icp-cc/justfile              # ❌ UPDATE NEEDED - Remove API server targets
```

## Appwrite Function Secrets Setup

The marketplace deployment tool **automatically sets environment variables**:

```rust
// marketplace-deploy/src/functions.rs
"variables": [
    {
        "key": "APPWRITE_FUNCTION_ENDPOINT",
        "value": &self.config.endpoint
    },
    {
        "key": "APPWRITE_FUNCTION_PROJECT_ID",
        "value": &self.config.project_id
    },
    {
        "key": "APPWRITE_FUNCTION_API_KEY",
        "value": &self.config.api_key
    },
    // ... more variables
]
```

### Required Environment Variables

Each marketplace function needs these variables:

```bash
# Appwrite Connection
APPWRITE_FUNCTION_ENDPOINT=https://fra.cloud.appwrite.io/v1
APPWRITE_FUNCTION_PROJECT_ID=your-project-id
APPWRITE_FUNCTION_API_KEY=your-api-key

# Database Configuration
DATABASE_ID=marketplace_db
SCRIPTS_COLLECTION_ID=scripts
USERS_COLLECTION_ID=users
REVIEWS_COLLECTION_ID=reviews
PURCHASES_COLLECTION_ID=purchases
```

## Validation Checklist

- [ ] ❌ **DELETE**: `/appwrite-api-server/` directory
- [ ] ✅ **VERIFY**: No API keys in Flutter app
- [ ] ✅ **VERIFY**: Functions have environment variables
- [ ] ✅ **TEST**: Marketplace stats endpoint works
- [ ] ✅ **TEST**: Marketplace search endpoint works
- [ ] ✅ **UPDATE**: Documentation removes proxy references
- [ ] ✅ **UPDATE**: Justfile removes proxy targets
- [ ] ✅ **TEST**: Both local and production environments work
- [ ] ✅ **SECURITY**: Production uses read-only API keys
- [ ] ✅ **MONITORING**: Function execution is logged

## Benefits of Migration

1. **🔒 Security**: No API keys exposed to clients
2. **🚀 Performance**: Fewer network hops, lower latency
3. **💰 Cost**: One less service to run and maintain
4. **🛠️ Simplicity**: Fewer moving parts, easier debugging
5. **📈 Scalability**: Direct Appwrite Functions scale automatically

## References

- [Appwrite Functions Documentation](https://appwrite.io/docs/products/functions)
- [Appwrite Function Environment Variables](https://appwrite.io/docs/products/functions/functions)
