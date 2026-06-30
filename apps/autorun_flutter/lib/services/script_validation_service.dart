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

/// Validates TypeScript/QuickJS script bundles through the authoritative Rust
/// validator (rquickjs-based) over FFI.
///
/// Previously this class hosted a Lua-regex `quickValidate` heuristic that ran
/// as a fallback when the Rust bridge was unavailable. Per cleanup-plan TD-8,
/// that heuristic is removed: the Rust validator is authoritative and the
/// previous fallback used wrong-language rules. When FFI is unavailable we now
/// surface a clear error rather than silently returning stale heuristics.
class ScriptValidationService {
  static final ScriptValidationService _instance = ScriptValidationService._internal();
  factory ScriptValidationService() => _instance;
  ScriptValidationService._internal();

  Future<ValidationResult> validateScript(String source) async {
    // Use Rust validation (rquickjs)
    try {
      final rustResult = await _validateWithRust(source);
      if (rustResult != null) {
        return rustResult;
      }
    } catch (e) {
      debugPrint('Rust validation failed: $e');
      return ValidationResult(
        isValid: false,
        errors: ['Validation failed: ${e.toString()}'],
        warnings: [],
        lineCount: source.split('\n').length,
        characterCount: source.length,
      );
    }

    // Rust bridge returned no result (FFI unavailable on this platform).
    // Fail loud rather than fall back to wrong-language heuristics.
    return ValidationResult(
      isValid: false,
      errors: const ['Script validator unavailable (native bridge not loaded)'],
      warnings: const [],
      lineCount: source.split('\n').length,
      characterCount: source.length,
    );
  }

  Future<ValidationResult?> _validateWithRust(String source) async {
    try {
      // Determine context from JS comment markers.
      final isExample = source.contains(
          RegExp(r'//\s*(example|demo|tutorial|sample)', caseSensitive: false));
      final isTest = source.contains(
          RegExp(r'//\s*(test|spec|unit)', caseSensitive: false));
      final isProduction = !isExample && !isTest;

      // Call Rust validation via FFI
      final rustBridge = NativeBridge();
      final resultJson = rustBridge.validateJsComprehensive(
        script: source,
        isExample: isExample,
        isTest: isTest,
        isProduction: isProduction,
      );

      if (resultJson.isNotEmpty) {
        final Map<String, dynamic> jsonResult =
            json.decode(resultJson) as Map<String, dynamic>;
        return ValidationResult.fromRustJson(jsonResult);
      }
    } catch (e) {
      // Return null to trigger the unavailable-bridge error path.
      return null;
    }
    return null;
  }
}
