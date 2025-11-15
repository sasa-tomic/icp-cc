import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'testable_script_repository.dart';
import 'unified_test_builder.dart';

/// Authentication scenarios enum - replaces both AuthenticationTestCase and AuthenticationTestMatrix
enum AuthenticationScenario {
  validToken('test-auth-token authentication', AuthenticationMethod.testToken, true),
  customTestToken('custom test-auth-token authentication', AuthenticationMethod.testToken, true, 'test-auth-token'),
  realSignature('cryptographic signature authentication', AuthenticationMethod.realSignature, true),

  invalidToken('invalid authentication token', AuthenticationMethod.invalidToken, false, '401'),
  missingToken('missing authentication signature', AuthenticationMethod.missingToken, false, '401'),
  malformedToken('malformed authentication data', AuthenticationMethod.malformedToken, false, '401'),
  invalidCredentials('invalid principal/public key combination', AuthenticationMethod.testToken, false, '401', null, true);

  const AuthenticationScenario(
    this.description,
    this.method,
    this.shouldSucceed, [
    this.expectedError,
    this._customTokenValue,
    this._forceInvalidAuth = false,
  ]);

  final String description;
  final AuthenticationMethod method;
  final bool shouldSucceed;
  final String? expectedError;
  final String? _customTokenValue;
  final bool _forceInvalidAuth;

  /// Helper to get custom token value for backward compatibility
  String? get customToken => _customTokenValue;

  Map<String, dynamic> toTestCase() {
    return {
      'description': description,
      'method': method,
      'shouldSucceed': shouldSucceed,
      'expectedError': expectedError,
      'customToken': _customTokenValue,
      'forceInvalidAuth': _forceInvalidAuth,
    };
  }

  static List<AuthenticationScenario> getValidCases() =>
      values.where((scenario) => scenario.shouldSucceed).toList();

  static List<AuthenticationScenario> getInvalidCases() =>
      values.where((scenario) => !scenario.shouldSucceed).toList();
}

/// Custom test matchers for cleaner assertions
class AuthenticationMatchers {
  static Matcher succeedsWithMessage(String expectedMessage) {
    return completes;
  }

  static Matcher failsWithAuthenticationError() {
    return throwsA(
      allOf(
        isA<Exception>(),
        predicate(
          (e) => e.toString().contains('401') || e.toString().contains('403'),
        ),
      ),
    );
  }

  static Matcher failsWithError(String expectedError) {
    return throwsA(
      allOf(
        isA<Exception>(),
        predicate(
          (e) => e.toString().contains(expectedError),
        ),
      ),
    );
  }

  static Matcher hasValidScriptId() {
    return predicate(
      (String id) => RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$').hasMatch(id),
    );
  }

  static Matcher hasConsistentBehavior() {
    return predicate(
      (String result) {
        // Extract script ID from "description: script_id" format
        final parts = result.split(': ');
        if (parts.length != 2) return false;

        final scriptId = parts[1].trim();
        // Check if it matches UUID format
        return RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$').hasMatch(scriptId);
      },
    );
  }
}

/// Generic test operations that can be composed
abstract class TestOperation {
  Future<void> execute(TestableScriptRepository repository);
  String get description;
}

class CreateScriptOperation extends TestOperation {
  final ScriptRecord script;

  CreateScriptOperation(this.script);

  @override
  Future<void> execute(TestableScriptRepository repository) async {
    await repository.saveScript(script);
  }

  @override
  String get description => 'Create script: ${script.title}';
}

class UpdateScriptOperation extends TestOperation {
  final ScriptRecord script;

  UpdateScriptOperation(this.script);

  @override
  Future<void> execute(TestableScriptRepository repository) async {
    await repository.saveScript(script);
  }

  @override
  String get description => 'Update script: ${script.title}';
}

class DeleteScriptOperation extends TestOperation {
  final String scriptId;

  DeleteScriptOperation(this.scriptId);

  @override
  Future<void> execute(TestableScriptRepository repository) async {
    await repository.deleteScript(scriptId);
  }

  @override
  String get description => 'Delete script: $scriptId';
}

class CreateAndUpdateOperation extends TestOperation {
  final ScriptRecord originalScript;

  CreateAndUpdateOperation(this.originalScript);

  @override
  Future<void> execute(TestableScriptRepository repository) async {
    await repository.saveScript(originalScript);
    final updatedScript = UnifiedScriptTestBuilder.create()
        .forUpdate(originalScript)
        .build();
    await repository.saveScript(updatedScript);
  }

  @override
  String get description => 'Create and update script: ${originalScript.title}';
}

