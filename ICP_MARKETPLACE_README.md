# ICP Autorun Marketplace

A marketplace solution for Lua scripts that can be used with ICP (Internet Computer Protocol) canisters. This implementation includes a backend, public API server, and Flutter frontend.

## Architecture Overview

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│                     │    │                     │    │                     │
│   Flutter App       │───▶│   Public API        │───▶│   Appwrite Backend  │
│                     │    │   (Appwrite)        │    │                     │
│                     │    │                     │    │                     │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

## Features

### 🚀 Script Management
- **Browse & Download**: Users can browse and download free Lua scripts
- **Canister Compatibility**: Scripts can specify compatible canister IDs
- **Categories & Tags**: Organized by categories (Gaming, Finance, DeFi, etc.)
- **Free Scripts**: Currently supports free scripts only
- **Code Review**: Users should review code before running scripts

### 🔍 Search
- **Full-Text Search**: Search across titles, descriptions, and tags
- **Canister ID Filtering**: Find scripts compatible with specific canisters
- **Category Filtering**: Browse by predefined categories
- **Sorting**: Sort by downloads and recency

### 🔧 Technical Features
- **Security**: Users should review code before running scripts
- **Open API**: Public API for third-party integrations
- **Payment System**: Optional payment processing for premium scripts (currently disabled)
- **User Reviews**: Rating and review system with verified purchase indicators

## Project Structure

```
icp-cc/
├── appwrite/                          # Appwrite backend configuration
│   ├── appwrite.json                  # Database schema definition
│   ├── functions/                     # Cloud functions
│   └── README.md                      # Backend documentation
├── appwrite-api-server/               # Node.js public API server
│   ├── package.json                   # Dependencies
│   ├── src/server.js                  # API server implementation
│   ├── .env.example                   # Environment template
│   └── README.md                      # API documentation
├── appwrite-cli/                      # Deployment and maintenance
├── apps/autorun_flutter/              # Flutter frontend app
│   ├── lib/
│   │   ├── models/                    # Data models (JSON serializable, NO Appwrite models)
│   │   ├── services/                  # API services (OpenAPI service ONLY, NO Appwrite services)
│   │   ├── screens/                   # UI screens
│   │   ├── widgets/                   # Reusable UI components
│   │   └── utils/                     # Utility functions (NO Appwrite config)
│   └── pubspec.yaml                   # Flutter dependencies (NO appwrite package)
└── ICP_MARKETPLACE_README.md          # This file
```

## 🚨 Architecture Rules

### CRITICAL: Flutter App Isolation
- **Flutter MUST NOT import appwrite package**
- **Flutter MUST NOT access Appwrite services directly**
- **Flutter MUST NOT use Appwrite configuration**
- **Flutter MUST ONLY communicate through the public API server**
- **Flutter models MUST be plain JSON serializable classes**
- **Flutter services MUST use HTTP to call public API endpoints**

This separation ensures:
1. **Security**: Backend credentials are never exposed to the client
2. **Flexibility**: Backend can be changed without affecting client code
3. **Maintainability**: Clear separation of concerns

## Quick Start Guide

### Prerequisites

