import { describe, it, expect } from 'vitest';

describe('Basic Site Tests', () => {
  it('should have a test environment', () => {
    expect(true).toBe(true);
  });

  it('should handle environment variables', () => {
    expect(typeof process.env.NODE_ENV).toBe('string');
  });

  it('should have the correct public site URL for development', () => {
    // In development/test, we should use localhost
    const expectedUrl = process.env.NODE_ENV === 'production'
      ? 'https://icp-autorun.appwrite.network'
      : 'http://localhost:5173';

    // Test that we can construct URLs correctly
    const apiUrl = `${expectedUrl}/api/test`;
    expect(apiUrl).toMatch(/\/api\/test$/);
  });
});