# Appwrite Function URLs Guide

## ⚠️ Architecture Change Notice

**IMPORTANT**: This document is preserved for historical reference. We have decided to migrate from Appwrite Functions to Appwrite Sites for our project architecture. See [Appwrite Sites vs Functions](./appwrite-sites-vs-functions.md) for the detailed decision.

The new approach will use Appwrite Sites with API routes instead of standalone Functions.

## Legacy: Function URL Format

### Standard Format
The correct URL format to access Appwrite functions directly is:

```
https://<function-id>.<region>.cloud.appwrite.io
```

### Your Project Functions (Legacy)

Based on your Appwrite configuration (`appwrite.config.json`), your project is hosted in the **Frankfurt (fra)** region.

Your deployed functions (to be migrated to Sites):

| Function ID | Function Name | Legacy URL | New Site Route | Status |
|-------------|---------------|-----------|----------------|---------|
| `search_scripts` | Search Scripts | `https://search_scripts.fra.cloud.appwrite.io` | `/api/search_scripts` | Deployed but failed |
| `process_purchase` | Process Purchase | `https://process_purchase.fra.cloud.appwrite.io` | `/api/process_purchase` | Deployed but failed |
| `update_script_stats` | Update Script Stats | `https://update_script_stats.fra.cloud.appwrite.io` | `/api/update_script_stats` | Deployed but failed |

## Migration to Sites

### New Architecture
Instead of separate Functions, we'll use a single Appwrite Site with API routes:

```javascript
// Old approach (Functions)
const searchResults = await fetch('https://search_scripts.fra.cloud.appwrite.io?query=lua');

// New approach (Sites API routes)
const searchResults = await fetch('/api/search_scripts?query=lua');
```

### Benefits of Migration
1. **Simplified Deployment**: Git-based deployment instead of individual function deployments
2. **Automatic Public URLs**: Site provides public URLs automatically
3. **Better Integration**: Frontend and API deployed together
4. **Framework Support**: Native support for SSR and API routes
5. **Domain Management**: Built-in custom domain support

## Current Status (Legacy Functions)

All three functions are currently in a **failed deployment state** (`latestDeploymentStatus: failed`). Since we're migrating to Sites, we will not be fixing these deployments.

## Migration Steps

1. **Create Appwrite Site** with Git integration
2. **Convert Functions to API Routes**:
   - Move function code to `/api/search_scripts`, `/api/process_purchase`, `/api/update_script_stats`
   - Adapt code for the Site runtime environment
3. **Update Frontend URLs** to use relative paths instead of absolute function URLs
4. **Deploy Site** using Git integration
5. **Test API Routes** to ensure functionality
6. **Configure Custom Domain** (optional)

## Frontend Integration Changes

### Before (Functions)
```javascript
// API client configuration
const API_BASE_URL = 'https://search_scripts.fra.cloud.appwrite.io';

// Function calls
const searchResults = await fetch(`${API_BASE_URL}?query=lua`);
```

### After (Sites)
```javascript
// API calls use relative paths
const searchResults = await fetch('/api/search_scripts?query=lua');
```

## References

- [Appwrite Sites vs Functions Decision](./appwrite-sites-vs-functions.md)
- [Appwrite Sites Documentation](https://appwrite.io/docs/products/sites)
- [Sites Domain Configuration](https://appwrite.io/docs/products/sites/domains)