- **Appwrite Account**: Create account at [appwrite.io](https://appwrite.io)
- **Node.js 18+**: For API server
- **Flutter SDK**: For mobile app

### 1. Setup Appwrite Backend

```bash
# First install Just (one-time setup)
./install-just.sh

# Build the deployment CLI
just appwrite-setup

# Deploy to Appwrite
just appwrite-deploy

# Deploy with dry-run (safely test)
just appwrite-deploy -- --dry-run
```

### 2. Deploy API Server

```bash
cd appwrite-api-server

# Install dependencies
npm install

# Configure environment
cp .env.example .env
# Edit .env with your Appwrite credentials

# Start development server
just appwrite-api-server

# Or start production server
just appwrite-api-server-prod

# Or run tests
just appwrite-api-server-test
```

### 3. Setup Flutter App

```bash
cd apps/autorun_flutter

# Install dependencies
flutter pub get

# Add required packages (NOTE: NO appwrite dependency!)
flutter pub add http cached_network_image

# Update lib/services/marketplace_open_api_service.dart with your API endpoint
# (default: https://fra.cloud.appwrite.io/v1)

# Run the app
flutter run
```

### 4. Configure Your API Endpoint

Update the API server URL in `apps/autorun_flutter/lib/services/marketplace_open_api_service.dart`:

```dart
final String _baseUrl = 'https://fra.cloud.appwrite.io/v1'; // Production Appwrite endpoint
```

## API Documentation

### Public API Endpoints

#### Scripts
- `GET /v1/scripts/search` - Search scripts with advanced filters
- `GET /v1/scripts/{id}` - Get script details
- `GET /v1/scripts/featured` - Get featured scripts
- `GET /v1/scripts/trending` - Get trending scripts
- `GET /v1/scripts/category/{category}` - Browse by category
- `GET /v1/scripts/canister/{canisterId}` - Find compatible scripts
- `GET /v1/scripts/{id}/download` - Download free scripts

#### Reviews & Stats
- `GET /v1/scripts/{id}/reviews` - Get script reviews
- `GET /v1/stats` - Marketplace statistics
- `POST /v1/scripts/validate` - Validate Lua syntax

### Example API Usage

```bash
# Search gaming scripts
curl "https://fra.cloud.appwrite.io/v1/scripts/search?category=Gaming&min_rating=4"

# Find scripts for a specific canister
curl "https://fra.cloud.appwrite.io/v1/scripts/canister/rrkah-fqaaa-aaaaa-aaaaq-cai"

# Get script details
curl "https://fra.cloud.appwrite.io/v1/scripts/script_123"

# Validate Lua code
curl -X POST "https://fra.cloud.appwrite.io/v1/scripts/validate" \
  -H "Content-Type: application/json" \
  -d '{"lua_source": "print(\"Hello, ICP!\")"}'
```

## Database Schema

### Scripts Collection
```json
{
  "title": "string",
  "description": "string",
  "category": "string",
  "tags": ["string"],
  "authorId": "string",
  "authorName": "string",
  "price": "float",
  "downloads": "integer",
  "rating": "float",
  "reviewCount": "integer",
  "luaSource": "string",
  "iconUrl": "string",
  "screenshots": ["string"],
  "canisterIds": ["string"],
  "version": "string",
  "compatibility": "string",
  "isPublic": "boolean",
  "isApproved": "boolean",
  "featuredOrder": "integer"
}
```

## Security Considerations

### Backend Security
- **Appwrite Security**: Document-level security and permissions
- **API Key Management**: Secure storage of admin API keys

### API Server Security
- **Input Validation**: Basic validation for user inputs
- **CORS Protection**: Configurable cross-origin access
- **Security Headers**: Helmet.js for secure HTTP headers

### Flutter App Security
- **No Appwrite Access**: Flutter app MUST NOT access Appwrite directly - only through public API
- **No Authentication**: Currently no authentication required (see TODO.md for future plans)
- **Code Review**: Users should review all script code before execution

## Testing

### Testing Strategy
- **Unit Tests**: All business logic must have unit tests
- **Integration Tests**: API endpoints must be tested end-to-end
- **Flutter Tests**: UI components and user flows must be tested
- **Fail Fast Examples**:
  - API returns detailed error messages with proper HTTP status codes
  - Flutter shows clear error messages when API calls fail
  - Database operations fail fast with descriptive error logs

## Deployment

### Development Environment
```bash
# Start API server locally
cd appwrite-api-server
npm run dev

# Start Flutter app
cd apps/autorun_flutter
flutter run
```

### Production Environment

#### API Server Deployment (Docker)
```bash
# Build Docker image
docker build -t icp-marketplace-api appwrite-api-server/

# Run with Docker Compose
docker-compose up -d
```

#### Flutter App Deployment
```bash
# Build for production
cd apps/autorun_flutter

# Build Android APK
flutter build apk --release

# Build iOS
flutter build ios --release

# Build Web
flutter build web
```

## Contributing

### Development Workflow
1. Fork the repository
2. Create a feature branch
3. Implement your changes
4. Add tests for new functionality
5. Update documentation
6. Submit a pull request

### Code Standards
- **Node.js**: ESLint and Prettier for code formatting
- **Flutter**: Follow Dart style guidelines
- **Documentation**: Comprehensive API documentation

## License

see ./LICENSE

## Support

### Documentation
- [Appwrite Documentation](https://appwrite.io/docs)
- [Flutter Documentation](https://flutter.dev/docs)

### Community
- GitHub Issues for bug reports and feature requests

### Contact
For questions specific to the ICP Script Marketplace:
- Create an issue in this repository
- Contact the development team
- Check the FAQ section

---

## FAQ

### Q: Do I need an account to use the marketplace?
A: No account is currently needed to browse and download scripts. Authentication will be added later for script uploads.

### Q: Can I self-host the marketplace?
A: Yes, all components can be self-hosted. The repository has everything needed to set up the marketplace.

### Q: How are canister IDs validated?
A: Canister IDs are validated using a regex pattern to ensure they follow the proper ICP canister format.

### Q: Is there a limit on script size?
A: Yes, there's a 100KB limit for Lua source code to ensure optimal performance.

### Q: How are payments handled?
A: Currently only free scripts are supported. Payment integration with icpay.org will be added later.

### Q: Can I integrate this with my existing ICP project?
A: Yes! The marketplace is designed to work with any ICP canister. Scripts can specify compatible canister IDs for targeted searches.

### Q: Is it safe to run downloaded scripts?
A: Users should review all script code before execution. Security measures will be improved in future versions.

---

**Happy coding with ICP Autorun Marketplace! 🚀**

