# Appwrite Sites vs Functions: Architecture Decision

This document explains why Appwrite Sites should be used instead of Appwrite Functions for our project architecture.

## Executive Summary

For our use case requiring public URLs and web functionality, **Appwrite Sites** is the correct choice over Appwrite Functions. Functions should only be used for standalone backend logic without frontend requirements.

## Key Differences

### Appwrite Sites
- **Purpose**: Static hosting and web applications
- **URLs**: Automatic public URLs with custom domain support
- **Deployment**: Git-based automatic deployments
- **Use Cases**:
  - Static sites and SPAs
  - SSR applications (Next.js, Nuxt, SvelteKit)
  - Web applications with public endpoints
  - Framework-native API routes

### Appwrite Functions
- **Purpose**: Serverless backend logic
- **URLs**: Require manual API endpoint configuration
- **Deployment**: Individual function deployment
- **Use Cases**:
  - Background processing
  - Standalone API endpoints
  - Complex computational tasks
  - Backend services without frontend

## Our Requirements Analysis

Based on our project needs:

1. ✅ **Public URLs Required** - Sites provide these automatically
2. ✅ **Web Application** - Sites are designed for web apps
3. ✅ **Frontend Integration** - Sites host both frontend and backend together
4. ❌ **Standalone Backend Logic** - Not our primary use case

## Migration Benefits

Switching from Functions to Sites provides:

1. **Automatic Public URLs**: No manual endpoint configuration needed
2. **Simplified Deployment**: Git-based deployment with builds
3. **Better Integration**: Frontend and API routes deployed together
4. **Domain Management**: Built-in custom domain support
5. **Framework Support**: Native SSR and API route support

## Recommended Architecture

```
Appwrite Site (https://icp-autorun.appwrite.network)
├── Frontend (SvelteKit)
├── API Routes (/api/*)
└── Static Assets
```

Instead of:
```
Appwrite Functions (Legacy)
├── search_scripts (https://search_scripts.fra.cloud.appwrite.io)
├── process_purchase (https://process_purchase.fra.cloud.appwrite.io)
└── update_script_stats (https://update_script_stats.fra.cloud.appwrite.io)
└── Separate Frontend Hosting
```

## Next Steps

1. Create new Appwrite Site
2. Migrate function code to site API routes
3. Update frontend to use relative URLs (`/api/search_scripts`)
4. Configure custom domain if needed
5. Deploy using Git integration

## References

- [Appwrite Sites Documentation](https://appwrite.io/docs/products/sites)
- [Sites vs Functions Comparison](https://appwrite.io/docs/products/sites/migrations/vercel)
- [Sites Domain Configuration](https://appwrite.io/docs/products/sites/domains)