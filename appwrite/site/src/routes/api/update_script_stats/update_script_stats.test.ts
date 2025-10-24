import { POST } from './+server';
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
    getDocument: vi.fn(),
    updateDocument: vi.fn(),
  })),
  Query: {
    equal: vi.fn(),
    limit: vi.fn(),
  },
}));

describe('/api/update_script_stats', () => {
  let mockDatabases: any;

  beforeEach(async () => {
    vi.clearAllMocks();
    const { Databases } = await import('node-appwrite');
    mockDatabases = new (Databases as any)();
  });

  it('should update script stats for new review', async () => {
    const eventData = {
      payload: {
        $collectionId: 'reviews',
        $operation: 'create',
        scriptId: 'script1',
        rating: 5,
        userId: 'user1'
      }
    };

    const mockReviews = [
      { rating: 5, isVerifiedPurchase: true },
      { rating: 4, isVerifiedPurchase: false },
      { rating: 5, isVerifiedPurchase: true }
    ];

    const mockScript = {
      $id: 'script1',
      authorId: 'author1'
    };

    const mockUser = {
      $id: 'author1',
      totalDownloads: 100
    };

    const mockAuthorScripts = [
      { rating: 4.5 },
      { rating: 5.0 }
    ];

    // Mock database responses
    mockDatabases.listDocuments
      .mockResolvedValueOnce({
        total: 3,
        documents: mockReviews
      }) // Get all reviews for script
      .mockResolvedValueOnce({
        total: 2,
        documents: mockAuthorScripts
      }); // Get all scripts by author

    mockDatabases.getDocument
      .mockResolvedValueOnce(mockScript) // Get script
      .mockResolvedValueOnce(mockUser); // Get user

    mockDatabases.updateDocument.mockResolvedValue({});

    const request = new Request('http://localhost/api/update_script_stats', {
      method: 'POST',
      body: JSON.stringify(eventData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
    expect(data.data).toMatchObject({
      scriptId: 'script1',
      newAverageRating: 4.67, // (5 + 4 + 5) / 3 = 4.67
      reviewCount: 3,
      verifiedReviewCount: 2,
      authorId: 'author1',
      authorStats: {
        scriptsPublished: 2,
        averageRating: 4.75 // (4.5 + 5.0) / 2 = 4.75
      }
    });

    // Should update script stats
    expect(mockDatabases.updateDocument).toHaveBeenCalledWith(
      expect.any(String),
      expect.any(String),
      'script1',
      {
        rating: 4.67,
        reviewCount: 3,
        verifiedReviewCount: 2
      }
    );

    // Should update author stats
    expect(mockDatabases.updateDocument).toHaveBeenCalledWith(
      expect.any(String),
      expect.any(String),
      'author1',
      {
        scriptsPublished: 2,
        averageRating: 4.75,
        totalDownloads: 100
      }
    );
  });

  it('should ignore irrelevant events', async () => {
    const eventData = {
      payload: {
        $collectionId: 'users', // Different collection
        $operation: 'create',
        userId: 'user1'
      }
    };

    const request = new Request('http://localhost/api/update_script_stats', {
      method: 'POST',
      body: JSON.stringify(eventData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
    expect(data.message).toBe('Event not relevant for script stats update');

    // Should not make any database calls
    expect(mockDatabases.listDocuments).not.toHaveBeenCalled();
  });

  it('should ignore update operations (only handle create)', async () => {
    const eventData = {
      payload: {
        $collectionId: 'reviews',
        $operation: 'update', // Not create
        scriptId: 'script1',
        rating: 5,
        userId: 'user1'
      }
    };

    const request = new Request('http://localhost/api/update_script_stats', {
      method: 'POST',
      body: JSON.stringify(eventData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
    expect(data.message).toBe('Event not relevant for script stats update');
  });

  it('should handle scripts with no reviews', async () => {
    const eventData = {
      payload: {
        $collectionId: 'reviews',
        $operation: 'create',
        scriptId: 'script1',
        rating: 5,
        userId: 'user1'
      }
    };

    const mockScript = { authorId: 'author1' };
    const mockUser = { totalDownloads: 0 };

    mockDatabases.listDocuments
      .mockResolvedValueOnce({ total: 0, documents: [] }) // No reviews
      .mockResolvedValueOnce({ total: 0, documents: [] }); // No author scripts

    mockDatabases.getDocument
      .mockResolvedValueOnce(mockScript)
      .mockResolvedValueOnce(mockUser);

    mockDatabases.updateDocument.mockResolvedValue({});

    const request = new Request('http://localhost/api/update_script_stats', {
      method: 'POST',
      body: JSON.stringify(eventData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.data.newAverageRating).toBe(0);
    expect(data.data.reviewCount).toBe(0);
  });

  it('should handle database errors gracefully', async () => {
    const eventData = {
      payload: {
        $collectionId: 'reviews',
        $operation: 'create',
        scriptId: 'script1',
        rating: 5,
        userId: 'user1'
      }
    };

    mockDatabases.listDocuments.mockRejectedValue(new Error('Database connection failed'));

    const request = new Request('http://localhost/api/update_script_stats', {
      method: 'POST',
      body: JSON.stringify(eventData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(500);
    expect(data.success).toBe(false);
    expect(data.error).toBe('Stats update failed');
  });

  it('should handle invalid JSON gracefully', async () => {
    const request = new Request('http://localhost/api/update_script_stats', {
      method: 'POST',
      body: 'invalid json',
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(500);
    expect(data.success).toBe(false);
    expect(data.error).toBe('Stats update failed');
  });

  it('should calculate verified purchase counts correctly', async () => {
    const eventData = {
      payload: {
        $collectionId: 'reviews',
        $operation: 'create',
        scriptId: 'script1',
        rating: 4,
        userId: 'user1'
      }
    };

    const mockReviews = [
      { rating: 4, isVerifiedPurchase: true },
      { rating: 3, isVerifiedPurchase: false },
      { rating: 5, isVerifiedPurchase: true },
      { rating: 2, isVerifiedPurchase: false }
    ];

    mockDatabases.listDocuments.mockResolvedValue({
      total: 4,
      documents: mockReviews
    });

    mockDatabases.getDocument.mockResolvedValue({ authorId: 'author1' });
    mockDatabases.updateDocument.mockResolvedValue({});

    const request = new Request('http://localhost/api/update_script_stats', {
      method: 'POST',
      body: JSON.stringify(eventData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.data.verifiedReviewCount).toBe(2); // Only 2 verified purchases
    expect(data.data.newAverageRating).toBe(3.5); // (4 + 3 + 5 + 2) / 4 = 3.5
  });
});