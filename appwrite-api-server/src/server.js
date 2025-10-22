require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const { body, query, validationResult } = require('express-validator');
const winston = require('winston');
const { Client, Databases, Functions } = require('node-appwrite');
const luaparse = require('luaparse');
const validator = require('validator');

// Initialize Express app
const app = express();
const PORT = process.env.PORT || 3000;

// Configure logging
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console({
      format: winston.format.simple()
    })
  ]
});

// Initialize Appwrite client
const appwriteClient = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1')
  .setProject(process.env.APPWRITE_PROJECT_ID || '68f7fc8b00255b20ed42')
  .setKey(process.env.APPWRITE_API_KEY || '');

const databases = new Databases(appwriteClient);
const functions = new Functions(appwriteClient);

// Configuration
const CONFIG = {
  DATABASE_ID: process.env.DATABASE_ID || 'marketplace_db',
  SCRIPTS_COLLECTION_ID: process.env.SCRIPTS_COLLECTION_ID || 'scripts',
  REVIEWS_COLLECTION_ID: process.env.REVIEWS_COLLECTION_ID || 'reviews',
  SEARCH_FUNCTION_ID: process.env.SEARCH_FUNCTION_ID || 'search_scripts',
  DEFAULT_LIMIT: 20,
  MAX_LIMIT: 100,
  RATE_LIMIT_WINDOW: 15 * 60 * 1000, // 15 minutes
  RATE_LIMIT_MAX: 100, // requests per window
};

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS ? process.env.ALLOWED_ORIGINS.split(',') : '*',
  methods: ['GET', 'POST'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: CONFIG.RATE_LIMIT_WINDOW,
  max: CONFIG.RATE_LIMIT_MAX,
  message: {
    error: 'Too many requests from this IP, please try again later.',
    retryAfter: CONFIG.RATE_LIMIT_WINDOW / 1000
  },
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/api', limiter);
app.use(express.json({ limit: '10mb' }));

// Request logging
app.use((req, res, next) => {
  logger.info(`${req.method} ${req.path}`, {
    ip: req.ip,
    userAgent: req.get('User-Agent')
  });
  next();
});

// Validation middleware
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      error: 'Validation failed',
      details: errors.array()
    });
  }
  next();
};

// Utility functions
const sanitizeQuery = (query) => {
  const sanitized = { ...query };

  // Sanitize string inputs
  Object.keys(sanitized).forEach(key => {
    if (typeof sanitized[key] === 'string') {
      sanitized[key] = validator.escape(sanitized[key]);
    }
  });

  // Validate and sanitize numeric inputs
  if (sanitized.limit) {
    sanitized.limit = Math.min(parseInt(sanitized.limit) || CONFIG.DEFAULT_LIMIT, CONFIG.MAX_LIMIT);
  }
  if (sanitized.offset) {
    sanitized.offset = Math.max(parseInt(sanitized.offset) || 0, 0);
  }

  return sanitized;
};

