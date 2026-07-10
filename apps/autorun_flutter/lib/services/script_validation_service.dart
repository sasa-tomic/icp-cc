import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../rust/native_bridge.dart';

/// Thrown when the Rust validator returns a result that cannot be understood
/// (malformed JSON, unexpected schema) — or when the FFI call itself fails
/// (e.g. a missing symbol from a version-mismatched `.so`).
///
/// This is a **real error** and must surface. It is deliberately distinct from
/// the soft "bridge unavailable" path: an empty FFI result (the native library
/// could not be opened) is reported as "validator unavailable", whereas this
/// exception means the bridge *was* loaded but something went wrong — silently
/// reporting that as "bridge unavailable" makes real failures undebuggable
/// (AUD-2).
class ScriptValidationException implements Exception {
  ScriptValidationException(this.message, {this.cause, this.resultSnippet});

  final String message;
  final Object? cause;

  /// A short excerpt of the offending validator output (when the failure was a
  /// parse error), to aid debugging. May be `null` for FFI-call failures.
  final String? resultSnippet;

  @override
  String toString() {
    final parts = <String>['ScriptValidationException: $message'];
    if (cause != null) parts.add('cause: $cause');
    if (resultSnippet != null) {
      final snippet = resultSnippet!;
      parts.add('rust result: "${snippet.length > 200 ? '${snippet.substring(0, 200)}…' : snippet}"');
    }
    return parts.join('; ');
  }
}


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
/// This class previously hosted a `quickValidate` heuristic that ran as a
/// fallback when the Rust bridge was unavailable. Per cleanup-plan TD-8, that
/// heuristic is removed: the Rust validator is authoritative, and when FFI is
/// unavailable we now surface a clear error rather than silently returning
/// stale heuristics.
class ScriptValidationService {
  static final ScriptValidationService _instance =
      ScriptValidationService._internal();
  factory ScriptValidationService() => _instance;
  ScriptValidationService._internal() : _validator = null;

  /// Test seam: inject a stand-in for the native validator that returns its raw
  /// JSON result for [source]. Production callers use the default factory,
  /// which delegates to the real [NativeBridge]. This lets the bridge-missing
  /// (empty result) and malformed-result paths be exercised deterministically.
  @visibleForTesting
  ScriptValidationService.withValidator(String Function(String source) validator)
      : _validator = validator;

  final String Function(String source)? _validator;

  Future<ValidationResult> validateScript(String source) async {
    try {
      final rustResult = await _validateWithRust(source);
      if (rustResult != null) {
        return rustResult;
      }
    } on ScriptValidationException catch (e) {
      // A REAL error calling/parsing the validator — surface the cause loudly,
      // never confuse it with the bridge-missing soft path (AUD-2).
      debugPrint('Script validation error: $e');
      return _failure(source, ['Validation error: $e']);
    }

    // The bridge returned an empty result: the native library could not be
    // loaded on this platform. This is the ONLY soft "null" path — fail loud
    // rather than fall back to wrong-language heuristics.
    return _failure(
        source, const ['Script validator unavailable (native bridge not loaded)']);
  }

  ValidationResult _failure(String source, List<String> errors) =>
      ValidationResult(
        isValid: false,
        errors: errors,
        warnings: const [],
        lineCount: source.split('\n').length,
        characterCount: source.length,
      );

  Future<ValidationResult?> _validateWithRust(String source) async {
    // Determine context from JS comment markers.
    final isExample = source.contains(
        RegExp(r'//\s*(example|demo|tutorial|sample)', caseSensitive: false));
    final isTest = source.contains(
        RegExp(r'//\s*(test|spec|unit)', caseSensitive: false));
    final isProduction = !isExample && !isTest;

    // Call Rust validation via FFI. An EMPTY result means the native bridge
    // could not be opened (legit "validator unavailable" soft path). Any OTHER
    // failure here (e.g. a missing symbol from a version-mismatched library) is
    // a real error — surface it typed instead of swallowing it as a null.
    final String resultJson;
    try {
      final injected = _validator;
      resultJson = injected != null
          ? injected(source)
          : NativeBridge().validateJsComprehensive(
              script: source,
              isExample: isExample,
              isTest: isTest,
              isProduction: isProduction,
            );
    } catch (e) {
      throw ScriptValidationException('Native validator call failed', cause: e);
    }

    if (resultJson.isEmpty) {
      return null; // bridge unavailable — the soft path
    }

    // Parse the Rust result. A malformed/unexpected result is a REAL error —
    // surface it typed with the offending snippet, never as "bridge unavailable".
    try {
      final Map<String, dynamic> jsonResult =
          json.decode(resultJson) as Map<String, dynamic>;
      return ValidationResult.fromRustJson(jsonResult);
    } catch (e) {
      throw ScriptValidationException(
        'Failed to parse native validator result',
        cause: e,
        resultSnippet: resultJson,
      );
    }
  }
}
