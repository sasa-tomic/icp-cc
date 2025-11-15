import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'testable_script_repository.dart';
import 'test_signature_utils.dart';

/// Test data builders for authentication tests
class ScriptTestData {
  static ScriptRecord createTestScript({
    String? id,
    String? title,
    String? luaSource,
    String? description,
    String? category,
    String? authorName,
    Map<String, dynamic>? additionalMetadata,
  }) {
    final now = DateTime.now();
    return ScriptRecord(
      id: id ?? 'test-script-${DateTime.now().millisecondsSinceEpoch}',
      title: title ?? 'Test Script',
      luaSource: luaSource ?? 'print("Test script")',
      createdAt: now,
      updatedAt: now,
      metadata: {
        'description': description ?? 'Test script description',
        'category': category ?? 'Testing',
        'authorName': authorName ?? 'Test Author',
        'authorPrincipal': TestSignatureUtils.getPrincipal(),
        'authorPublicKey': TestSignatureUtils.getPublicKey(),
        ...?additionalMetadata,
      },
    );
  }

  static ScriptRecord createSpecialCharsScript() {
    return createTestScript(
      title: 'Special Chars Test 🚀',
      luaSource: 'print("Special chars: 🦄✨")\n-- Unicode: ñáéíóú\n-- Quotes: "test" and \'single\'',
      description: 'Testing special characters with signatures: ñoño 🎉',
      authorName: 'Special Chars Author 🧪',
      additionalMetadata: {
        'tags': ['unicode', 'testing', 'español', '🎯'],
      },
    );
  }

  static ScriptRecord createEmptyFieldsScript() {
    final now = DateTime.now();
    return ScriptRecord(
      id: 'empty-fields-${DateTime.now().millisecondsSinceEpoch}',
      title: '',
      luaSource: '',
      createdAt: now,
      updatedAt: now,
      metadata: {
        'description': '',
        'category': '',
        'authorName': '',
        'authorPrincipal': TestSignatureUtils.getPrincipal(),
        'authorPublicKey': TestSignatureUtils.getPublicKey(),
        'tags': [],
        'version': '',
      },
    );
  }

  static ScriptRecord createUpdatedScript(String originalId, DateTime originalCreatedAt) {
    return ScriptRecord(
      id: originalId,
      title: 'Updated Title',
      luaSource: 'print("Updated")',
      createdAt: originalCreatedAt,
      updatedAt: DateTime.now(),
      metadata: {
        'description': 'Updated description',
        'category': 'Testing',
        'authorName': 'Update Test Author',
        'authorPrincipal': TestSignatureUtils.getPrincipal(),
        'authorPublicKey': TestSignatureUtils.getPublicKey(),
      },
    );
  }
}

/// Authentication test helper methods
class AuthenticationTestHelper {
  static Future<void> testSuccessfulOperation({
    required AuthenticationMethod authMethod,
    required String operationName,
    required Future<void> Function(TestableScriptRepository) operation,
    String? customAuthToken,
  }) async {
    final repository = TestableScriptRepository(
      authMethod: authMethod,
      customAuthToken: customAuthToken,
    );

    try {
      await expectLater(
        () => operation(repository),
        returnsNormally,
        reason: '$operationName should succeed with $authMethod',
      );
    } finally {
      repository.dispose();
    }
  }

  static Future<void> testFailedAuthentication({
    required AuthenticationMethod authMethod,
    required String operationName,
    required Future<void> Function(TestableScriptRepository) operation,
    String expectedErrorPattern = '401',
  }) async {
    final repository = TestableScriptRepository(authMethod: authMethod);

    try {
      await expectLater(
        () => operation(repository),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          anyOf([
            contains(expectedErrorPattern),
            contains('401'), // Unauthorized
            contains('403'), // Forbidden
          ]),
        )),
        reason: '$operationName should fail with $authMethod',
      );
    } finally {
      repository.dispose();
    }
  }

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
    final updatedScript = ScriptTestData.createUpdatedScript(
      createdId,
      originalScript.createdAt,
    );
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

/// Test case parameter objects for cleaner test organization
class AuthenticationTestCase {
  final String name;
  final AuthenticationMethod method;
  final String? customToken;
  final bool shouldSucceed;
  final String? expectedError;

  const AuthenticationTestCase({
    required this.name,
    required this.method,
    this.customToken,
    this.shouldSucceed = true,
    this.expectedError,
  });
}

class AuthenticationTestCases {
  static const List<AuthenticationTestCase> validCases = [
    AuthenticationTestCase(
      name: 'test-auth-token',
      method: AuthenticationMethod.testToken,
    ),
    AuthenticationTestCase(
      name: 'custom test-auth-token',
      method: AuthenticationMethod.testToken,
      customToken: 'test-auth-token',
    ),
    AuthenticationTestCase(
      name: 'real cryptographic signature',
      method: AuthenticationMethod.realSignature,
    ),
  ];

  static const List<AuthenticationTestCase> invalidCases = [
    AuthenticationTestCase(
      name: 'invalid token',
      method: AuthenticationMethod.invalidToken,
      shouldSucceed: false,
      expectedError: '401',
    ),
    AuthenticationTestCase(
      name: 'missing authentication',
      method: AuthenticationMethod.missingToken,
      shouldSucceed: false,
      expectedError: '401',
    ),
    AuthenticationTestCase(
      name: 'malformed authentication',
      method: AuthenticationMethod.malformedToken,
      shouldSucceed: false,
      expectedError: '401',
    ),
    AuthenticationTestCase(
      name: 'invalid credentials',
      method: AuthenticationMethod.testToken,
      shouldSucceed: false,
      expectedError: '401',
    ),
  ];
}