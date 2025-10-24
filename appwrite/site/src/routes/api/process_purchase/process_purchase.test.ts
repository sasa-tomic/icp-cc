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
    createDocument: vi.fn(),
    updateDocument: vi.fn(),
  })),
  Query: {
    equal: vi.fn(),
  },
}));

describe('/api/process_purchase', () => {
  let mockDatabases: any;

  beforeEach(async () => {
    vi.clearAllMocks();
    const { Databases } = await import('node-appwrite');
    mockDatabases = new (Databases as any)();
  });

  it('should process a purchase successfully', async () => {
    const purchaseData = {
      userId: 'user1',
      scriptId: 'script1',
      paymentMethod: 'credit_card',
      price: 9.99,
      transactionId: 'txn123'
    };

    const mockScript = {
      $id: 'script1',
      title: 'Test Script',
      description: 'A test script',
      luaSource: '-- test script',
      iconUrl: 'https://example.com/icon.png',
      screenshots: ['https://example.com/screenshot.png'],
      version: '1.0.0',
      compatibility: 'ICP',
      isPublic: true,
      isApproved: true,
      authorId: 'author1',
      downloads: 10,
      currency: 'USD'
    };

    const mockPurchase = {
      $id: 'purchase1',
      ...purchaseData,
      status: 'completed'
    };

    const mockUser = {
      $id: 'user1',
      totalDownloads: 5
    };

    // Mock database responses
    mockDatabases.listDocuments.mockResolvedValue({ total: 0, documents: [] }); // No existing purchases
    mockDatabases.getDocument
      .mockResolvedValueOnce(mockScript) // Get script
      .mockResolvedValueOnce(mockUser); // Get user (if user is author)
    mockDatabases.createDocument.mockResolvedValue(mockPurchase); // Create purchase
    mockDatabases.updateDocument.mockResolvedValue({}); // Update script stats

    const request = new Request('http://localhost/api/process_purchase', {
      method: 'POST',
      body: JSON.stringify(purchaseData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
    expect(data.data.purchase).toMatchObject({
      userId: 'user1',
      scriptId: 'script1',
      price: 9.99,
      status: 'completed'
    });
    expect(data.data.script).toMatchObject({
      id: 'script1',
      title: 'Test Script',
      luaSource: '-- test script'
    });
  });

  it('should reject purchases with missing required fields', async () => {
    const incompleteData = {
      userId: 'user1',
      scriptId: 'script1'
      // Missing paymentMethod, price, transactionId
    };

    const request = new Request('http://localhost/api/process_purchase', {
      method: 'POST',
      body: JSON.stringify(incompleteData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(400);
    expect(data.success).toBe(false);
    expect(data.error).toBe('Missing required fields');
  });

  it('should prevent duplicate purchases', async () => {
    const purchaseData = {
      userId: 'user1',
      scriptId: 'script1',
      paymentMethod: 'credit_card',
      price: 9.99,
      transactionId: 'txn123'
    };

    // Mock existing purchase
    mockDatabases.listDocuments.mockResolvedValue({
      total: 1,
      documents: [{ status: 'completed' }]
    });

    const request = new Request('http://localhost/api/process_purchase', {
      method: 'POST',
      body: JSON.stringify(purchaseData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(409);
    expect(data.success).toBe(false);
    expect(data.error).toBe('Script already purchased');
  });

  it('should reject purchases for unavailable scripts', async () => {
    const purchaseData = {
      userId: 'user1',
      scriptId: 'script1',
      paymentMethod: 'credit_card',
      price: 9.99,
      transactionId: 'txn123'
    };

    const mockUnavailableScript = {
      $id: 'script1',
      isPublic: false, // Not public
      isApproved: true
    };

    mockDatabases.listDocuments.mockResolvedValue({ total: 0, documents: [] });
    mockDatabases.getDocument.mockResolvedValue(mockUnavailableScript);

    const request = new Request('http://localhost/api/process_purchase', {
      method: 'POST',
      body: JSON.stringify(purchaseData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(404);
    expect(data.success).toBe(false);
    expect(data.error).toBe('Script not available for purchase');
  });

  it('should update download counts correctly', async () => {
    const purchaseData = {
      userId: 'user1',
      scriptId: 'script1',
      paymentMethod: 'credit_card',
      price: 9.99,
      transactionId: 'txn123'
    };

    const mockScript = {
      $id: 'script1',
      isPublic: true,
      isApproved: true,
      authorId: 'user1', // User is the author
      downloads: 10
    };

    mockDatabases.listDocuments.mockResolvedValue({ total: 0, documents: [] });
    mockDatabases.getDocument
      .mockResolvedValueOnce(mockScript) // Get script
      .mockResolvedValueOnce({ totalDownloads: 5 }); // Get user

    mockDatabases.createDocument.mockResolvedValue({ $id: 'purchase1' });
    mockDatabases.updateDocument.mockResolvedValue({});

    const request = new Request('http://localhost/api/process_purchase', {
      method: 'POST',
      body: JSON.stringify(purchaseData),
      headers: { 'Content-Type': 'application/json' }
    });

    await POST({ request } as any);

    // Should update script downloads
    expect(mockDatabases.updateDocument).toHaveBeenCalledWith(
      expect.any(String),
      expect.any(String),
      'script1',
      { downloads: 11 }
    );

    // Should update user total downloads (since user is author)
    expect(mockDatabases.updateDocument).toHaveBeenCalledWith(
      expect.any(String),
      expect.any(String),
      'user1',
      { totalDownloads: 6 }
    );
  });

  it('should handle database errors gracefully', async () => {
    const purchaseData = {
      userId: 'user1',
      scriptId: 'script1',
      paymentMethod: 'credit_card',
      price: 9.99,
      transactionId: 'txn123'
    };

    mockDatabases.listDocuments.mockRejectedValue(new Error('Database connection failed'));

    const request = new Request('http://localhost/api/process_purchase', {
      method: 'POST',
      body: JSON.stringify(purchaseData),
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(500);
    expect(data.success).toBe(false);
    expect(data.error).toBe('Purchase processing failed');
  });

  it('should handle invalid JSON gracefully', async () => {
    const request = new Request('http://localhost/api/process_purchase', {
      method: 'POST',
      body: 'invalid json',
      headers: { 'Content-Type': 'application/json' }
    });

    const response = await POST({ request } as any);
    const data = await response.json();

    expect(response.status).toBe(500);
    expect(data.success).toBe(false);
    expect(data.error).toBe('Purchase processing failed');
  });
});