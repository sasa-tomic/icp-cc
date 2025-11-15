import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  
  Future<ValidationResult> validateScript(String luaSource) async {
    // Use Rust validation only (mlua)
    try {
      final rustResult = await _validateWithRust(luaSource);
      if (rustResult != null) {
        return rustResult;
      }
    } catch (e) {
      debugPrint('Rust validation failed: $e');
      // Return error result if Rust validation fails
      return ValidationResult(
        isValid: false,
        errors: ['Validation failed: ${e.toString()}'],
        warnings: [],
        lineCount: luaSource.split('\n').length,
        characterCount: luaSource.length,
      );
    }

    // Should not reach here, but return basic validation as safety net
    return quickValidate(luaSource);
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