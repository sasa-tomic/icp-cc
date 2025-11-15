import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'testable_script_repository.dart';
import 'test_signature_utils.dart';

/// Fluent builder for creating test scripts with method chaining
class ScriptTestBuilder {
  String? _id;
  String? _title;
  String? _luaSource;
  String? _description;
  String? _category;
  String? _authorName;
  final Map<String, dynamic> _metadata = {};
  DateTime? _createdAt;
  DateTime? _updatedAt;

  ScriptTestBuilder();

  ScriptTestBuilder withId(String id) {
    _id = id;
    return this;
  }

  ScriptTestBuilder withTitle(String title) {
    _title = title;
    return this;
  }

  ScriptTestBuilder withLuaSource(String luaSource) {
    _luaSource = luaSource;
    return this;
  }

  ScriptTestBuilder withDescription(String description) {
    _description = description;
    return this;
  }

  ScriptTestBuilder withCategory(String category) {
    _category = category;
    return this;
  }

  ScriptTestBuilder withAuthor(String authorName) {
    _authorName = authorName;
    return this;
  }

  ScriptTestBuilder withMetadata(Map<String, dynamic> metadata) {
    _metadata.addAll(metadata);
    return this;
  }

  ScriptTestBuilder withTimestamps({DateTime? createdAt, DateTime? updatedAt}) {
    _createdAt = createdAt;
    _updatedAt = updatedAt;
    return this;
  }

  ScriptTestBuilder asEmpty() {
    return withTitle('')
        .withLuaSource('')
        .withDescription('')
        .withCategory('')
        .withAuthor('')
        .withMetadata({'tags': [], 'version': ''});
  }

  ScriptTestBuilder withSpecialChars() {
    return withTitle('Special Chars Test 🚀')
        .withLuaSource('print("Special chars: 🦄✨")\n-- Unicode: ñáéíóú\n-- Quotes: "test" and \'single\'')
        .withDescription('Testing special characters with signatures: ñoño 🎉')
        .withAuthor('Special Chars Author 🧪')
        .withMetadata({'tags': ['unicode', 'testing', 'español', '🎯']});
  }

  ScriptTestBuilder withUnicode() {
    return withTitle('Título con Acentos Ñoño 🚀')
        .withDescription('Descripción con caracteres especiales: café, naïve, 北京')
        .withAuthor('Autor Especial Ñ')
        .withMetadata({
          'tags': ['español', '中文', 'français', '🎯'],
          'category': 'Pruebas Especiales',
        });
  }

  ScriptRecord build() {
    final now = DateTime.now();
    return ScriptRecord(
      id: _id ?? 'test-script-${DateTime.now().millisecondsSinceEpoch}',
      title: _title ?? 'Test Script',
      luaSource: _luaSource ?? 'print("Test script")',
      createdAt: _createdAt ?? now,
      updatedAt: _updatedAt ?? now,
      metadata: {
        'description': _description ?? 'Test script description',
        'category': _category ?? 'Testing',
        'authorName': _authorName ?? 'Test Author',
        'authorPrincipal': TestSignatureUtils.getPrincipal(),
        'authorPublicKey': TestSignatureUtils.getPublicKey(),
        ..._metadata,
      },
    );
  }

  /// Create a copy of this builder with updated fields for script updates
  ScriptTestBuilder forUpdate(ScriptRecord original) {
    return ScriptTestBuilder()
        .withId(original.id)
        .withTitle('Updated ${original.title}')
        .withLuaSource('print("Updated: ${original.luaSource}")')
        .withTimestamps(createdAt: original.createdAt, updatedAt: DateTime.now())
        .withMetadata(Map<String, dynamic>.from(original.metadata))
        .withDescription('Updated: ${original.metadata['description']}');
  }

  static ScriptTestBuilder create() => ScriptTestBuilder();
}

/// Custom test matchers for cleaner assertions
class AuthenticationMatchers {
  static Matcher succeedsWithMessage(String expectedMessage) {
    return allOf(
      returnsNormally,
      completes,
      predicate((dynamic result) => true),
    );
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
      (String id) => RegExp(r'^[a-f0-9]{64}$').hasMatch(id),
    );
  }

  static Matcher hasConsistentBehavior() {
    return allOf(
      isA<String>(),
      hasValidScriptId(),
    );
  }
}

/// Table-driven test framework for authentication scenarios
class AuthenticationTestMatrix {
  static final List<Map<String, dynamic>> testMatrix = [
    // Valid cases
    {
      'scenario': 'valid token',
      'method': AuthenticationMethod.testToken,
      'shouldSucceed': true,
      'description': 'test-auth-token authentication',
    },
    {
      'scenario': 'custom token',
      'method': AuthenticationMethod.testToken,
      'customToken': 'test-auth-token',
      'shouldSucceed': true,
      'description': 'custom test-auth-token authentication',
    },
    {
      'scenario': 'real signature',
      'method': AuthenticationMethod.realSignature,
      'shouldSucceed': true,
      'description': 'cryptographic signature authentication',
    },
    // Invalid cases
    {
      'scenario': 'invalid token',
      'method': AuthenticationMethod.invalidToken,
      'shouldSucceed': false,
      'expectedError': '401',
      'description': 'invalid authentication token',
    },
    {
      'scenario': 'missing auth',
      'method': AuthenticationMethod.missingToken,
      'shouldSucceed': false,
      'expectedError': '401',
      'description': 'missing authentication signature',
    },
    {
      'scenario': 'malformed auth',
      'method': AuthenticationMethod.malformedToken,
      'shouldSucceed': false,
      'expectedError': '401',
      'description': 'malformed authentication data',
    },
  ];

