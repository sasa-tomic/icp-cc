# ICP Marketplace API Server

A public Node.js API server that provides open access to the ICP Script Marketplace data. This server acts as a public gateway to the Appwrite backend, exposing only safe, read-only operations that don't require authentication.

## Features

- **Public Search**: Search scripts by keywords, category, canister ID, rating, and price
- **Script Details**: Get detailed information about individual scripts
- **Featured Scripts**: Access curated list of featured scripts
- **Trending Scripts**: Get most downloaded and highest-rated scripts
- **Category Browsing**: Browse scripts by category
- **Reviews**: Access public reviews and ratings
- **Canister Compatibility**: Search scripts compatible with specific ICP canisters
- **Script Validation**: Validate Lua script syntax
- **Marketplace Statistics**: Public marketplace statistics
- **Rate Limiting**: Protection against abuse with configurable rate limits
- **Security**: Input validation, sanitization, and secure headers

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Flutter App   │───▶│  API Server      │───▶│   Appwrite      │
│  (No Auth)      │    │ (Node.js/Express)│    │   Backend       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
  Public UI Layer        Public API Layer       Private Data Layer
```

### Security Model

- **Read-Only Access**: Only safe, read-only operations are exposed
- **No Authentication**: Public endpoints that don't require user credentials
- **Input Validation**: All inputs are validated and sanitized
- **Rate Limiting**: Protection against abuse and DDoS attacks
- **CORS Protection**: Configurable cross-origin resource sharing
- **Security Headers**: Helmet.js for secure HTTP headers

## Installation and Setup

### Prerequisites

- Node.js 18 or higher
- npm or yarn
- Appwrite project with marketplace setup

### Quick Start

1. **Clone and setup**:
   ```bash
   cd /path/to/icp-cc/appwrite-api-server
   npm install
   ```

2. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your Appwrite credentials
   ```

3. **Start the server**:
   ```bash
   # Development
   npm run dev

   # Production
   npm start
   ```

### Environment Variables

Create a `.env` file with the following variables:

```env
# Appwrite Configuration
APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1
APPWRITE_PROJECT_ID=68f7fc8b00255b20ed42
APPWRITE_API_KEY=your-admin-api-key

# Database Configuration
DATABASE_ID=marketplace_db
SCRIPTS_COLLECTION_ID=scripts
REVIEWS_COLLECTION_ID=reviews
SEARCH_FUNCTION_ID=search_scripts

# Server Configuration
PORT=3000
NODE_ENV=production
LOG_LEVEL=info

# CORS Configuration
ALLOWED_ORIGINS=http://localhost:3000,https://your-app-domain.com

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
```

## API Endpoints

### Base URL
```
http://localhost:3000/v1
```

### Scripts

#### Search Scripts
```http
GET /v1/scripts/search
```

**Query Parameters:**
- `q` (optional): Search query string
- `category` (optional): Script category
- `canister_id` (optional): Canister ID for compatibility
- `min_rating` (optional): Minimum rating (0-5)
- `max_price` (optional): Maximum price
- `sort_by` (optional): Sort field (createdAt, rating, downloads, price, title)
- `sort_order` (optional): Sort order (asc, desc)
- `limit` (optional): Results per page (max 100)
- `offset` (optional): Pagination offset

**Example:**
```bash
curl "http://localhost:3000/v1/scripts/search?q=gaming&category=Gaming&min_rating=4&limit=10"
```

#### Get Script Details
```http
GET /v1/scripts/{scriptId}
```

#### Get Featured Scripts
```http
GET /v1/scripts/featured?limit=10
```

#### Get Trending Scripts
```http
GET /v1/scripts/trending?limit=10
```

#### Get Scripts by Category
```http
GET /v1/scripts/category/{category}?limit=20&sort_by=rating&sort_order=desc
```

#### Get Scripts by Canister ID
```http
GET /v1/scripts/canister/{canisterId}?limit=20
```

#### Download Script (Free only)
```http
GET /v1/scripts/{scriptId}/download
```

### Reviews

#### Get Script Reviews
```http
GET /v1/scripts/{scriptId}/reviews?limit=20&verified_only=true
```

### Utilities

#### Validate Script Syntax
```http
POST /v1/scripts/validate
Content-Type: application/json

{
  "lua_source": "print('Hello, World!')"
}
```

