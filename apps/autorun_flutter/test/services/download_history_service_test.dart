import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/download_history_service.dart';

void main() {
  group('DownloadHistoryService', () {
    late DownloadHistoryService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = DownloadHistoryService();
    });

    tearDown(() async {
      await service.clearHistory();
    });

    group('addToHistory', () {
      test('should add script to download history', () async {
        // Act
        await service.addToHistory(
          marketplaceScriptId: 'test-id-1',
          title: 'Test Script',
          authorName: 'Test Author',
          version: '1.0.0',
          localScriptId: 'local-id-1',
        );

        // Assert
        final history = await service.getDownloadHistory();
        expect(history.length, 1);
        expect(history.first.marketplaceScriptId, 'test-id-1');
        expect(history.first.title, 'Test Script');
        expect(history.first.authorName, 'Test Author');
        expect(history.first.version, '1.0.0');
        expect(history.first.localScriptId, 'local-id-1');
      });

      test('should handle multiple downloads', () async {
        // Act
        await service.addToHistory(
          marketplaceScriptId: 'test-id-1',
          title: 'Test Script 1',
          authorName: 'Author 1',
          version: '1.0.0',
          localScriptId: 'local-id-1',
        );
        await Future.delayed(const Duration(milliseconds: 10)); // Ensure different timestamps
        await service.addToHistory(
          marketplaceScriptId: 'test-id-2',
          title: 'Test Script 2',
          authorName: 'Author 2',
          version: '2.0.0',
          localScriptId: 'local-id-2',
        );

        // Assert
        final history = await service.getDownloadHistory();
        expect(history.length, 2);
        expect(history.first.marketplaceScriptId, 'test-id-2'); // Most recent first
        expect(history.last.marketplaceScriptId, 'test-id-1');
      });

      test('should update existing script if already downloaded', () async {
        // Act
        await service.addToHistory(
          marketplaceScriptId: 'test-id-1',
          title: 'Test Script',
          authorName: 'Original Author',
          version: '1.0.0',
          localScriptId: 'local-id-1',
        );
        await service.addToHistory(
          marketplaceScriptId: 'test-id-1',
          title: 'Updated Test Script',
          authorName: 'Updated Author',
          version: '2.0.0',
          localScriptId: 'local-id-2',
        );

        // Assert
        final history = await service.getDownloadHistory();
        expect(history.length, 1);
        expect(history.first.title, 'Updated Test Script');
        expect(history.first.authorName, 'Updated Author');
        expect(history.first.version, '2.0.0');
        expect(history.first.localScriptId, 'local-id-2');
      });
    });

    group('getDownloadHistory', () {
      test('should return empty list when no downloads', () async {
        // Act
        final history = await service.getDownloadHistory();

        // Assert
        expect(history, isEmpty);
      });

      test('should return downloads sorted by date (newest first)', () async {
        // Arrange
        await service.addToHistory(
          marketplaceScriptId: 'script-1',
          title: 'Script 1',
          authorName: 'Author 1',
          version: '1.0.0',
          localScriptId: 'local-1',
        );
        await Future.delayed(const Duration(milliseconds: 10));
        await service.addToHistory(
          marketplaceScriptId: 'script-2',
          title: 'Script 2',
          authorName: 'Author 2',
          version: '1.0.0',
          localScriptId: 'local-2',
        );
        await Future.delayed(const Duration(milliseconds: 10));
        await service.addToHistory(
          marketplaceScriptId: 'script-3',
          title: 'Script 3',
          authorName: 'Author 3',
          version: '1.0.0',
          localScriptId: 'local-3',
        );

        // Act
        final history = await service.getDownloadHistory();

        // Assert
        expect(history.length, 3);
        expect(history[0].marketplaceScriptId, 'script-3'); // Most recent
        expect(history[1].marketplaceScriptId, 'script-2');
        expect(history[2].marketplaceScriptId, 'script-1'); // Oldest
      });
    });

    group('isDownloaded', () {
      test('should return false for non-downloaded script', () async {
        // Act & Assert
        expect(await service.isDownloaded('non-existent-id'), isFalse);
      });

      test('should return true for downloaded script', () async {
        // Arrange
        await service.addToHistory(
          marketplaceScriptId: 'test-id-1',
          title: 'Test Script',
          authorName: 'Test Author',
          version: '1.0.0',
          localScriptId: 'local-id-1',
        );

        // Act & Assert
        expect(await service.isDownloaded('test-id-1'), isTrue);
      });
    });

    group('removeFromHistory', () {
      test('should remove script from download history', () async {
        // Arrange
        await service.addToHistory(
          marketplaceScriptId: 'script-1',
          title: 'Script 1',
          authorName: 'Author 1',
          version: '1.0.0',
          localScriptId: 'local-1',
        );
        await service.addToHistory(
          marketplaceScriptId: 'script-2',
          title: 'Script 2',
          authorName: 'Author 2',
          version: '1.0.0',
          localScriptId: 'local-2',
        );

        // Act
        await service.removeFromHistory('script-1');

        // Assert
        final history = await service.getDownloadHistory();
        expect(history.length, 1);
        expect(history.first.marketplaceScriptId, 'script-2');
      });

      test('should handle removing non-existent script', () async {
        // Arrange
        await service.addToHistory(
          marketplaceScriptId: 'script-1',
          title: 'Script 1',
          authorName: 'Author 1',
          version: '1.0.0',
          localScriptId: 'local-1',
        );

        // Act
        await service.removeFromHistory('non-existent-id');

        // Assert
        final history = await service.getDownloadHistory();
        expect(history.length, 1);
        expect(history.first.marketplaceScriptId, 'script-1');
      });
    });

    group('clearHistory', () {
      test('should clear all download history', () async {
        // Arrange
        await service.addToHistory(
          marketplaceScriptId: 'script-1',
          title: 'Script 1',
          authorName: 'Author 1',
          version: '1.0.0',
          localScriptId: 'local-1',
        );
        await service.addToHistory(
          marketplaceScriptId: 'script-2',
          title: 'Script 2',
          authorName: 'Author 2',
          version: '1.0.0',
          localScriptId: 'local-2',
        );

        // Act
        await service.clearHistory();

        // Assert
        final history = await service.getDownloadHistory();
        expect(history, isEmpty);
      });
    });

    group('getDownloadCount', () {
      test('should return 0 for no downloads', () async {
        // Act & Assert
        expect(await service.getDownloadCount(), 0);
      });

      test('should return correct count for downloads', () async {
        // Arrange
        await service.addToHistory(
          marketplaceScriptId: 'script-1',
          title: 'Script 1',
          authorName: 'Author 1',
          version: '1.0.0',
          localScriptId: 'local-1',
        );
        await service.addToHistory(
          marketplaceScriptId: 'script-2',
          title: 'Script 2',
          authorName: 'Author 2',
          version: '1.0.0',
          localScriptId: 'local-2',
        );

        // Act & Assert
        expect(await service.getDownloadCount(), 2);
      });
    });

    group('persistence', () {
      test('should persist data across service instances', () async {
        // Arrange
        await service.addToHistory(
          marketplaceScriptId: 'test-id-1',
          title: 'Test Script',
          authorName: 'Test Author',
          version: '1.0.0',
          localScriptId: 'local-id-1',
        );

        // Act - Create new service instance
        final newService = DownloadHistoryService();

        // Assert
        final history = await newService.getDownloadHistory();
        expect(history.length, 1);
        expect(history.first.marketplaceScriptId, 'test-id-1');
        expect(history.first.authorName, 'Test Author');
      });
    });

    group('error handling', () {
      test('should handle empty version gracefully', () async {
        // Act
        await service.addToHistory(
          marketplaceScriptId: 'test-id-1',
          title: 'Test Script',
          authorName: 'Test Author',
          version: null,
          localScriptId: 'local-id-1',
        );

        // Assert
        final history = await service.getDownloadHistory();
        expect(history.length, 1);
        expect(history.first.version, isNull);
      });

      test('should handle empty strings gracefully', () async {
        // Act
        await service.addToHistory(
          marketplaceScriptId: '',
          title: '',
          authorName: '',
          version: '',
          localScriptId: '',
        );

        // Assert
        final history = await service.getDownloadHistory();
        expect(history.length, 1);
        expect(history.first.marketplaceScriptId, isEmpty);
        expect(history.first.title, isEmpty);
        expect(history.first.authorName, isEmpty);
        expect(history.first.version, '');
        expect(history.first.localScriptId, isEmpty);
      });
    });

    group('DownloadRecord serialization', () {
      test('should serialize DownloadRecord to JSON correctly', () {
        // Arrange
        final record = DownloadRecord(
          marketplaceScriptId: 'test-id',
          title: 'Test Script',
          authorName: 'Test Author',
          version: '1.0.0',
          downloadedAt: DateTime.parse('2023-01-01T00:00:00.000Z'),
          localScriptId: 'local-id',
        );

        // Act
        final json = record.toJson();

        // Assert
        expect(json['marketplaceScriptId'], 'test-id');
        expect(json['title'], 'Test Script');
        expect(json['authorName'], 'Test Author');
        expect(json['version'], '1.0.0');
        expect(json['downloadedAt'], '2023-01-01T00:00:00.000Z');
        expect(json['localScriptId'], 'local-id');
      });

      test('should deserialize DownloadRecord from JSON correctly', () {
        // Arrange
        final json = {
          'marketplaceScriptId': 'test-id',
          'title': 'Test Script',
          'authorName': 'Test Author',
          'version': '1.0.0',
          'downloadedAt': '2023-01-01T00:00:00.000Z',
          'localScriptId': 'local-id',
        };

        // Act
        final record = DownloadRecord.fromJson(json);

        // Assert
        expect(record.marketplaceScriptId, 'test-id');
        expect(record.title, 'Test Script');
        expect(record.authorName, 'Test Author');
        expect(record.version, '1.0.0');
        expect(record.downloadedAt, DateTime.parse('2023-01-01T00:00:00.000Z'));
        expect(record.localScriptId, 'local-id');
      });

      test('should handle null version in JSON', () {
        // Arrange
        final json = {
          'marketplaceScriptId': 'test-id',
          'title': 'Test Script',
          'authorName': 'Test Author',
          'version': null,
          'downloadedAt': '2023-01-01T00:00:00.000Z',
          'localScriptId': 'local-id',
        };

        // Act
        final record = DownloadRecord.fromJson(json);

        // Assert
        expect(record.version, isNull);
      });
    });
  });
}