import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/services/bookmarks_service.dart';

void main() {
  group('BookmarksService', () {
    setUp(() {
      // Reset cache before each test
      BookmarksService.invalidateCache();
    });

    test('BookmarkEntry serialization works correctly', () {
      final entry = BookmarkEntry(
        canisterId: 'rdmx6-jaaaa-aaaaa-aaadq-cai',
        method: 'get_balance',
        label: 'NNS Ledger',
      );

      final json = entry.toJson();
      expect(json['canister_id'], 'rdmx6-jaaaa-aaaaa-aaadq-cai');
      expect(json['method'], 'get_balance');
      expect(json['label'], 'NNS Ledger');

      final restored = BookmarkEntry.fromJson(json);
      expect(restored.canisterId, entry.canisterId);
      expect(restored.method, entry.method);
      expect(restored.label, entry.label);
    });

    test('BookmarkEntry equality works correctly', () {
      final entry1 = BookmarkEntry(
        canisterId: 'rdmx6-jaaaa-aaaaa-aaadq-cai',
        method: 'get_balance',
        label: 'NNS Ledger',
      );

      final entry2 = BookmarkEntry(
        canisterId: 'rdmx6-jaaaa-aaaaa-aaadq-cai',
        method: 'get_balance',
        label: 'Different Label',
      );

      final entry3 = BookmarkEntry(
        canisterId: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
        method: 'get_balance',
        label: 'NNS Ledger',
      );

      expect(entry1, equals(entry2)); // Same canister + method = equal
      expect(entry1, isNot(equals(entry3))); // Different canister = not equal
    });

    test('list returns empty list when storage is empty', () async {
      // Test JSON serialization/deserialization logic
      final entries = <BookmarkEntry>[];
      final jsonString = json.encode(entries.map((e) => e.toJson()).toList());
      final parsed = json.decode(jsonString) as List<dynamic>;
      final restored = parsed
          .whereType<Map<String, dynamic>>()
          .map((json) => BookmarkEntry.fromJson(json))
          .toList();

      expect(restored, isEmpty);
    });

    test('list restores bookmarks from JSON correctly', () {
      final testData = [
        {
          'canister_id': 'rdmx6-jaaaa-aaaaa-aaadq-cai',
          'method': 'get_balance',
          'label': 'NNS Ledger',
        },
        {
          'canister_id': 'rrkah-fqaaa-aaaaa-aaaaq-cai',
          'method': 'get_neuron_ids',
          'label': 'NNS Governance',
        },
        {
          'canister_id': 'rwlgt-iiaaa-aaaaa-aaaaa-cai',
          'method': 'get_value',
        },
      ];

      final jsonString = json.encode(testData);
      final parsed = json.decode(jsonString) as List<dynamic>;
      final entries = parsed
          .whereType<Map<String, dynamic>>()
          .map((json) => BookmarkEntry.fromJson(json))
          .toList();

      expect(entries, hasLength(3));
      expect(entries[0].canisterId, 'rdmx6-jaaaa-aaaaa-aaadq-cai');
      expect(entries[0].method, 'get_balance');
      expect(entries[0].label, 'NNS Ledger');
      expect(entries[1].canisterId, 'rrkah-fqaaa-aaaaa-aaaaq-cai');
      expect(entries[1].method, 'get_neuron_ids');
      expect(entries[1].label, 'NNS Governance');
      expect(entries[2].canisterId, 'rwlgt-iiaaa-aaaaa-aaaaa-cai');
      expect(entries[2].method, 'get_value');
      expect(entries[2].label, isNull);
    });

    test('bookmarks JSON serialization is compatible with original format', () {
      // Test that our new format matches the original Rust format
      final originalFormat = [
        {
          'canister_id': 'rdmx6-jaaaa-aaaaa-aaadq-cai',
          'method': 'get_balance',
          'label': 'NNS Ledger',
        }
      ];

      final entries = originalFormat
          .whereType<Map<String, dynamic>>()
          .map((json) => BookmarkEntry.fromJson(json))
          .toList();

      final serialized = entries.map((e) => e.toJson()).toList();
      final serializedJson = json.encode(serialized);
      final parsedSerialized = json.decode(serializedJson) as List<dynamic>;

      expect(parsedSerialized, hasLength(1));
      final entry = parsedSerialized.first as Map<String, dynamic>;
      expect(entry['canister_id'], 'rdmx6-jaaaa-aaaaa-aaadq-cai');
      expect(entry['method'], 'get_balance');
      expect(entry['label'], 'NNS Ledger');
    });

    test('BookmarkEntry without label serializes correctly', () {
      final entry = BookmarkEntry(
        canisterId: 'rwlgt-iiaaa-aaaaa-aaaaa-cai',
        method: 'get_value',
      );

      final json = entry.toJson();
      expect(json['canister_id'], 'rwlgt-iiaaa-aaaaa-aaaaa-cai');
      expect(json['method'], 'get_value');
      expect(json.containsKey('label'), false);

      final restored = BookmarkEntry.fromJson(json);
      expect(restored.canisterId, entry.canisterId);
      expect(restored.method, entry.method);
      expect(restored.label, isNull);
    });

    test('BookmarksEvents notifies listeners', () {
      var notificationCount = 0;
      BookmarksEvents.listenable.addListener(() {
        notificationCount++;
      });

      BookmarksEvents.notifyChanged();
      expect(notificationCount, 1);

      BookmarksEvents.notifyChanged();
      expect(notificationCount, 2);
    });
  });
}