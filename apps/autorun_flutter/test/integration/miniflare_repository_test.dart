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
      repository = MiniflareTestHelper.createTestRepository(failSilently: false);
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
        final savedScriptId = await repository.saveScript(testScript);
        createdScriptIds.add(savedScriptId);

        // Assert
        await repository.expectScriptExists(savedScriptId);
        final retrievedScript = await repository.getScriptById(savedScriptId);
        expect(retrievedScript!.title, equals('CRUD Test Script'));
        expect(retrievedScript.luaSource, contains('Hello from test script'));
      });

      test('should update existing script', () async {
        // Arrange
        final originalScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Original Title',
        );
        final savedScriptId = await repository.saveScript(originalScript);
        createdScriptIds.add(savedScriptId);

        // Act
        final updatedMetadata = Map<String, dynamic>.from(originalScript.metadata);
        updatedMetadata['version'] = '2.0.0';
        
        final updatedScript = ScriptRecord(
          id: savedScriptId,
          title: 'Updated Title',
          luaSource: originalScript.luaSource,
          metadata: updatedMetadata,
          createdAt: originalScript.createdAt,
          updatedAt: DateTime.now(),
        );
        await repository.saveScript(updatedScript);

        // Assert
        final retrievedScript = await repository.getScriptById(savedScriptId);
        expect(retrievedScript!.title, equals('Updated Title'));
        expect(retrievedScript.metadata['version'], equals('2.0.0'));
      });

      test('should delete script', () async {
        // Arrange
        final testScript = MiniflareScriptRepositoryTestExtensions.createTestScript();
        final savedScriptId = await repository.saveScript(testScript);
        createdScriptIds.add(savedScriptId);

        // Verify it exists
        await repository.expectScriptExists(savedScriptId);

        // Act
        await repository.deleteScript(savedScriptId);
        createdScriptIds.remove(savedScriptId); // Remove from cleanup list

        // Assert
        await repository.expectScriptNotExists(savedScriptId);
      });

      test('should list all scripts', () async {
        // Arrange
        final testScripts = MiniflareScriptRepositoryTestExtensions.createTestScripts(count: 3);
        
        for (final script in testScripts) {
          final savedScriptId = await repository.saveScript(script);
          createdScriptIds.add(savedScriptId);
        }

        // Act
        final allScripts = await repository.getAllScripts();

        // Assert
        expect(allScripts.length, greaterThanOrEqualTo(3));
        // Note: We can't check by original IDs since server generates new ones
        // Instead we check that we have at least the expected number of new scripts
      });
    });

    group('Search and Filtering', () {
      test('should search scripts by title', () async {
        // Arrange
        final searchableScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Unique Searchable Title',
        );
        final savedScriptId = await repository.saveScript(searchableScript);
        createdScriptIds.add(savedScriptId);

        // Act
        final searchResults = await repository.searchScripts('Unique Searchable');

        // Assert
        expect(searchResults.any((s) => s.title.contains('Unique Searchable')), isTrue);
      });

      test('should filter scripts by category', () async {
        // Arrange
        final devScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Dev Script',
          metadata: {
            'description': 'Development script for testing',
            'category': 'Development',
            'authorName': 'Dev Test Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
        );
        final utilScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Util Script',
          metadata: {
            'description': 'Utility script for testing',
            'category': 'Utility',
            'authorName': 'Util Test Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
        );
        
        final devScriptId = await repository.saveScript(devScript);
        final utilScriptId = await repository.saveScript(utilScript);
        createdScriptIds.addAll([devScriptId, utilScriptId]);

        // Wait a moment for scripts to be indexed
        await Future.delayed(Duration(milliseconds: 500));

        // Act - Get all scripts and filter by category
        final allScripts = await repository.getAllScripts();
        final devScripts = allScripts.where((s) => s.metadata['category'] == 'Development').toList();
        final utilScripts = allScripts.where((s) => s.metadata['category'] == 'Utility').toList();

        // Assert
        expect(devScripts.any((s) => s.title.contains('Dev Script')), isTrue);
        expect(utilScripts.any((s) => s.title.contains('Util Script')), isTrue);
      });

      test('should get only public scripts', () async {
        // Arrange
        final publicScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Public Script',
          metadata: {
            'description': 'Public script for testing',
            'category': 'Testing',
            'authorName': 'Public Test Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': true,
          },
        );
        final privateScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Private Script',
          metadata: {
            'description': 'Private script for testing',
            'category': 'Testing',
            'authorName': 'Private Test Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': false,
          },
        );
        
        final publicScriptId = await repository.saveScript(publicScript);
        final privateScriptId = await repository.saveScript(privateScript);
        createdScriptIds.addAll([publicScriptId, privateScriptId]);

        // Act
        final publicScripts = await repository.getPublicScripts();

        // Assert
        expect(publicScripts.any((s) => s.title.contains('Public Script')), isTrue);
        expect(publicScripts.any((s) => s.title.contains('Private Script')), isFalse);
      });
    });

    group('Publishing', () {
      test('should publish script successfully', () async {
        // Arrange
        final privateScript = MiniflareScriptRepositoryTestExtensions.createTestScript(
          title: 'Script to Publish',
          metadata: {
            'description': 'Script to be published',
            'category': 'Testing',
            'authorName': 'Publish Test Author',
            'version': '1.0.0',
            'price': 0.0,
            'isPublic': false,
          },
        );
        final scriptId = await repository.saveScript(privateScript);
        createdScriptIds.add(scriptId);

        // Act
        final scriptToPublish = ScriptRecord(
          id: scriptId,
          title: privateScript.title,
          luaSource: privateScript.luaSource,
          metadata: privateScript.metadata,
          createdAt: privateScript.createdAt,
          updatedAt: DateTime.now(),
        );
        final publishedId = await repository.publishScript(scriptToPublish);

        // Assert
        expect(publishedId, equals(scriptId));
        final publishedScript = await repository.getScriptById(publishedId);
        expect(publishedScript!.metadata['isPublic'], isTrue);
      });
    });

    group('Counting', () {
      test('should get accurate script count', () async {
        // Arrange
        final initialCount = await repository.getScriptsCount();
        final newScript = MiniflareScriptRepositoryTestExtensions.createTestScript();
        final savedScriptId = await repository.saveScript(newScript);
        createdScriptIds.add(savedScriptId);

        // Act
        final finalCount = await repository.getScriptsCount();

        // Assert
        expect(finalCount, greaterThanOrEqualTo(initialCount + 1));
      });
    });

    group('Error Handling', () {
      test('should handle server unavailability gracefully', () async {
        // Arrange - Use a non-existent server with silent fail client
        final offlineRepository = MiniflareTestHelper.createTestRepository(
          baseUrl: 'http://localhost:9999',
          failSilently: true,
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