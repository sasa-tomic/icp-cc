import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';

void main() {
  group('MarketplaceScript fromJson', () {
    test('handles null author field gracefully', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Script',
        'description': 'Test Description',
        'category': 'Test',
        'tags': ['test'],
        'authorId': 'author-123',
        'authorName': 'Test Author',
        'price': 0.0,
        'currency': 'USD',
        'downloads': 0,
        'rating': 0.0,
        'reviewCount': 0,
        'bundle': 'globalThis.init=()=>({state:{},effects:[]});',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
        'author': null,
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.id, 'test-id');
      expect(script.title, 'Test Script');
      expect(script.bundle, isNotEmpty);
      expect(script.author, isNull);
    });

    test('handles missing author field gracefully', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Script',
        'description': 'Test Description',
        'category': 'Test',
        'tags': ['test'],
        'authorId': 'author-123',
        'authorName': 'Test Author',
        'price': 0.0,
        'currency': 'USD',
        'downloads': 0,
        'rating': 0.0,
        'reviewCount': 0,
        'bundle': 'globalThis.init=()=>({state:{},effects:[]});',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.id, 'test-id');
      expect(script.title, 'Test Script');
      expect(script.author, isNull);
    });

    test('parses a valid author field', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Script',
        'description': 'Test Description',
        'category': 'Test',
        'tags': ['test'],
        'authorId': 'author-123',
        'authorName': 'Test Author',
        'price': 0.0,
        'currency': 'USD',
        'downloads': 0,
        'rating': 0.0,
        'reviewCount': 0,
        'bundle': 'globalThis.init=()=>({state:{},effects:[]});',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
        'author': {
          'id': 'author-123',
          'username': 'testuser',
          'displayName': 'Test User',
          'isVerifiedDeveloper': true,
        },
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.author, isNotNull);
      expect(script.author!.id, 'author-123');
      expect(script.author!.username, 'testuser');
      expect(script.author!.displayName, 'Test User');
      expect(script.author!.isVerifiedDeveloper, isTrue);
    });

    test('handles author field with wrong type gracefully', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Script',
        'description': 'Test Description',
        'category': 'Test',
        'tags': ['test'],
        'authorId': 'author-123',
        'authorName': 'Test Author',
        'price': 0.0,
        'currency': 'USD',
        'downloads': 0,
        'rating': 0.0,
        'reviewCount': 0,
        'bundle': 'globalThis.init=()=>({state:{},effects:[]});',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
        'author': 'invalid-string',
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.author, isNull);
    });

    test('parses tags provided as JSON string', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Script',
        'description': 'Test Description',
        'category': 'Test',
        'tags': '["alpha","beta","gamma"]',
        'bundle': 'globalThis.init=()=>({state:{},effects:[]});',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.tags, equals(<String>['alpha', 'beta', 'gamma']));
    });

    test('infers tags from comma separated string when JSON parse fails', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Script',
        'description': 'Test Description',
        'category': 'Test',
        'tags': 'alpha, beta ,  gamma ',
        'bundle': 'globalThis.init=()=>({state:{},effects:[]});',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.tags, equals(<String>['alpha', 'beta', 'gamma']));
    });
  });

  group('MarketplaceScript bundle round-trip', () {
    test('toJson/fromJson preserves the bundle field', () {
      const bundle = 'globalThis.init=()=>({state:{count:0},effects:[]});';
      final now = DateTime.utc(2024, 1, 1);
      final script = MarketplaceScript(
        id: '1',
        title: 't',
        description: 'd',
        category: 'c',
        bundle: bundle,
        createdAt: now,
        updatedAt: now,
      );
      final round = MarketplaceScript.fromJson(script.toJson());
      expect(round.bundle, bundle);
    });
  });
}
