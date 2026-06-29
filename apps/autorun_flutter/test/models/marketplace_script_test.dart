import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/services/script_runner.dart';

void main() {
  group('MarketplaceScript fromJson', () {
    test('should handle null author field gracefully', () {
      // Arrange
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
        'luaSource': 'print("Hello World")',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
        'author': null, // This is the key test case
      };

      // Act
      final script = MarketplaceScript.fromJson(json);

      // Assert
      expect(script.id, 'test-id');
      expect(script.title, 'Test Script');
      expect(script.author, isNull); // Should handle null author gracefully
    });

    test('should handle missing author field gracefully', () {
      // Arrange
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
        'luaSource': 'print("Hello World")',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
        // author field completely missing
      };

      // Act
      final script = MarketplaceScript.fromJson(json);

      // Assert
      expect(script.id, 'test-id');
      expect(script.title, 'Test Script');
      expect(script.author, isNull); // Should handle missing author gracefully
    });

    test('should handle valid author field correctly', () {
      // Arrange
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
        'luaSource': 'print("Hello World")',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
        'author': {
          'id': 'author-123',
          'username': 'testuser',
          'displayName': 'Test User',
          'isVerifiedDeveloper': true,
        },
      };

      // Act
      final script = MarketplaceScript.fromJson(json);

      // Assert
      expect(script.id, 'test-id');
      expect(script.title, 'Test Script');
      expect(script.author, isNotNull);
      expect(script.author!.id, 'author-123');
      expect(script.author!.username, 'testuser');
      expect(script.author!.displayName, 'Test User');
      expect(script.author!.isVerifiedDeveloper, isTrue);
    });

    test('should handle author field with wrong type gracefully', () {
      // Arrange
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
        'luaSource': 'print("Hello World")',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
        'author': 'invalid-string', // Wrong type - should be Map but is String
      };

      // Act
      final script = MarketplaceScript.fromJson(json);

      // Assert
      expect(script.id, 'test-id');
      expect(script.title, 'Test Script');
      expect(script.author, isNull); // Should handle wrong type gracefully by setting to null
    });

    test('should parse tags provided as JSON string', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Script',
        'description': 'Test Description',
        'category': 'Test',
        'tags': '["alpha","beta","gamma"]',
        'authorId': 'author-123',
        'authorName': 'Test Author',
        'price': 0.0,
        'currency': 'USD',
        'downloads': 0,
        'rating': 0.0,
        'reviewCount': 0,
        'luaSource': 'print("Hello World")',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.tags, equals(<String>['alpha', 'beta', 'gamma']));
    });

    test('should infer tags from comma separated string when JSON parse fails', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Script',
        'description': 'Test Description',
        'category': 'Test',
        'tags': 'alpha, beta ,  gamma ',
        'authorId': 'author-123',
        'authorName': 'Test Author',
        'price': 0.0,
        'currency': 'USD',
        'downloads': 0,
        'rating': 0.0,
        'reviewCount': 0,
        'luaSource': 'print("Hello World")',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
      };

      final script = MarketplaceScript.fromJson(json);

      expect(script.tags, equals(<String>['alpha', 'beta', 'gamma']));
    });
  });

  group('language discriminator', () {
    Map<String, dynamic> baseJson() => <String, dynamic>{
          'id': 'test-id',
          'title': 'Test Script',
          'description': 'desc',
          'category': 'Test',
          'luaSource': 'print("hi")',
          'createdAt': '2024-01-01T00:00:00.000Z',
          'updatedAt': '2024-01-01T00:00:00.000Z',
        };

    test('defaults to lua when language is absent', () {
      final script = MarketplaceScript.fromJson(baseJson());
      expect(script.language, ScriptLanguage.lua);
    });

    test('parses typescript language', () {
      final json = baseJson()..['language'] = 'typescript';
      final script = MarketplaceScript.fromJson(json);
      expect(script.language, ScriptLanguage.typescript);
    });

    test('unknown language value falls back to lua', () {
      final json = baseJson()..['language'] = 'rust';
      final script = MarketplaceScript.fromJson(json);
      expect(script.language, ScriptLanguage.lua);
    });

    test('round-trips language through toJson/fromJson', () {
      for (final lang in ScriptLanguage.values) {
        final script = MarketplaceScript(
          id: '1',
          title: 't',
          description: 'd',
          category: 'c',
          luaSource: 's',
          language: lang,
          createdAt: DateTime.utc(2024, 1, 1),
          updatedAt: DateTime.utc(2024, 1, 1),
        );
        final round = MarketplaceScript.fromJson(script.toJson());
        expect(round.language, lang);
      }
    });
  });
}
