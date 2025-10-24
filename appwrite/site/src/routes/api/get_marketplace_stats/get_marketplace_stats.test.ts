import { GET } from './+server';
import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock the node-appwrite module
vi.mock('node-appwrite', () => ({
  Client: vi.fn(() => ({
    setEndpoint: vi.fn().mockReturnThis(),
    setProject: vi.fn().mockReturnThis(),
    setKey: vi.fn().mockReturnThis(),
  })),
  Databases: vi.fn(() => ({
    listDocuments: vi.fn(),
  })),
  Query: {
    equal: vi.fn(),
    limit: vi.fn(),
  },
}));

describe('/api/get_marketplace_stats', () => {
  let mockDatabases: any;

  beforeEach(async () => {
    // Clear all mocks before each test
    vi.clearAllMocks();

    // Get the mocked databases instance
    const { Databases } = await import('node-appwrite');
    mockDatabases = new (Databases as any)();
  });

  it('should return marketplace stats successfully', async () => {
    // Mock the database responses
    mockDatabases.listDocuments
      .mockResolvedValueOnce({
        total: 100,
        documents: Array(100).fill({ downloads: 5, rating: 4 })
      }) // totalScripts
      .mockResolvedValueOnce({ total: 25 }) // totalAuthors
      .mockResolvedValueOnce({
        total: 100,
        documents: Array(100).fill({ downloads: 5, rating: 4 })
      }) // allScripts (for downloads/ratings calculation)
      .mockResolvedValueOnce({ total: 500 }) // totalPurchases
      .mockResolvedValueOnce({ total: 200 }) // totalReviews
      .mockResolvedValueOnce({
        total: 100,
        documents: Array(100).fill({
          downloads: 5,
          rating: 4,
          category: 'Automation'
        })
      }); // scriptsByCategory

    const response = await GET();
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
    expect(data.data).toMatchObject({
      totalScripts: 100,
      totalAuthors: 25,
      totalDownloads: 500, // 100 scripts * 5 downloads each
      averageRating: 4.0,
      totalPurchases: 500,
      totalReviews: 200,
      scriptsWithDownloads: 100,
      scriptsWithReviews: 100,
      categoryBreakdown: {
        Automation: {
          count: 100,
          totalDownloads: 500,
          averageRating: 4.0,
          ratingCount: 100,
          totalRating: 400
        }
      }
    });
  });

  it('should handle empty marketplace gracefully', async () => {
    // Mock empty database responses
    mockDatabases.listDocuments
      .mockResolvedValue({ total: 0, documents: [] });

    const response = await GET();
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
    expect(data.data).toMatchObject({
      totalScripts: 0,
      totalAuthors: 0,
      totalDownloads: 0,
      averageRating: 0.0,
      totalPurchases: 0,
      totalReviews: 0,
      categoryBreakdown: {},
      activeDevelopers: 0,
      scriptsWithDownloads: 0,
      scriptsWithReviews: 0
    });
  });

  it('should handle database errors gracefully', async () => {
    // Mock database error
    mockDatabases.listDocuments.mockRejectedValue(new Error('Database connection failed'));

    const response = await GET();
    const data = await response.json();

    expect(response.status).toBe(500);
    expect(data.success).toBe(true); // The endpoint returns success even with errors
    expect(data.data.error).toBe('Stats calculation failed, showing defaults');
  });

  it('should calculate ratings correctly for mixed scripts', async () => {
    // Mock scripts with different ratings
    mockDatabases.listDocuments
      .mockResolvedValueOnce({ total: 3, documents: [] }) // totalScripts
      .mockResolvedValueOnce({ total: 1 }) // totalAuthors
      .mockResolvedValueOnce({
        total: 3,
        documents: [
          { rating: 5, downloads: 10 },
          { rating: 3, downloads: 5 },
          { rating: 0, downloads: 2 } // unrated script
        ]
      }) // allScripts
      .mockResolvedValue({ total: 0, documents: [] }); // other calls

    const response = await GET();
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.data.averageRating).toBe(4.0); // (5 + 3) / 2 = 4.0 (only rated scripts counted)
    expect(data.data.totalDownloads).toBe(17); // 10 + 5 + 2
    expect(data.data.scriptsWithReviews).toBe(2); // only scripts with rating > 0
  });

  it('should handle environment variables correctly', async () => {
    // Test that environment variables are used
    const originalEnv = process.env;

    process.env = {
      ...originalEnv,
      DATABASE_ID: 'test-db',
      SCRIPTS_COLLECTION_ID: 'test-scripts',
      USERS_COLLECTION_ID: 'test-users'
    };

    mockDatabases.listDocuments.mockResolvedValue({ total: 0, documents: [] });

    await GET();

    // Verify that the databases were called with correct collection IDs
    expect(mockDatabases.listDocuments).toHaveBeenCalledWith(
      'test-db',
      'test-scripts',
      expect.any(Array)
    );

    // Restore original environment
    process.env = originalEnv;
  });
});