import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'test_signature_utils.dart';

/// Signature utilities helper that provides access to signature methods
class SignatureUtils {
  static String getPrincipal() => TestSignatureUtils.getPrincipal();
  static String getPublicKey() => TestSignatureUtils.getPublicKey();
  static String generateTestSignature(Map<String, dynamic> payload) =>
      TestSignatureUtils.generateTestSignature(payload);
}

/// Unified test builder that consolidates ScriptTestBuilder and ScriptTestData functionality
/// Provides fluent interface for creating test scripts with proper signatures
class UnifiedScriptTestBuilder {
  String? _id;
  String? _title;
  String? _luaSource;
  String? _description;
  String? _category;
  String? _authorName;
  final Map<String, dynamic> _metadata = {};
  DateTime? _createdAt;
  DateTime? _updatedAt;

  UnifiedScriptTestBuilder();

  UnifiedScriptTestBuilder withId(String id) {
    _id = id;
    return this;
  }

  UnifiedScriptTestBuilder withTitle(String title) {
    _title = title;
    return this;
  }

  UnifiedScriptTestBuilder withLuaSource(String luaSource) {
    _luaSource = luaSource;
    return this;
  }

  UnifiedScriptTestBuilder withDescription(String description) {
    _description = description;
    return this;
  }

  UnifiedScriptTestBuilder withCategory(String category) {
    _category = category;
    return this;
  }

  UnifiedScriptTestBuilder withAuthor(String authorName) {
    _authorName = authorName;
    return this;
  }

  UnifiedScriptTestBuilder withMetadata(Map<String, dynamic> metadata) {
    _metadata.addAll(metadata);
    return this;
  }

  UnifiedScriptTestBuilder withTimestamps({DateTime? createdAt, DateTime? updatedAt}) {
    _createdAt = createdAt;
    _updatedAt = updatedAt;
    return this;
  }

  UnifiedScriptTestBuilder asEmpty() {
    return withTitle('')
        .withLuaSource('')
        .withDescription('')
        .withCategory('')
        .withAuthor('')
        .withMetadata({'tags': [], 'version': ''});
  }

  UnifiedScriptTestBuilder withSpecialChars() {
    return withTitle('Special Chars Test 🚀')
        .withLuaSource('print("Special chars: 🦄✨")\n-- Unicode: ñáéíóú\n-- Quotes: "test" and \'single\'')
        .withDescription('Testing special characters with signatures: ñoño 🎉')
        .withAuthor('Special Chars Author 🧪')
        .withMetadata({'tags': ['unicode', 'testing', 'español', '🎯']});
  }

  UnifiedScriptTestBuilder withUnicode() {
    return withTitle('Título con Acentos Ñoño 🚀')
        .withDescription('Descripción con caracteres especiales: café, naïve, 北京')
        .withAuthor('Autor Especial Ñ')
        .withMetadata({
          'tags': ['español', '中文', 'français', '🎯'],
          'category': 'Pruebas Especiales',
        });
  }

  /// Create a copy of this builder with updated fields for script updates
  UnifiedScriptTestBuilder forUpdate(ScriptRecord original) {
    _id = original.id;
    _title = 'Updated ${original.title}';
    _luaSource = 'print("Updated: ${original.luaSource}")';
    _createdAt = original.createdAt;
    _updatedAt = DateTime.now();
    _metadata.clear();
    _metadata.addAll(original.metadata);
    _description = 'Updated: ${original.metadata['description']}';
    return this;
  }

  /// Build the final ScriptRecord with proper signature
  ScriptRecord build() {
    final now = DateTime.now();
    final timestamp = _createdAt?.toIso8601String() ?? now.toIso8601String();

    // Create signature payload
    final signaturePayload = {
      'action': 'upload',
      'title': _title ?? 'Test Script',
      'description': _description ?? 'Test script description',
      'category': _category ?? 'Testing',
      'lua_source': _luaSource ?? 'print("Test script")',
      'version': _metadata['version'] ?? '1.0.0',
      'tags': _metadata['tags'] ?? [],
      'author_principal': SignatureUtils.getPrincipal(),
      'timestamp': timestamp,
    };

    final signature = SignatureUtils.generateTestSignature(signaturePayload);

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
        'authorPrincipal': SignatureUtils.getPrincipal(),
        'authorPublicKey': SignatureUtils.getPublicKey(),
        'signature': signature,
        'timestamp': timestamp,
        ..._metadata,
      },
    );
  }

  static UnifiedScriptTestBuilder create() => UnifiedScriptTestBuilder();
}

/// Predefined test templates for common scenarios
class TestTemplates {
  static ScriptRecord basicScript() {
    return UnifiedScriptTestBuilder.create().build();
  }

  static ScriptRecord scriptForScenario(String scenario) {
    return UnifiedScriptTestBuilder.create()
        .withTitle('$scenario Test Script')
        .withDescription('Testing $scenario functionality')
        .withAuthor('$scenario Test Author')
        .build();
  }

  static ScriptRecord updateScriptForScenario(String scenario, ScriptRecord original) {
    return UnifiedScriptTestBuilder.create()
        .forUpdate(original)
        .withTitle('Updated $scenario Script')
        .build();
  }

  static List<ScriptRecord> edgeCaseScripts() {
    return [
      UnifiedScriptTestBuilder.create().asEmpty().build(),
      UnifiedScriptTestBuilder.create().withSpecialChars().build(),
      UnifiedScriptTestBuilder.create().withUnicode().build(),
    ];
  }

  /// Create a script with proper signature for API testing
  static ScriptRecord createTestScriptWithSignature({
    required String id,
    required String title,
    String description = 'Test script',
    String category = 'Development',
    List<String> tags = const ['test'],
    String authorName = 'Test Author',
    String luaSource = 'function init() return {}, {} end',
  }) {
    return UnifiedScriptTestBuilder.create()
        .withId(id)
        .withTitle(title)
        .withDescription(description)
        .withCategory(category)
        .withAuthor(authorName)
        .withLuaSource(luaSource)
        .withMetadata({
          'tags': tags,
          'version': '1.0.0',
          'price': 0.0,
          'isPublic': true,
        })
        .build();
  }

  /// Create update request data with proper signature
  static Map<String, dynamic> createTestUpdateRequest(String scriptId, {Map<String, dynamic>? updates}) {
    final timestamp = DateTime.now().toIso8601String();
    final signaturePayload = {
      'action': 'update',
      'script_id': scriptId,
      'timestamp': timestamp,
      ...?updates,
    };

    final signature = SignatureUtils.generateTestSignature(signaturePayload);

    return {
      'signature': signature,
      'timestamp': timestamp,
      'author_principal': SignatureUtils.getPrincipal(),
      'author_public_key': SignatureUtils.getPublicKey(),
      ...?updates,
    };
  }
}