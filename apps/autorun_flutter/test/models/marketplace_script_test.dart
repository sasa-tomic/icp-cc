import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';

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
  });
}