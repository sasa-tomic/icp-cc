import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';

void main() {
  group('Local Script Search Logic', () {
    test('filters scripts by title case-insensitively', () {
      final scripts = [
        ScriptRecord(
          id: '1',
          title: 'Hello World',
          bundle: 'print("hello")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ScriptRecord(
          id: '2',
          title: 'Farewell Message',
          bundle: 'print("bye")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ScriptRecord(
          id: '3',
          title: 'HELLO Advanced',
          bundle: 'print("advanced")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      const query = 'hello';
      final filtered = scripts.where((s) {
        return s.title.toLowerCase().contains(query.toLowerCase());
      }).toList();

      expect(filtered.length, equals(2));
      expect(filtered.any((s) => s.id == '1'), isTrue);
      expect(filtered.any((s) => s.id == '3'), isTrue);
      expect(filtered.any((s) => s.id == '2'), isFalse);
    });

    test('empty query shows all scripts', () {
      final scripts = [
        ScriptRecord(
          id: '1',
          title: 'Hello World',
          bundle: 'print("hello")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ScriptRecord(
          id: '2',
          title: 'Farewell Message',
          bundle: 'print("bye")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      const query = '';
      final filtered = scripts.where((s) {
        if (query.isEmpty) return true;
        return s.title.toLowerCase().contains(query.toLowerCase());
      }).toList();

      expect(filtered.length, equals(2));
    });

    test('filters scripts by partial title match', () {
      final scripts = [
        ScriptRecord(
          id: '1',
          title: 'Token Generator',
          bundle: 'print("token")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ScriptRecord(
          id: '2',
          title: 'Random Number',
          bundle: 'print("random")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ScriptRecord(
          id: '3',
          title: 'My Token Script',
          bundle: 'print("my token")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      const query = 'token';
      final filtered = scripts.where((s) {
        return s.title.toLowerCase().contains(query.toLowerCase());
      }).toList();

      expect(filtered.length, equals(2));
      expect(filtered.any((s) => s.id == '1'), isTrue);
      expect(filtered.any((s) => s.id == '3'), isTrue);
    });

    test('no match returns empty list', () {
      final scripts = [
        ScriptRecord(
          id: '1',
          title: 'Hello World',
          bundle: 'print("hello")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ScriptRecord(
          id: '2',
          title: 'Farewell Message',
          bundle: 'print("bye")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      const query = 'xyz';
      final filtered = scripts.where((s) {
        return s.title.toLowerCase().contains(query.toLowerCase());
      }).toList();

      expect(filtered, isEmpty);
    });

    test('filters by marketplace author when available', () {
      final scripts = [
        ScriptRecord(
          id: '1',
          title: 'Hello World',
          bundle: 'print("hello")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          metadata: {'marketplace_author': 'john_doe'},
        ),
        ScriptRecord(
          id: '2',
          title: 'Test Script',
          bundle: 'print("test")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          metadata: {'marketplace_author': 'jane_smith'},
        ),
        ScriptRecord(
          id: '3',
          title: 'Another Script',
          bundle: 'print("another")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      const query = 'john';
      final filtered = scripts.where((s) {
        final titleMatch = s.title.toLowerCase().contains(query.toLowerCase());
        final authorMatch =
            s.marketplaceAuthor?.toLowerCase().contains(query.toLowerCase()) ??
                false;
        return titleMatch || authorMatch;
      }).toList();

      expect(filtered.length, equals(1));
      expect(filtered.any((s) => s.id == '1'), isTrue);
    });

    test('filters combining title and author matching', () {
      final scripts = [
        ScriptRecord(
          id: '1',
          title: 'NFT Creator',
          bundle: 'print("nft")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          metadata: {'marketplace_author': 'alice'},
        ),
        ScriptRecord(
          id: '2',
          title: 'Token Generator',
          bundle: 'print("token")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          metadata: {'marketplace_author': 'bob'},
        ),
        ScriptRecord(
          id: '3',
          title: 'Random Number',
          bundle: 'print("random")',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          metadata: {'marketplace_author': 'alice'},
        ),
      ];

      // Search for "alice" should find scripts by author alice
      const query = 'alice';
      final filtered = scripts.where((s) {
        final titleMatch = s.title.toLowerCase().contains(query.toLowerCase());
        final authorMatch =
            s.marketplaceAuthor?.toLowerCase().contains(query.toLowerCase()) ??
                false;
        return titleMatch || authorMatch;
      }).toList();

      expect(filtered.length, equals(2));
      expect(filtered.any((s) => s.id == '1'), isTrue);
      expect(filtered.any((s) => s.id == '3'), isTrue);
    });
  });
}
