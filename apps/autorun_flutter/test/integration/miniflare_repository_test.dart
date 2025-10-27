import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import '../test_helpers/miniflare_script_repository.dart';
import '../test_helpers/miniflare_test_helper.dart';

/// Integration tests for MiniflareScriptRepository
/// These tests verify that the repository can work with a real Miniflare deployment
void main() {
  group('MiniflareScriptRepository Integration Tests', () {
    late MiniflareScriptRepository repository;
    final List<String> createdScriptIds = [];

    setUpAll(() async {
      // Setup test environment
      await MiniflareTestHelper.setupMiniflareTestEnvironment(
        requireServer: false, // Allow tests to run in offline mode
      );
    });

    setUp(() async {
      // Create a fresh repository for each test
      repository = MiniflareTestHelper.createTestRepository();
    });

    tearDown(() async {
      // Clean up created scripts
      await MiniflareTestHelper.cleanupTestData(
        scriptIds: createdScriptIds,
      );
      createdScriptIds.clear();
      
      // Dispose repository
      repository.dispose();
    });

    group('Basic CRUD Operations', () {
      test('should create and retrieve script', () async {
        // Arrange
        final testScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'CRUD Test Script',
        );

        // Act
        await repository.saveScript(testScript);
        createdScriptIds.add(testScript.id);

        // Assert
        await repository.expectScriptExists(testScript.id);
        final retrievedScript = await repository.getScriptById(testScript.id);
        expect(retrievedScript!.title, equals('CRUD Test Script'));
        expect(retrievedScript.luaSource, contains('Hello from test script'));
      });

      test('should update existing script', () async {
        // Arrange
        final originalScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Original Title',
        );
        await repository.saveScript(originalScript);
        createdScriptIds.add(originalScript.id);

        // Act
        final updatedMetadata = Map<String, dynamic>.from(originalScript.metadata);
        updatedMetadata['version'] = '2.0.0';
        
        final updatedScript = ScriptRecord(
          id: originalScript.id,
          title: 'Updated Title',
          luaSource: originalScript.luaSource,
          metadata: updatedMetadata,
          createdAt: originalScript.createdAt,
          updatedAt: DateTime.now(),
        );
        await repository.saveScript(updatedScript);

        // Assert
        final retrievedScript = await repository.getScriptById(originalScript.id);
        expect(retrievedScript!.title, equals('Updated Title'));
        expect(retrievedScript.metadata['version'], equals('2.0.0'));
      });

      test('should delete script', () async {
        // Arrange
        final testScript = MiniflareScriptRepositoryTestExtensions.createTestScript();
        await repository.saveScript(testScript);
        createdScriptIds.add(testScript.id);

        // Verify it exists
        await repository.expectScriptExists(testScript.id);

        // Act
        await repository.deleteScript(testScript.id);
        createdScriptIds.remove(testScript.id); // Remove from cleanup list

        // Assert
        await repository.expectScriptNotExists(testScript.id);
      });

      test('should list all scripts', () async {
        // Arrange
        final testScripts = MiniflareScriptRepositoryTestExtensions.createTestScripts(count: 3);
        
        for (final script in testScripts) {
          await repository.saveScript(script);
          createdScriptIds.add(script.id);
        }

        // Act
        final allScripts = await repository.getAllScripts();

        // Assert
        expect(allScripts.length, greaterThanOrEqualTo(3));
        for (final testScript in testScripts) {
          expect(allScripts.any((s) => s.id == testScript.id), isTrue);
        }
      });
    });

    group('Search and Filtering', () {
      test('should search scripts by title', () async {
        // Arrange
        final searchableScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Unique Searchable Title',
        );
        await repository.saveScript(searchableScript);
        createdScriptIds.add(searchableScript.id);

        // Act
        final searchResults = await repository.searchScripts('Unique Searchable');

        // Assert
        expect(searchResults.any((s) => s.id == searchableScript.id), isTrue);
      });

      test('should filter scripts by category', () async {
        // Arrange
        final devScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Dev Script',
          metadata: {'category': 'Development'},
        );
        final utilScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Util Script',
          metadata: {'category': 'Utility'},
        );
        
        await repository.saveScript(devScript);
        await repository.saveScript(utilScript);
        createdScriptIds.addAll([devScript.id, utilScript.id]);

        // Act
        final devScripts = await repository.getScriptsByCategory('Development');
        final utilScripts = await repository.getScriptsByCategory('Utility');

        // Assert
        expect(devScripts.any((s) => s.id == devScript.id), isTrue);
        expect(utilScripts.any((s) => s.id == utilScript.id), isTrue);
      });

      test('should get only public scripts', () async {
        // Arrange
        final publicScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Public Script',
          metadata: {'isPublic': true},
        );
        final privateScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Private Script',
          metadata: {'isPublic': false},
        );
        
        await repository.saveScript(publicScript);
        await repository.saveScript(privateScript);
        createdScriptIds.addAll([publicScript.id, privateScript.id]);

        // Act
        final publicScripts = await repository.getPublicScripts();

        // Assert
        expect(publicScripts.any((s) => s.id == publicScript.id), isTrue);
        expect(publicScripts.any((s) => s.id == privateScript.id), isFalse);
      });
    });

    group('Publishing', () {
      test('should publish script successfully', () async {
        // Arrange
        final privateScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Script to Publish',
          metadata: {'isPublic': false},
        );
        await repository.saveScript(privateScript);
        createdScriptIds.add(privateScript.id);

        // Act
        final publishedId = await repository.publishScript(privateScript);

        // Assert
        expect(publishedId, equals(privateScript.id));
        final publishedScript = await repository.getScriptById(publishedId);
        expect(publishedScript!.metadata['isPublic'], isTrue);
      });
    });

    group('Counting', () {
      test('should get accurate script count', () async {
        // Arrange
        final initialCount = await repository.getScriptsCount();
        final newScript = MiniflareScriptRepositoryTestExtensions.createTestScript();
        await repository.saveScript(newScript);
        createdScriptIds.add(newScript.id);

        // Act
        final finalCount = await repository.getScriptsCount();

        // Assert
        expect(finalCount, greaterThanOrEqualTo(initialCount + 1));
      });
    });

    group('Error Handling', () {
      test('should handle server unavailability gracefully', () async {
        // Arrange - Use a non-existent server
        final offlineRepository = MiniflareScriptRepository(
          baseUrl: 'http://localhost:9999',
        );

        // Act & Assert - Should not throw exceptions
        expect(offlineRepository.loadScripts(), completes);
        expect(offlineRepository.getAllScripts(), completes);
        expect(offlineRepository.getScriptById('nonexistent'), completes);
        expect(offlineRepository.searchScripts('test'), completes);
        expect(offlineRepository.getScriptsByCategory('test'), completes);
        expect(offlineRepository.getPublicScripts(), completes);
        expect(offlineRepository.getScriptsCount(), completes);

        // Cleanup
        offlineRepository.dispose();
      });

      test('should handle persistence errors gracefully', () async {
        // Arrange
        final testScript = MiniflareScriptRepositoryTestExtensions.createTestScript();

        // Act & Assert - Should not throw exceptions even if server is unavailable
        expect(repository.persistScripts([testScript]), completes);
        expect(repository.saveScript(testScript), completes);
        expect(repository.deleteScript('nonexistent'), completes);
      });
    });
  });
}