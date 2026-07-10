import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_validation_service.dart';

/// Deterministic tests for `ScriptValidationService` error handling (AUD-2).
///
/// Before AUD-2, a single `catch (e) { return null; }` swallowed EVERY failure
/// in `_validateWithRust` — a malformed Rust result, a JSON decode error, a
/// cast error — and reported them all identically to "the native bridge isn't
/// loaded", making real failures undebuggable. These tests pin the narrowed
/// contract via the `withValidator` seam:
///
///   * an EMPTY bridge result  → soft "validator unavailable" (legit, preserved)
///   * a MALFORMED bridge result → typed error surfaced (NOT "unavailable")
///   * a bridge that THROWS      → typed error surfaced (NOT "unavailable")
///   * a well-formed bridge result → parsed normally
void main() {
  // A minimal well-formed Rust validator result (valid script).
  const validRustResult =
      '{"is_valid":true,"syntax_errors":[],"warnings":[],"line_count":3,"character_count":42}';

  group('ScriptValidationService error handling (AUD-2)', () {
    test('empty bridge result → soft "validator unavailable" (bridge-missing path)',
        () async {
      final service = ScriptValidationService.withValidator((_) => '');
      final result = await service.validateScript('const x = 1;');

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('unavailable')),
        isTrue,
        reason: 'a missing bridge must surface the soft unavailable error',
      );
    });

    test('malformed JSON from bridge → typed error, NOT "unavailable"',
        () async {
      final service =
          ScriptValidationService.withValidator((_) => 'not valid json {');
      final result = await service.validateScript('const x = 1;');

      expect(result.isValid, isFalse);
      // The regression: previously this was swallowed as "unavailable".
      expect(
        result.errors.any((e) => e.contains('unavailable')),
        isFalse,
        reason: 'a parse failure must not be misreported as a missing bridge',
      );
      // The real error surfaces, carrying the parse cause + the offending snippet.
      expect(
        result.errors.any((e) =>
            e.contains('Validation error') &&
            e.contains('parse native validator result') &&
            e.contains('rust result:')),
        isTrue,
        reason: 'the typed validation error + snippet must be surfaced',
      );
      expect(
        result.errors.join('\n'),
        contains('not valid json {'),
        reason: 'the offending rust result snippet must be included for debugging',
      );
    });

    test('valid JSON that is not a map (array) → typed error, NOT "unavailable"',
        () async {
      final service = ScriptValidationService.withValidator((_) => '[1, 2, 3]');
      final result = await service.validateScript('const x = 1;');

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('unavailable')),
        isFalse,
      );
      expect(
        result.errors.any((e) =>
            e.contains('Validation error') &&
            e.contains('parse native validator result')),
        isTrue,
      );
    });

    test('bridge that throws → typed error, NOT "unavailable"', () async {
      final service = ScriptValidationService.withValidator(
        (_) => throw StateError('symbol lookup failed (version mismatch)'),
      );
      final result = await service.validateScript('const x = 1;');

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('unavailable')),
        isFalse,
        reason: 'an FFI call failure must not be misreported as a missing bridge',
      );
      expect(
        result.errors.any((e) =>
            e.contains('Validation error') &&
            e.contains('Native validator call failed')),
        isTrue,
        reason: 'the FFI-call failure must surface as the typed error',
      );
    });

    test('well-formed bridge result → parsed normally (happy path intact)',
        () async {
      final service =
          ScriptValidationService.withValidator((_) => validRustResult);
      final result = await service.validateScript('const x = 1;');

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.lineCount, 3);
      expect(result.characterCount, 42);
    });
  });

  test('ScriptValidationException toString includes cause + snippet', () {
    final exception = ScriptValidationException(
      'Failed to parse native validator result',
      cause: const FormatException('Unexpected character'),
      resultSnippet: 'garbage{',
    );

    final text = exception.toString();
    expect(text, contains('ScriptValidationException'));
    expect(text, contains('FormatException'));
    expect(text, contains('rust result:'));
    expect(text, contains('garbage{'));
  });

  test('ScriptValidationException truncates very long snippets', () {
    final exception = ScriptValidationException(
      'boom',
      resultSnippet: 'x' * 500,
    );

    expect(exception.toString(), contains('…'));
  });
}
