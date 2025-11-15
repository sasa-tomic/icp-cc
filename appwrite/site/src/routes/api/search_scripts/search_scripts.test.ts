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
  })),
  Query: {
    equal: vi.fn(),
    search: vi.fn(),
    greaterThanEqual: vi.fn(),
    lessThanEqual: vi.fn(),
    orderDesc: vi.fn(),
    limit: vi.fn(),
    offset: vi.fn(),
  },
}));

describe('/api/search_scripts', () => {
  let mockDatabases: any;

  beforeEach(async () => {
    vi.clearAllMocks();
    const { Databases } = await import('node-appwrite');
    mockDatabases = new (Databases as any)();
  });

  it('should search scripts successfully with basic query', async () => {
    const mockScripts = [
      {
        $id: 'script1',
        title: 'Test Script',
        description: 'A test script',
        authorId: 'author1',
        authorName: 'Test Author',
        rating: 4.5,
        downloads: 100
      }
    ];

    const mockAuthor = {
      $id: 'author1',
      username: 'testauthor',
      displayName: 'Test Author',
      avatar: null,
      isVerifiedDeveloper: true
    };

    mockDatabases.listDocuments.mockResolvedValue({
      total: 1,
      documents: mockScripts
    });

    mockDatabases.getDocument.mockResolvedValue(mockAuthor);

    const request = new Request('http://localhost/api/search_scripts', {
      method: 'POST',
      body: JSON.stringify({ query: 'test' }),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
    expect(data.data.scripts).toHaveLength(1);
    expect(data.data.scripts[0]).toMatchObject({
      id: 'script1',
      title: 'Test Script',
      author: {
        id: 'author1',
        username: 'testauthor',
        displayName: 'Test Author',
        isVerifiedDeveloper: true
      }
    });
  });

  it('should handle missing author gracefully', async () => {
    const mockScripts = [
      {
        $id: 'script1',
        title: 'Test Script',
        authorId: 'unknown-author',
        authorName: 'Unknown Author',
        rating: 4.0
      }
    ];

    mockDatabases.listDocuments.mockResolvedValue({
      total: 1,
      documents: mockScripts
    });

    mockDatabases.getDocument.mockRejectedValue(new Error('Author not found'));

    const request = new Request('http://localhost/api/search_scripts', {
      method: 'POST',
      body: JSON.stringify({ query: 'test' }),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
    expect(data.data.scripts[0].author).toMatchObject({
      id: 'unknown-author',
      username: 'Unknown Author',
      displayName: 'Unknown Author',
      isVerifiedDeveloper: false
    });
  });

  it('should apply search filters correctly', async () => {
    mockDatabases.listDocuments.mockResolvedValue({
      total: 0,
      documents: []
    });

    const request = new Request('http://localhost/api/search_scripts', {
      method: 'POST',
      body: JSON.stringify({
        query: 'automation',
        category: 'Automation',
        canisterId: 'test-canister',
        minRating: 4.0,
        maxPrice: 10.0,
        sortBy: 'rating',
        order: 'desc',
        limit: 20,
        offset: 0
      }),
      headers: { 'Content-Type': 'application/json' }
    });

    await POST({ request } as any);

    expect(mockDatabases.listDocuments).toHaveBeenCalledWith(
      expect.any(String),
      expect.any(String),
      expect.arrayContaining([
        expect.any(Object), // isPublic filter
        expect.any(Object), // isApproved filter
        expect.any(Object), // title search
        expect.any(Object), // description search
        expect.any(Object), // category filter
        expect.any(Object), // canister filter
        expect.any(Object), // rating filter
        expect.any(Object), // price filter
        expect.any(Object), // sort order
        expect.any(Object), // limit
        expect.any(Object)  // offset
      ])
    );
  });

  it('should handle invalid JSON gracefully', async () => {
    const request = new Request('http://localhost/api/search_scripts', {
      method: 'POST',
      body: 'invalid json',
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(500);
    expect(data.success).toBe(false);
    expect(data.error).toBe('Search failed');
  });

  it('should handle database errors gracefully', async () => {
    mockDatabases.listDocuments.mockRejectedValue(new Error('Database connection failed'));

    const request = new Request('http://localhost/api/search_scripts', {
      method: 'POST',
      body: JSON.stringify({ query: 'test' }),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(500);
    expect(data.success).toBe(false);
    expect(data.error).toBe('Search failed');
  });

  it('should use default parameters when not provided', async () => {
    mockDatabases.listDocuments.mockResolvedValue({
      total: 0,
      documents: []
    });

    const request = new Request('http://localhost/api/search_scripts', {
      method: 'POST',
      body: JSON.stringify({}),
      headers: { 'Content-Type': 'application/json' }
    });

    await POST({ request } as any);

    // Should be called with default sort, limit, and offset
    expect(mockDatabases.listDocuments).toHaveBeenCalledWith(
      expect.any(String),
      expect.any(String),
      expect.arrayContaining([
        expect.any(Object), // default sort (createdAt desc)
        expect.objectContaining({ limit: 20 }), // default limit
        expect.objectContaining({ offset: 0 }) // default offset
      ])
    );
  });
});