const validateCanisterId = (canisterId) => {
  const canisterRegex = /^[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{5}-[a-z0-9]{3}$/;
  return canisterRegex.test(canisterId);
};

const validateLuaCode = (luaCode) => {
  try {
    luaparse.parse(luaCode);
    return {
      isValid: true,
      errors: []
    };
  } catch (error) {
    return {
      isValid: false,
      errors: [error.message]
    };
  }
};

// API Routes

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Search scripts
app.get('/v1/scripts/search',
  [
    query('q').optional().isLength({ max: 256 }).withMessage('Search query too long'),
    query('category').optional().isIn(['Utilities', 'Finance', 'Gaming', 'Social', 'NFT', 'DeFi', 'Data Analytics', 'Automation', 'Security', 'Other']),
    query('canister_id').optional().custom(value => validateCanisterId(value) ? true : 'Invalid canister ID format'),
    query('min_rating').optional().isFloat({ min: 0, max: 5 }),
    query('max_price').optional().isFloat({ min: 0 }),
    query('sort_by').optional().isIn(['createdAt', 'rating', 'downloads', 'price', 'title']),
    query('sort_order').optional().isIn(['asc', 'desc']),
    query('limit').optional().isInt({ min: 1, max: CONFIG.MAX_LIMIT }),
    query('offset').optional().isInt({ min: 0 })
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const sanitized = sanitizeQuery(req.query);

      // Use Appwrite search function
      const searchParams = {
        query: sanitized.q || '',
        category: sanitized.category,
        canisterId: sanitized.canister_id,
        minRating: sanitized.min_rating ? parseFloat(sanitized.min_rating) : undefined,
        maxPrice: sanitized.max_price ? parseFloat(sanitized.max_price) : undefined,
        sortBy: sanitized.sort_by || 'createdAt',
        order: sanitized.sort_order || 'desc',
        limit: sanitized.limit || CONFIG.DEFAULT_LIMIT,
        offset: sanitized.offset || 0
      };

      const execution = await functions.createExecution(
        CONFIG.SEARCH_FUNCTION_ID,
        JSON.stringify(searchParams),
        false // synchronous
      );

      const response = JSON.parse(execution.responseBody);

      if (!response.success) {
        throw new Error(response.error || 'Search failed');
      }

      const result = response.data;

      res.json({
        scripts: result.scripts,
        total: result.total,
        hasMore: result.hasMore,
        offset: parseInt(sanitized.offset || 0),
        limit: parseInt(sanitized.limit || CONFIG.DEFAULT_LIMIT)
      });

    } catch (error) {
      logger.error('Search scripts error:', error);
      res.status(500).json({
        error: 'Failed to search scripts',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
);

// Get script details
app.get('/v1/scripts/:scriptId',
  [
    query('scriptId').notEmpty().withMessage('Script ID is required')
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { scriptId } = req.params;

      const document = await databases.getDocument(
        CONFIG.DATABASE_ID,
        CONFIG.SCRIPTS_COLLECTION_ID,
        scriptId
      );

      // Only return public and approved scripts
      if (!document.isPublic || !document.isApproved) {
        return res.status(404).json({ error: 'Script not found' });
      }

      res.json(document);

    } catch (error) {
      if (error.code === 404) {
        return res.status(404).json({ error: 'Script not found' });
      }

      logger.error('Get script details error:', error);
      res.status(500).json({
        error: 'Failed to get script details',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
);

// Get featured scripts
app.get('/v1/scripts/featured',
  [
    query('limit').optional().isInt({ min: 1, max: 50 })
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const limit = Math.min(parseInt(req.query.limit) || 10, 50);

      const documents = await databases.listDocuments(
        CONFIG.DATABASE_ID,
        CONFIG.SCRIPTS_COLLECTION_ID,
        [
          { method: 'equal', attribute: 'isPublic', values: [true] },
          { method: 'equal', attribute: 'isApproved', values: [true] },
          { method: 'notEqual', attribute: 'featuredOrder', values: [null] },
          { method: 'orderAsc', attribute: 'featuredOrder' },
          { method: 'limit', value: limit }
        ]
      );

      res.json(documents.documents);

    } catch (error) {
      logger.error('Get featured scripts error:', error);
      res.status(500).json({
        error: 'Failed to get featured scripts',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
);

// Get trending scripts
app.get('/v1/scripts/trending',
  [
    query('limit').optional().isInt({ min: 1, max: 50 })
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const limit = Math.min(parseInt(req.query.limit) || 10, 50);

      const documents = await databases.listDocuments(
        CONFIG.DATABASE_ID,
        CONFIG.SCRIPTS_COLLECTION_ID,
        [
          { method: 'equal', attribute: 'isPublic', values: [true] },
          { method: 'equal', attribute: 'isApproved', values: [true] },
          { method: 'greaterThanEqual', attribute: 'downloads', values: [5] },
          { method: 'orderDesc', attribute: 'downloads' },
          { method: 'limit', value: limit }
        ]
      );

      res.json(documents.documents);

    } catch (error) {
      logger.error('Get trending scripts error:', error);
      res.status(500).json({
        error: 'Failed to get trending scripts',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
);

// Get scripts by category
app.get('/v1/scripts/category/:category',
  [
    query('category').isIn(['Utilities', 'Finance', 'Gaming', 'Social', 'NFT', 'DeFi', 'Data Analytics', 'Automation', 'Security', 'Other']),
    query('limit').optional().isInt({ min: 1, max: CONFIG.MAX_LIMIT }),
    query('offset').optional().isInt({ min: 0 }),
    query('sort_by').optional().isIn(['createdAt', 'rating', 'downloads', 'price', 'title']),
    query('sort_order').optional().isIn(['asc', 'desc'])
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { category } = req.params;
      const sanitized = sanitizeQuery(req.query);

      const queries = [
        { method: 'equal', attribute: 'isPublic', values: [true] },
        { method: 'equal', attribute: 'isApproved', values: [true] },
        { method: 'equal', attribute: 'category', values: [category] },
        { method: 'limit', value: sanitized.limit || CONFIG.DEFAULT_LIMIT },
        { method: 'offset', value: sanitized.offset || 0 }
      ];

      // Add sorting
      const sortBy = sanitized.sort_by || 'rating';
      const sortOrder = sanitized.sort_order || 'desc';
      queries.push({
        method: sortOrder === 'desc' ? 'orderDesc' : 'orderAsc',
        attribute: sortBy
      });

      const documents = await databases.listDocuments(
        CONFIG.DATABASE_ID,
        CONFIG.SCRIPTS_COLLECTION_ID,
        queries
      );

      res.json(documents.documents);

    } catch (error) {
      logger.error('Get scripts by category error:', error);
      res.status(500).json({
        error: 'Failed to get scripts by category',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
);

// Get script reviews
app.get('/v1/scripts/:scriptId/reviews',
  [
    query('scriptId').notEmpty().withMessage('Script ID is required'),
    query('limit').optional().isInt({ min: 1, max: 50 }),
    query('offset').optional().isInt({ min: 0 }),
    query('verified_only').optional().isBoolean()
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { scriptId } = req.params;
      const sanitized = sanitizeQuery(req.query);

      const queries = [
        { method: 'equal', attribute: 'scriptId', values: [scriptId] },
        { method: 'equal', attribute: 'status', values: ['approved'] },
        { method: 'orderDesc', attribute: 'createdAt' },
        { method: 'limit', value: sanitized.limit || 20 },
        { method: 'offset', value: sanitized.offset || 0 }
      ];

      if (sanitized.verified_only === 'true') {
        queries.push({ method: 'equal', attribute: 'isVerifiedPurchase', values: [true] });
      }

      const documents = await databases.listDocuments(
        CONFIG.DATABASE_ID,
        CONFIG.REVIEWS_COLLECTION_ID,
        queries
      );

      res.json(documents.documents);

    } catch (error) {
      logger.error('Get script reviews error:', error);
      res.status(500).json({
        error: 'Failed to get script reviews',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
);

// Download script (only free scripts)
app.get('/v1/scripts/:scriptId/download',
  async (req, res) => {
    try {
      const { scriptId } = req.params;

      const document = await databases.getDocument(
        CONFIG.DATABASE_ID,
        CONFIG.SCRIPTS_COLLECTION_ID,
        scriptId
      );

      // Check if script is free and publicly available
      if (!document.isPublic || !document.isApproved) {
        return res.status(404).json({ error: 'Script not found' });
      }

      if (document.price > 0) {
        return res.status(403).json({
          error: 'Paid scripts require authentication to download'
        });
      }

      // Return script source
      res.json({
        scriptId: document.$id,
        title: document.title,
        luaSource: document.luaSource,
        version: document.version,
        compatibility: document.compatibility
      });

    } catch (error) {
      if (error.code === 404) {
        return res.status(404).json({ error: 'Script not found' });
      }

      logger.error('Download script error:', error);
      res.status(500).json({
        error: 'Failed to download script',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
);

// Search scripts by canister ID
app.get('/v1/scripts/canister/:canisterId',
  [
    query('canisterId').custom(value => validateCanisterId(value) ? true : 'Invalid canister ID format'),
    query('limit').optional().isInt({ min: 1, max: CONFIG.MAX_LIMIT })
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { canisterId } = req.params;
      const limit = Math.min(parseInt(req.query.limit) || CONFIG.DEFAULT_LIMIT, CONFIG.MAX_LIMIT);

      const documents = await databases.listDocuments(
        CONFIG.DATABASE_ID,
        CONFIG.SCRIPTS_COLLECTION_ID,
        [
          { method: 'equal', attribute: 'isPublic', values: [true] },
          { method: 'equal', attribute: 'isApproved', values: [true] },
          { method: 'search', attribute: 'canisterIds', values: [canisterId] },
          { method: 'orderDesc', attribute: 'rating' },
          { method: 'limit', value: limit }
        ]
      );

      res.json(documents.documents);

    } catch (error) {
      logger.error('Search scripts by canister ID error:', error);
      res.status(500).json({
        error: 'Failed to search scripts by canister ID',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
);

// Get compatible scripts for multiple canister IDs
app.post('/v1/scripts/compatible',
  [
    body('canister_ids').isArray({ min: 1 }).withMessage('Canister IDs array is required'),
    body('canister_ids.*').custom(value => validateCanisterId(value) ? true : 'Invalid canister ID format'),
    body('limit').optional().isInt({ min: 1, max: CONFIG.MAX_LIMIT })
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { canister_ids, limit = 50 } = req.body;

      // Build queries for all canister IDs
      const documents = await databases.listDocuments(
        CONFIG.DATABASE_ID,
        CONFIG.SCRIPTS_COLLECTION_ID,
        [
          { method: 'equal', attribute: 'isPublic', values: [true] },
          { method: 'equal', attribute: 'isApproved', values: [true] },
          { method: 'limit', value: Math.min(limit, CONFIG.MAX_LIMIT) },
          { method: 'orderDesc', attribute: 'rating' }
        ]
      );

      // Filter scripts that match any of the provided canister IDs
      const compatibleScripts = documents.documents.filter(script => {
        if (!script.canisterIds || !Array.isArray(script.canisterIds)) {
          return false;
        }
        return script.canisterIds.some(canisterId =>
          canister_ids.includes(canisterId)
        );
      });

      res.json(compatibleScripts);

    } catch (error) {
      logger.error('Get compatible scripts error:', error);
      res.status(500).json({
        error: 'Failed to get compatible scripts',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
);

// Get marketplace statistics
app.get('/v1/stats', async (req, res) => {
  try {
    // Get total scripts count
    const scriptsCount = await databases.listDocuments(
      CONFIG.DATABASE_ID,
      CONFIG.SCRIPTS_COLLECTION_ID,
      [
        { method: 'equal', attribute: 'isPublic', values: [true] },
        { method: 'equal', attribute: 'isApproved', values: [true] },
        { method: 'limit', value: 1 }
      ]
    );

    // Get total authors count (this would require aggregation in a real implementation)
    const authorsCount = await databases.listDocuments(
      CONFIG.DATABASE_ID,
      'users', // assuming users collection
      [
        { method: 'greaterThan', attribute: 'scriptsPublished', values: [0] },
        { method: 'limit', value: 1 }
      ]
    );

    // Calculate total downloads and average rating (simplified for this example)
    const stats = {
      total_scripts: scriptsCount.total || 0,
      total_authors: authorsCount.total || 0,
      total_downloads: 0, // Would need aggregation query
      average_rating: 0.0, // Would need aggregation query
      last_updated: new Date().toISOString()
    };

    res.json(stats);

  } catch (error) {
    logger.error('Get marketplace stats error:', error);
    res.status(500).json({
      error: 'Failed to get marketplace statistics',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

// Validate script syntax
app.post('/v1/scripts/validate',
  [
    body('lua_source').notEmpty().withMessage('Lua source code is required')
  ],
  handleValidationErrors,
  async (req, res) => {
    try {
      const { lua_source } = req.body;

      const validation = validateLuaCode(lua_source);

      res.json({
        is_valid: validation.isValid,
        errors: validation.errors,
        warnings: []
      });

    } catch (error) {
      logger.error('Validate script error:', error);
      res.status(500).json({
        error: 'Failed to validate script',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  }
);

// Error handling middleware
app.use((error, req, res, next) => {
  logger.error('Unhandled error:', error);
  res.status(500).json({
    error: 'Internal server error',
    details: process.env.NODE_ENV === 'development' ? error.message : undefined
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// Start server
app.listen(PORT, () => {
  logger.info(`ICP Marketplace API Server started on port ${PORT}`);
  logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
  logger.info(`Rate limit: ${CONFIG.RATE_LIMIT_MAX} requests per ${CONFIG.RATE_LIMIT_WINDOW / 1000}s`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  process.exit(0);
});