#### Get Marketplace Statistics
```http
GET /v1/stats
```

## Response Format

### Success Response
```json
{
  "scripts": [
    {
      "$id": "script_123",
      "title": "ICP Gaming Script",
      "description": "A script for gaming on ICP",
      "category": "Gaming",
      "price": 0,
      "rating": 4.5,
      "downloads": 150,
      "authorName": "DevUser",
      "createdAt": "2023-10-22T10:00:00.000Z"
    }
  ],
  "total": 100,
  "hasMore": true,
  "offset": 0,
  "limit": 20
}
```

### Error Response
```json
{
  "error": "Validation failed",
  "details": [
    {
      "field": "min_rating",
      "message": "Minimum rating must be between 0 and 5"
    }
  ]
}
```

## Rate Limiting

- **Window**: 15 minutes
- **Requests**: 100 per IP per window
- **Headers**: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `Retry-After`

## Security Features

### Input Validation
- All query parameters are validated
- String inputs are sanitized to prevent XSS
- Numeric inputs are properly validated and bounded
- Canister IDs are validated against proper format

### Rate Limiting
- IP-based rate limiting
- Configurable windows and limits
- Retry-After headers for clients
- Separate limits for different endpoints

### Security Headers
- Helmet.js for secure HTTP headers
- CORS configuration for cross-origin requests
- Content Security Policy
- X-Frame-Options, X-Content-Type-Options

### Logging
- Structured logging with Winston
- Request/response logging
- Error tracking and monitoring
- Performance metrics

## Deployment

### Docker Deployment

1. **Build Docker image**:
   ```bash
   docker build -t icp-marketplace-api .
   ```

2. **Run container**:
   ```bash
   docker run -p 3000:3000 --env-file .env icp-marketplace-api
   ```

### Docker Compose

```yaml
version: '3.8'
services:
  api:
    build: .
    ports:
      - "3000:3000"
    env_file:
      - .env
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### Environment-specific Deployment

**Development:**
```bash
NODE_ENV=development npm run dev
```

**Production:**
```bash
NODE_ENV=production npm start
```

## Monitoring and Maintenance

### Health Check
```http
GET /health
```

Returns server status and timestamp.

### Metrics to Monitor
- Response times
- Error rates
- Request volumes
- Rate limit violations
- Memory and CPU usage

### Log Analysis
- Winston structured logs
- Request/response tracking
- Error categorization
- Performance monitoring

## Testing

### Run Tests
```bash
npm test
```

### API Testing
```bash
# Test search endpoint
curl "http://localhost:3000/v1/scripts/search?limit=5"

# Test script details
curl "http://localhost:3000/v1/scripts/script_id_here"

# Test validation
curl -X POST "http://localhost:3000/v1/scripts/validate" \
  -H "Content-Type: application/json" \
  -d '{"lua_source": "print(\"test\")"}'
```

## Configuration

### Custom Rate Limits
Modify rate limiting in `src/server.js`:
```javascript
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // requests per window
  // ... other options
});
```

### CORS Configuration
Update allowed origins in environment variables:
```env
ALLOWED_ORIGINS=http://localhost:3000,https://yourdomain.com,https://app.yourdomain.com
```

### Custom Endpoints
Add new endpoints in `src/server.js` following the existing patterns:
1. Define the route with validation middleware
2. Implement the business logic
3. Handle errors appropriately
4. Add proper logging

## Troubleshooting

### Common Issues

1. **Appwrite Connection Issues**
   - Verify API key and project ID
   - Check network connectivity
   - Confirm collection and function IDs

2. **Rate Limiting Issues**
   - Check `X-RateLimit-*` headers
   - Adjust limits in configuration
   - Monitor for abusive requests

3. **CORS Issues**
   - Verify allowed origins configuration
   - Check preflight requests
   - Ensure proper headers are set

### Debug Mode
Enable detailed logging:
```bash
LOG_LEVEL=debug npm run dev
```

### Health Monitoring
Set up monitoring for:
- Server uptime
- Response times
- Error rates
- Resource usage

## Contributing

1. Fork the repository
2. Create a feature branch
3. Implement your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This API server is part of the ICP project and follows the same licensing terms.