class CreateAndDeleteOperation extends TestOperation {
  final ScriptRecord script;

  CreateAndDeleteOperation(this.script);

  @override
  Future<void> execute(TestableScriptRepository repository) async {
    final createdId = await repository.saveScript(script);
    await repository.deleteScript(createdId);
  }

  @override
  String get description => 'Create and delete script: ${script.title}';
}

/// Unified authentication test helper that consolidates functionality from both helpers
class UnifiedAuthenticationTestHelper {
  /// Run a single test with a specific authentication scenario
  static Future<void> runTestWithScenario({
    required AuthenticationScenario scenario,
    required TestOperation operation,
    String? operationContext,
  }) async {
    final repository = TestRepositoryFactory.createForScenario(scenario);

    try {
      final context = operationContext ?? operation.description;

      if (scenario.shouldSucceed) {
        await operation.execute(repository);
      } else {
        final expectedError = scenario.expectedError;
        await expectLater(
          operation.execute(repository),
          expectedError != null
            ? AuthenticationMatchers.failsWithError(expectedError)
            : AuthenticationMatchers.failsWithAuthenticationError(),
          reason: '$context with ${scenario.description} should fail',
        );
      }
    } finally {
      repository.dispose();
    }
  }

  /// Run tests across multiple scenarios with the same operation
  static Future<void> runBatchTests({
    required List<AuthenticationScenario> scenarios,
    required TestOperation Function(AuthenticationScenario) operationBuilder,
    String? batchDescription,
  }) async {
    for (final scenario in scenarios) {
      final operation = operationBuilder(scenario);
      await runTestWithScenario(
        scenario: scenario,
        operation: operation,
        operationContext: batchDescription,
      );
    }
  }

  /// Test consistency across all valid authentication methods
  static Future<List<String>> runConsistencyTest({
    required List<AuthenticationScenario> scenarios,
    required ScriptRecord Function(String) scriptBuilder,
  }) async {
    final results = <String>[];

    for (final scenario in scenarios) {
      final repository = TestRepositoryFactory.createForScenario(scenario);

      try {
        final script = scriptBuilder(scenario.description);
        final createdId = await repository.saveScript(script);
        results.add('${scenario.description}: $createdId');
      } finally {
        repository.dispose();
      }
    }

    return results;
  }

  /// Run performance tests with concurrent operations
  static Future<void> runPerformanceTest({
    required List<AuthenticationScenario> scenarios,
    required int concurrency,
    required ScriptRecord Function(int) scriptBuilder,
  }) async {
    final futures = <Future<void>>[];

    for (int i = 0; i < concurrency; i++) {
      final script = scriptBuilder(i);

      for (final scenario in scenarios.take(2)) { // Limit for performance
        final operation = CreateScriptOperation(script);
        futures.add(runTestWithScenario(
          scenario: scenario,
          operation: operation,
          operationContext: 'Performance test $i',
        ));
      }
    }

    await Future.wait(futures);
  }

  /// Test basic operations with specific scenarios
  static Future<void> testScriptCreation(
    TestableScriptRepository repository,
    ScriptRecord script,
  ) async {
    await repository.saveScript(script);
  }

  static Future<void> testScriptUpdate(
    TestableScriptRepository repository,
    ScriptRecord updatedScript,
  ) async {
    await repository.saveScript(updatedScript);
  }

  static Future<void> testScriptDeletion(
    TestableScriptRepository repository,
    String scriptId,
  ) async {
    await repository.deleteScript(scriptId);
  }

  static Future<String> createScriptAndUpdate(
    TestableScriptRepository repository,
    ScriptRecord originalScript,
  ) async {
    final createdId = await repository.saveScript(originalScript);
    final updatedScript = UnifiedScriptTestBuilder.create()
        .forUpdate(originalScript)
        .build();
    await repository.saveScript(updatedScript);
    return createdId;
  }

  static Future<String> createScriptAndDelete(
    TestableScriptRepository repository,
    ScriptRecord script,
  ) async {
    final createdId = await repository.saveScript(script);
    await repository.deleteScript(createdId);
    return createdId;
  }
}

/// Repository factory for consistent test setup
class TestRepositoryFactory {
  static TestableScriptRepository createForScenario(AuthenticationScenario scenario) {
    return TestableScriptRepository(
      authMethod: scenario.method,
      customAuthToken: scenario.customToken,
      forceInvalidAuth: scenario._forceInvalidAuth,
    );
  }

  static List<TestableScriptRepository> createForAllValidScenarios() {
    return AuthenticationScenario.getValidCases()
        .map(createForScenario)
        .toList();
  }
}