# ICP Script Marketplace - SvelteKit Site

This is the SvelteKit-based web application for the ICP Script Marketplace, deployed as an Appwrite Site.

## Architecture

This project uses SvelteKit for the web application with API routes that replace the previous Appwrite Functions:

- **API Routes**: `/api/*` endpoints handle all backend logic
- **Frontend**: SvelteKit pages (to be added later)
- **Database**: Appwrite Database for storing scripts, users, purchases, and reviews

## API Endpoints

### POST /api/search_scripts
Search for scripts with various filters and pagination.

### POST /api/process_purchase
Process script purchases and update download counts.

### POST /api/update_script_stats
Update script statistics when new reviews are added.

### GET /api/get_marketplace_stats
Get marketplace statistics and analytics.

## Development

1. Install dependencies:
   ```bash
   npm install
   ```

2. Set environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your Appwrite credentials
   ```

3. Run development server:
   ```bash
   npm run dev
   ```

## Deployment

### Deploy to Appwrite Site

1. Install Appwrite CLI:
   ```bash
   npm install -g appwrite-cli
   ```

2. Login to Appwrite:
   ```bash
   appwrite login
   ```

3. Initialize the project:
   ```bash
   appwrite init --project icp-script-marketplace
   ```

4. Deploy the site:
   ```bash
   appwrite deploy site
   ```

### Environment Variables

Required environment variables:

- `DATABASE_ID`: Appwrite Database ID
- `SCRIPTS_COLLECTION_ID`: Scripts collection ID
- `USERS_COLLECTION_ID`: Users collection ID
- `PURCHASES_COLLECTION_ID`: Purchases collection ID
- `REVIEWS_COLLECTION_ID`: Reviews collection ID
- `APPWRITE_ENDPOINT`: Appwrite endpoint URL
- `APPWRITE_PROJECT_ID`: Appwrite project ID
- `APPWRITE_API_KEY`: Appwrite API key
- `PUBLIC_SITE_URL`: Site URL (https://icp-autorun.appwrite.network for production, http://localhost:5173 for local)

### Site URLs

- **Production**: https://icp-autorun.appwrite.network
- **Local Development**: http://localhost:5173

## Migration from Functions

This site provides API endpoints for marketplace functionality:

- `search_scripts` → `/api/search_scripts`
- `process_purchase` → `/api/process_purchase`
- `update_script_stats` → `/api/update_script_stats`
- `get_marketplace_stats` → `/api/get_marketplace_stats`

## Benefits of SvelteKit Site

1. **Unified Deployment**: Frontend and API deployed together
2. **Automatic URLs**: No manual endpoint configuration
3. **Git-based Deployment**: Simple deployment workflow
4. **Framework Support**: Native SvelteKit features
5. **Future Frontend**: Ready for UI components when needed
