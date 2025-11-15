// Test setup file for Jest
const { Client, Databases, Functions } = require('node-appwrite');

// Mock Appwrite client for testing
jest.mock('node-appwrite', () => ({
  Client: jest.fn().mockImplementation(() => ({
    setEndpoint: jest.fn().mockReturnThis(),
    setProject: jest.fn().mockReturnThis(),
    setKey: jest.fn().mockReturnThis(),
  })),
  Databases: jest.fn().mockImplementation(() => ({
    getDocument: jest.fn(),
    listDocuments: jest.fn(),
    createDocument: jest.fn(),
    updateDocument: jest.fn(),
    deleteDocument: jest.fn(),
  })),
  Functions: jest.fn().mockImplementation(() => ({
    createExecution: jest.fn(),
  })),
}));

// Mock console methods to reduce test noise
global.console = {
  ...console,
  log: jest.fn(),
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
};

// Set test environment variables
process.env.NODE_ENV = 'test';
process.env.APPWRITE_ENDPOINT = 'https://test.appwrite.io/v1';
process.env.APPWRITE_PROJECT_ID = 'test-project';
process.env.APPWRITE_API_KEY = 'test-key';
process.env.DATABASE_ID = 'test-db';
process.env.SCRIPTS_COLLECTION_ID = 'test-scripts';
process.env.REVIEWS_COLLECTION_ID = 'test-reviews';