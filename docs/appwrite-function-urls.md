# Appwrite API Endpoints Guide

## API Endpoint URLs

This project uses Appwrite Sites with API routes for all backend functionality. The frontend communicates with these endpoints using relative paths.

## Production API Endpoints

**Base URL**: `https://icp-autorun.appwrite.network/api/*`

### Available Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/search_scripts` | POST | Search scripts with advanced filtering |
| `/api/scripts` | GET | Get all scripts (with pagination) |
| `/api/scripts/[id]` | GET | Get script details by ID |
| `/api/scripts/[id]` | PUT | Update existing script |
| `/api/scripts/[id]` | DELETE | Delete a script |
| `/api/scripts/featured` | GET | Get featured scripts |
| `/api/scripts/trending` | GET | Get trending scripts |
| `/api/scripts/category/[category]` | GET | Get scripts by category |
| `/api/scripts/[id]/reviews` | GET | Get script reviews |
| `/api/scripts/compatible` | GET | Get scripts compatible with specific canisters |
| `/api/scripts/validate` | POST | Validate Lua script syntax |
| `/api/get_marketplace_stats` | GET | Get marketplace statistics |
| `/api/process_purchase` | POST | Process script purchase |
| `/api/update_script_stats` | POST | Update script statistics |

## Local Development API Endpoints

**Base URL**: `http://localhost:5173/api/*`

The same endpoints are available locally when running the development server.

## Frontend Integration

The Flutter app uses the `MarketplaceOpenApiService` to communicate with these endpoints:

```dart
// Base URL configuration
final String _baseUrl = '${AppConfig.appwriteEndpoint}/api';

// Example API call
final response = await http.post(
  Uri.parse('$_baseUrl/search_scripts'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode(searchParams),
);
```

## Architecture Benefits

Using Appwrite Sites with API routes provides:

1. **Unified Deployment**: Frontend and API deployed together
2. **Automatic URLs**: Public URLs provided automatically
3. **Git-based Deployment**: Simple deployment workflow
4. **Framework Support**: Native API route support
5. **Better Integration**: Shared infrastructure

## Configuration

The API endpoints are automatically configured based on the environment:

- **Production**: Uses `https://icp-autorun.appwrite.network/api/*`
- **Local Development**: Uses `http://localhost:5173/api/*`

## References

- [Appwrite Sites Documentation](https://appwrite.io/docs/products/sites)
- [Sites API Routes](https://appwrite.io/docs/products/sites/api-routes)