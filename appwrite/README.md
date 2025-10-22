# ICP Script Marketplace - Appwrite Backend

This directory contains the Appwrite backend configuration for the ICP Script Marketplace. The marketplace provides a searchable and discoverable platform for Lua scripts that can be used with ICP canisters.

## Features

- **Full-Text Search**: Search scripts by title, description, and tags
- **Canister ID Filtering**: Find scripts compatible with specific canisters
- **User Authentication**: Secure user registration and login
- **Script Management**: Upload, purchase, and review scripts
- **Rating System**: User reviews and ratings with verified purchase indicators
- **Storage**: File upload for script icons and screenshots
- **Real-time Updates**: Live updates for stats and marketplace changes

## Architecture

### Database Collections

#### Scripts Collection (`scripts`)
Stores marketplace script metadata including:
- Title, description, category, tags
- Author information
- Pricing and download statistics
- Rating and review counts
- Script source code
- Canister compatibility information
- File references (icons, screenshots)

#### Users Collection (`users`)
Extended user profiles with:
- Username and display name
- Bio and social links
- Script publication statistics
- Developer verification status
- Favorites list

#### Purchases Collection (`purchases`)
Purchase transaction records with:
- User and script references
- Payment information
- Transaction status
- Timestamps

#### Reviews Collection (`reviews`)
User reviews and ratings with:
- Script and user references
- Star ratings (1-5)
- Text comments
- Verified purchase indicators
- Moderation status

### Cloud Functions

#### Search Scripts (`search_scripts`)
Advanced search functionality with:
- Full-text search across multiple fields
- Category and canister ID filtering
- Rating and price filtering
- Customizable sorting and pagination

#### Process Purchase (`process_purchase`)
Handles script purchases including:
- Purchase validation
- Duplicate purchase prevention
- Download count updates
- Payment processing integration

#### Update Script Stats (`update_script_stats`)
Automatically updates script statistics when:
- New reviews are submitted
- Ratings are modified
- Download counts change

### Storage

#### Scripts Files Bucket (`scripts_files`)
File storage for:
- Script icons and thumbnails
- Screenshots and preview images
- Documentation files

## Configuration

### Environment Variables

The Flutter app uses these configuration values (in `lib/utils/appwrite_config.dart`):

```dart
static const String endpoint = 'https://fra.cloud.appwrite.io/v1';
static const String projectId = '68f7fc8b00255b20ed42';
```

### API Keys

For production deployment, ensure you have appropriate API keys with:
- `read` permissions for public data access
- `write` permissions for authenticated users
- `admin` permissions for administrative functions

## Security Considerations

1. **Input Validation**: All user inputs are validated before database operations
2. **Access Control**: Document-level security is enabled on all collections
3. **File Uploads**: File size and type restrictions are enforced
4. **Payment Processing**: Secure handling of purchase transactions
5. **Data Encryption**: Appwrite provides built-in encryption at rest and in transit

## Usage Examples

### Searching Scripts

```dart
final result = await marketplaceService.searchScripts(
  query: 'gaming scripts',
  category: 'Gaming',
  canisterId: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
  minRating: 4.0,
  maxPrice: 10.0,
  sortBy: 'rating',
  sortOrder: 'desc',
  limit: 20,
);
```

### Purchasing Scripts

```dart
final result = await marketplaceService.purchaseScript(
  scriptId: 'script123',
  paymentMethod: 'stripe',
  price: 5.99,
);
```

### User Authentication

```dart
// Register
final user = await authService.registerUser(
  email: 'user@example.com',
  password: 'securepassword',
  username: 'dev_user',
  displayName: 'Developer User',
);

// Login
final session = await authService.loginUser(
  email: 'user@example.com',
  password: 'securepassword',
);
```

## Monitoring and Maintenance

### Logs

Monitor your Appwrite project logs for:
- Function execution errors
- Failed authentication attempts
- Database operation failures
- Unusual activity patterns

### Performance

- Optimize database queries with proper indexes
- Monitor function execution times
- Set up alerts for high error rates
- Regular backup of important data

### Scaling

- Consider Appwrite's automatic scaling features
- Monitor resource usage and upgrade plans as needed
- Implement caching strategies for frequently accessed data

## API Reference

### REST API

All collections are accessible via Appwrite's REST API. The standard endpoints are:

- `GET /v1/databases/{databaseId}/collections/{collectionId}/documents`
- `POST /v1/databases/{databaseId}/collections/{collectionId}/documents`
- `PUT /v1/databases/{databaseId}/collections/{collectionId}/documents/{documentId}`
- `DELETE /v1/databases/{databaseId}/collections/{collectionId}/documents/{documentId}`

### Functions API

Execute cloud functions via:

```
POST /v1/functions/{functionId}/executions
```

## Troubleshooting

### Common Issues

1. **CORS Errors**: Ensure your Flutter app's origin is added to allowed domains
2. **Permission Errors**: Check collection permissions and API key scopes
3. **Function Timeouts**: Optimize function code for better performance
4. **File Upload Errors**: Verify file size and format restrictions

### Debug Mode

Enable Appwrite debugging in your Flutter app:

```dart
AppwriteService().initialize();
// Check console for detailed error messages
```

## Support

For issues related to:
- **Appwrite Platform**: Visit [appwrite.io/docs](https://appwrite.io/docs)
- **ICP Integration**: Check the main project documentation
- **Specific Marketplace Features**: Create an issue in this repository

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This marketplace backend is part of the ICP project and follows the same licensing terms.
