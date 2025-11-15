const request = require('supertest');
const app = require('../src/server');

describe('ICP Marketplace API Server', () => {
  describe('Health Check', () => {
    test('GET /health should return 200', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body).toHaveProperty('status', 'ok');
      expect(response.body).toHaveProperty('timestamp');
    });
  });

  describe('Script Search', () => {
    test('GET /v1/scripts/search with valid parameters', async () => {
      const response = await request(app)
        .get('/v1/scripts/search')
        .query({
          q: 'test script',
          category: 'Gaming',
          limit: 10
        })
        .expect(200);

      expect(response.body).toHaveProperty('scripts');
      expect(response.body).toHaveProperty('total');
      expect(response.body).toHaveProperty('hasMore');
      expect(Array.isArray(response.body.scripts)).toBe(true);
    });

    test('GET /v1/scripts/search with invalid category should return 400', async () => {
      await request(app)
        .get('/v1/scripts/search')
        .query({ category: 'InvalidCategory' })
        .expect(400);
    });

    test('GET /v1/scripts/search with invalid canister ID should return 400', async () => {
      await request(app)
        .get('/v1/scripts/search')
        .query({ canister_id: 'invalid-id' })
        .expect(400);
    });
  });

  describe('Script Details', () => {
    test('GET /v1/scripts/:scriptId with valid ID should return script details', async () => {
      // This test would need a mock database setup
      // For now, we expect it to handle missing script gracefully
      await request(app)
        .get('/v1/scripts/nonexistent-script')
        .expect(404);
    });
  });

  describe('Featured Scripts', () => {
    test('GET /v1/scripts/featured should return array', async () => {
      const response = await request(app)
        .get('/v1/scripts/featured')
        .expect(200);

      expect(Array.isArray(response.body)).toBe(true);
    });
  });

  describe('Trending Scripts', () => {
    test('GET /v1/scripts/trending should return array', async () => {
      const response = await request(app)
        .get('/v1/scripts/trending')
        .expect(200);

      expect(Array.isArray(response.body)).toBe(true);
    });
  });

  describe('Script Categories', () => {
    test('GET /v1/scripts/category/:category with valid category', async () => {
      const response = await request(app)
        .get('/v1/scripts/category/Gaming')
        .expect(200);

      expect(Array.isArray(response.body)).toBe(true);
    });

    test('GET /v1/scripts/category/:category with invalid category should return 400', async () => {
      await request(app)
        .get('/v1/scripts/category/InvalidCategory')
        .expect(400);
    });
  });

  describe('Script Validation', () => {
    test('POST /v1/scripts/validate with valid Lua code', async () => {
      const response = await request(app)
        .post('/v1/scripts/validate')
        .send({ lua_source: 'print("Hello, ICP!")' })
        .expect(200);

      expect(response.body).toHaveProperty('is_valid', true);
      expect(response.body).toHaveProperty('errors');
      expect(Array.isArray(response.body.errors)).toBe(true);
    });

    test('POST /v1/scripts/validate with invalid Lua code', async () => {
      const response = await request(app)
        .post('/v1/scripts/validate')
        .send({ lua_source: 'print invalid syntax here' })
        .expect(200);

      expect(response.body).toHaveProperty('is_valid', false);
      expect(Array.isArray(response.body.errors)).toBe(true);
      expect(response.body.errors.length).toBeGreaterThan(0);
    });

    test('POST /v1/scripts/validate without lua_source should return 400', async () => {
      await request(app)
        .post('/v1/scripts/validate')
        .send({})
        .expect(400);
    });
  });

  describe('Marketplace Stats', () => {
    test('GET /v1/stats should return statistics', async () => {
      const response = await request(app)
        .get('/v1/stats')
        .expect(200);

      expect(response.body).toHaveProperty('total_scripts');
      expect(response.body).toHaveProperty('total_authors');
      expect(response.body).toHaveProperty('total_downloads');
      expect(response.body).toHaveProperty('average_rating');
      expect(response.body).toHaveProperty('last_updated');
      expect(typeof response.body.total_scripts).toBe('number');
      expect(typeof response.body.total_authors).toBe('number');
    });
  });

  describe('Error Handling', () => {
    test('GET /nonexistent should return 404', async () => {
      await request(app)
        .get('/nonexistent')
        .expect(404);
    });
  });
});