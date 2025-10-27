import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../rust/native_bridge.dart';

class ValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final int lineCount;
  final int characterCount;

  ValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    required this.lineCount,
    required this.characterCount,
  });

  factory ValidationResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return ValidationResult(
      isValid: data['is_valid'] as bool? ?? false,
      errors: (data['errors'] as List<dynamic>?)?.cast<String>() ?? [],
      warnings: (data['warnings'] as List<dynamic>?)?.cast<String>() ?? [],
      lineCount: data['line_count'] as int? ?? 0,
      characterCount: data['character_count'] as int? ?? 0,
    );
  }

  factory ValidationResult.fromRustJson(Map<String, dynamic> json) {
    return ValidationResult(
      isValid: json['is_valid'] as bool? ?? false,
      errors: (json['syntax_errors'] as List<dynamic>?)?.cast<String>() ?? [],
      warnings: (json['warnings'] as List<dynamic>?)?.cast<String>() ?? [],
      lineCount: json['line_count'] as int? ?? 0,
      characterCount: json['character_count'] as int? ?? 0,
    );
  }
}

class ScriptValidationService {
  static final ScriptValidationService _instance = ScriptValidationService._internal();
  factory ScriptValidationService() => _instance;
  ScriptValidationService._internal();

  String get _baseUrl => '${AppConfig.apiEndpoint}/api/v1';
  final Duration _timeout = const Duration(seconds: 10);

  Future<ValidationResult> validateScript(String luaSource) async {
    // Try Rust validation first (more accurate and faster)
    try {
      final rustResult = await _validateWithRust(luaSource);
      if (rustResult != null) {
        return rustResult;
      }
    } catch (e) {
      // Fall back to server validation if Rust fails
      print('Rust validation failed, falling back to server: $e');
    }

    // Fallback to server validation (TypeScript)
    return await _validateWithServer(luaSource);
  }

  Future<ValidationResult?> _validateWithRust(String luaSource) async {
    try {
      // Determine context
      final isExample = luaSource.contains(RegExp(r'--\s*(example|demo|tutorial|sample)', caseSensitive: false));
      final isTest = luaSource.contains(RegExp(r'--\s*(test|spec|unit)', caseSensitive: false));
      final isProduction = !isExample && !isTest;

      // Call Rust validation via FFI
      final rustBridge = NativeBridge();
      final resultJson = rustBridge.validateLuaComprehensive(
        script: luaSource,
        isExample: isExample,
        isTest: isTest,
        isProduction: isProduction,
      );

      if (resultJson.isNotEmpty) {
        final Map<String, dynamic> jsonResult = json.decode(resultJson) as Map<String, dynamic>;
        return ValidationResult.fromRustJson(jsonResult);
      }
    } catch (e) {
      // Return null to trigger fallback
      return null;
    }
    return null;
  }

  Future<ValidationResult> _validateWithServer(String luaSource) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/scripts/validate'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'lua_source': luaSource,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body) as Map<String, dynamic>;
        return ValidationResult.fromJson(jsonResponse);
      } else {
        // Return error result for non-200 responses
        return ValidationResult(
          isValid: false,
          errors: ['Server error: ${response.statusCode}'],
          warnings: [],
          lineCount: 0,
          characterCount: 0,
        );
      }
    } catch (e) {
      // Return error result for exceptions
      return ValidationResult(
        isValid: false,
        errors: ['Validation failed: ${e.toString()}'],
        warnings: [],
        lineCount: 0,
        characterCount: 0,
      );
    }
  }

  // Quick validation for common issues without server call
  ValidationResult quickValidate(String luaSource) {
    final errors = <String>[];
    final warnings = <String>[];

    // Basic checks
    if (luaSource.trim().isEmpty) {
      errors.add('Script is empty');
    }

    // Check for required functions
    final requiredFunctions = ['init', 'view', 'update'];
    for (final func in requiredFunctions) {
      if (!luaSource.contains('function $func')) {
        errors.add('Required function \'$func\' not found');
      }
    }

    // Check for common security issues
    if (luaSource.contains('loadstring(')) {
      errors.add('loadstring() function detected - potential security risk');
    }

    if (luaSource.contains('dofile(')) {
      errors.add('dofile() function detected - potential security risk');
    }

    // Check for potential infinite loops
    if (luaSource.contains('while true do') && 
        !luaSource.contains('break') && 
        !luaSource.contains('return')) {
      warnings.add('Potential infinite loop detected - while true loop without break or return');
    }

    final lines = luaSource.split('\n');
    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      lineCount: lines.length,
      characterCount: luaSource.length,
    );
  }
}