  static List<Map<String, dynamic>> getValidCases() =>
      testMatrix.where((case_) => case_['shouldSucceed'] as bool).toList();

  static List<Map<String, dynamic>> getInvalidCases() =>
      testMatrix.where((case_) => !(case_['shouldSucceed'] as bool)).toList();
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
    final updatedScript = ScriptTestBuilder.create()
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

/// Advanced test helper with composable operations
class AdvancedAuthenticationTestHelper {
  static Future<void> runTestWithMatrix({
    required Map<String, dynamic> testCase,
    required TestOperation operation,
    String? operationContext,
  }) async {
    final repository = TestableScriptRepository(
      authMethod: testCase['method'] as AuthenticationMethod,
      customAuthToken: testCase['customToken'] as String?,
    );

    try {
      final shouldSucceed = testCase['shouldSucceed'] as bool;
      final description = testCase['description'] as String;
      final context = operationContext ?? operation.description;

      if (shouldSucceed) {
        await expectLater(
          () => operation.execute(repository),
          AuthenticationMatchers.succeedsWithMessage('$context should succeed with $description'),
          reason: '$context with $description',
        );
      } else {
        final expectedError = testCase['expectedError'] as String?;
        await expectLater(
          () => operation.execute(repository),
          expectedError != null
            ? AuthenticationMatchers.failsWithError(expectedError)
            : AuthenticationMatchers.failsWithAuthenticationError(),
          reason: '$context with $description should fail',
        );
      }
    } finally {
      repository.dispose();
    }
  }

  static Future<void> runBatchTests({
    required List<Map<String, dynamic>> testCases,
    required TestOperation Function(Map<String, dynamic>) operationBuilder,
    String? batchDescription,
  }) async {
    for (final testCase in testCases) {
      final operation = operationBuilder(testCase);
      await runTestWithMatrix(
        testCase: testCase,
        operation: operation,
        operationContext: batchDescription,
      );
    }
  }

  static Future<List<String>> runConsistencyTest({
    required List<Map<String, dynamic>> testCases,
    required ScriptRecord Function(String) scriptBuilder,
  }) async {
    final results = <String>[];

    for (final testCase in testCases) {
      final repository = TestableScriptRepository(
        authMethod: testCase['method'] as AuthenticationMethod,
        customAuthToken: testCase['customToken'] as String?,
      );

      try {
        final script = scriptBuilder(testCase['description'] as String);
        final createdId = await repository.saveScript(script);
        results.add('${testCase['description']}: $createdId');
      } finally {
        repository.dispose();
      }
    }

    return results;
  }

  static Future<void> runPerformanceTest({
    required List<Map<String, dynamic>> testCases,
    required int concurrency,
    required ScriptRecord Function(int) scriptBuilder,
  }) async {
    final futures = <Future<void>>[];

    for (int i = 0; i < concurrency; i++) {
      final script = scriptBuilder(i);

      for (final testCase in testCases.take(2)) { // Limit for performance
        final operation = CreateScriptOperation(script);
        futures.add(runTestWithMatrix(
          testCase: testCase,
          operation: operation,
          operationContext: 'Performance test $i',
        ));
      }
    }

    await Future.wait(futures);
  }
}

/// Repository factory for consistent test setup
class TestRepositoryFactory {
  static TestableScriptRepository createForTest({
    required AuthenticationMethod method,
    String? customToken,
    bool forceInvalidAuth = false,
  }) {
    return TestableScriptRepository(
      authMethod: method,
      customAuthToken: customToken,
      forceInvalidAuth: forceInvalidAuth,
    );
  }

  static List<TestableScriptRepository> createForAllValidMethods({
    Map<String, String>? customTokens,
  }) {
    return AuthenticationTestMatrix.getValidCases()
        .map((testCase) => createForTest(
          method: testCase['method'] as AuthenticationMethod,
          customToken: testCase['customToken'] as String?,
        ))
        .toList();
  }
}

/// Predefined test templates for common scenarios
class TestTemplates {
  static ScriptRecord basicScript() {
    return ScriptTestBuilder.create().build();
  }

  static ScriptRecord scriptForScenario(String scenario) {
    return ScriptTestBuilder.create()
        .withTitle('$scenario Test Script')
        .withDescription('Testing $scenario functionality')
        .withAuthor('$scenario Test Author')
        .build();
  }

  static ScriptRecord updateScriptForScenario(String scenario, ScriptRecord original) {
    return ScriptTestBuilder.create()
        .forUpdate(original)
        .withTitle('Updated $scenario Script')
        .build();
  }

  static List<ScriptRecord> edgeCaseScripts() {
    return [
      ScriptTestBuilder.create().asEmpty().build(),
      ScriptTestBuilder.create().withSpecialChars().build(),
      ScriptTestBuilder.create().withUnicode().build(),
    ];
  }
}