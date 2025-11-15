import 'package:flutter_test/flutter_test.dart';
import '../test_helpers/unified_authentication_helper.dart';
import '../test_helpers/unified_test_builder.dart';

/// Streamlined authentication tests using unified helpers
/// Eliminates redundancy while maintaining comprehensive coverage
void main() {
  group('Authentication Tests - Unified Approach', () {
    group('Core Operations - Valid Authentication', () {
      for (final scenario in AuthenticationScenario.getValidCases()) {
        group(scenario.description, () {
          test('should create scripts successfully', () async {
            final operation = CreateScriptOperation(
              TestTemplates.scriptForScenario(scenario.description),
            );

            await UnifiedAuthenticationTestHelper.runTestWithScenario(
              scenario: scenario,
              operation: operation,
            );
          });

          test('should update scripts successfully', () async {
            final originalScript = TestTemplates.scriptForScenario(
              'Original ${scenario.description}',
            );
            final operation = CreateAndUpdateOperation(originalScript);

            await UnifiedAuthenticationTestHelper.runTestWithScenario(
              scenario: scenario,
              operation: operation,
            );
          });

          test('should delete scripts successfully', () async {
            final operation = CreateAndDeleteOperation(
              TestTemplates.scriptForScenario('${scenario.description} Delete'),
            );

            await UnifiedAuthenticationTestHelper.runTestWithScenario(
              scenario: scenario,
              operation: operation,
            );
          });
        });
      }
    });

    group('Core Operations - Invalid Authentication', () {
      for (final scenario in AuthenticationScenario.getInvalidCases()) {
        test('should reject script creation with ${scenario.description}', () async {
          final operation = CreateScriptOperation(
            TestTemplates.scriptForScenario('Invalid ${scenario.description}'),
          );

          await UnifiedAuthenticationTestHelper.runTestWithScenario(
            scenario: scenario,
            operation: operation,
          );
        });

        test('should reject script deletion with ${scenario.description}', () async {
          final operation = DeleteScriptOperation('non-existent-id');

          await UnifiedAuthenticationTestHelper.runTestWithScenario(
            scenario: scenario,
            operation: operation,
          );
        });
      }
    });

    group('Fluent Builder Pattern', () {
      test('should handle scripts built with fluent API', () async {
        final script = UnifiedScriptTestBuilder.create()
            .withTitle('Fluent Builder Test')
            .withDescription('Testing fluent builder pattern')
            .withAuthor('Fluent Builder Author')
            .withLuaSource('print("Fluent builder works!")')
            .withMetadata({'category': 'Testing', 'tags': ['fluent', 'builder']})
            .build();

        await UnifiedAuthenticationTestHelper.runBatchTests(
          scenarios: AuthenticationScenario.getValidCases(),
          operationBuilder: (scenario) => CreateScriptOperation(script),
          batchDescription: 'Fluent builder pattern',
        );
      });
    });

    group('Cross-Method Consistency', () {
      test('should produce consistent behavior across all valid authentication methods', () async {
        final results = await UnifiedAuthenticationTestHelper.runConsistencyTest(
          scenarios: AuthenticationScenario.getValidCases(),
          scriptBuilder: (description) => TestTemplates.scriptForScenario(description),
        );

        // Verify all methods succeeded and returned valid script IDs
        expect(results.length, equals(AuthenticationScenario.getValidCases().length));

        for (final result in results) {
          expect(result, AuthenticationMatchers.hasConsistentBehavior());
        }
      });
    });

    group('Edge Cases', () {
      test('should handle Unicode and special characters across all methods', () async {
        final unicodeScript = UnifiedScriptTestBuilder.create().withUnicode().build();

        await UnifiedAuthenticationTestHelper.runBatchTests(
          scenarios: AuthenticationScenario.getValidCases(),
          operationBuilder: (scenario) => CreateScriptOperation(unicodeScript),
          batchDescription: 'Unicode and special characters',
        );
      });

      test('should handle empty and null values gracefully', () async {
        final emptyScript = UnifiedScriptTestBuilder.create().asEmpty().build();

        await UnifiedAuthenticationTestHelper.runTestWithScenario(
          scenario: AuthenticationScenario.validToken,
          operation: CreateScriptOperation(emptyScript),
          operationContext: 'Empty values test',
        );
      });

      test('should handle extremely long content', () async {
        final longContent = 'print("${'A' * 1000}")';
        final longScript = UnifiedScriptTestBuilder.create()
            .withTitle('Long Content Test')
            .withLuaSource(longContent)
            .withDescription('A' * 500)
            .build();

        await UnifiedAuthenticationTestHelper.runTestWithScenario(
          scenario: AuthenticationScenario.validToken,
          operation: CreateScriptOperation(longScript),
          operationContext: 'Long content test',
        );
      });
    });

    group('Repository Factory', () {
      test('should create repositories for all valid methods consistently', () async {
        final repositories = TestRepositoryFactory.createForAllValidScenarios();
        final script = TestTemplates.basicScript();

        for (final repository in repositories) {
          try {
            await expectLater(
              repository.saveScript(script),
              AuthenticationMatchers.succeedsWithMessage('Repository factory test'),
            );
          } finally {
            repository.dispose();
          }
        }
      });
    });

    group('Performance', () {
      test('should handle concurrent operations efficiently', () async {
        await UnifiedAuthenticationTestHelper.runPerformanceTest(
          scenarios: AuthenticationScenario.getValidCases(),
          concurrency: 3,
          scriptBuilder: (index) => UnifiedScriptTestBuilder.create()
              .withTitle('Concurrent Test Script $index')
              .withDescription('Testing concurrent operations')
              .withAuthor('Concurrent Test Author $index')
              .build(),
        );
      });
    });
  });
}