// R-3 WU-5 — Pure-Dart static-analysis unit tests (the PRIMARY VM bar).
//
// The `static_analysis` mod (`js_engine.rs:25-635`) is deterministic TEXT
// inspection — it never runs QuickJS — so its faithful Dart port
// (`js_static_analysis.dart`) is exhaustively unit-testable in `flutter test`
// (VM). This file exercises EVERY rule, positive AND negative, asserting the
// exact message strings and the rule-application order.
//
// The browser-only runtime stage (syntax check + required exports) is exercised
// by the Chrome parity probe (`just verify-quickjs-web-parity`); the
// runtime-stage golden vectors live in `js_validation_golden_vectors.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/web/js_static_analysis.dart';

// Production / example / test contexts (js_engine.rs:1102-1108).
final JsValidationContext _prod = JsValidationContext(
  isExample: false,
  isTest: false,
  isProduction: true,
);
final JsValidationContext _nonProd = JsValidationContext(
  isExample: true,
  isTest: false,
  isProduction: false,
);

const String _iVu = 'function init(arg){ return {state:{},effects:[]}; }\n'
    'function view(state){ return {}; }\n'
    'function update(msg,state){ return {state:state,effects:[]}; }';

void main() {
  group('freshResult — line_count / character_count parity with Rust', () {
    test('line_count matches Rust str::lines().count() edge cases', () {
      // Verified against the Rust reference (see WU-5 investigation).
      expect(freshResult('').lineCount, 0, reason: '"" → 0');
      expect(freshResult('a').lineCount, 1);
      expect(freshResult('a\n').lineCount, 1, reason: 'trailing newline optional');
      expect(freshResult('a\nb').lineCount, 2);
      expect(freshResult('a\nb\n').lineCount, 2);
      expect(freshResult('\n').lineCount, 1);
      expect(freshResult('\n\n').lineCount, 2);
      expect(freshResult('a\r\nb').lineCount, 2, reason: 'CRLF is one terminator');
      expect(freshResult('a\r\nb\r\n').lineCount, 2);
    });

    test('character_count is UTF-8 byte length (Rust str::len)', () {
      expect(freshResult('abc').characterCount, 3);
      // Non-ASCII: 'é' is 2 UTF-8 bytes — must match Rust `.len()`.
      expect(freshResult('é').characterCount, 2);
      expect(freshResult('€').characterCount, 3);
    });
  });

  group('context detection (is_example/is_test_script)', () {
    test('example markers', () {
      expect(isExampleScript('// Example script'), isTrue);
      expect(isExampleScript('// demo app'), isTrue);
      expect(isExampleScript('// TUTORIAL'), isTrue);
      expect(isExampleScript('// sample'), isTrue);
      expect(isExampleScript('/* example'), isTrue);
      expect(isExampleScript('/* demo'), isTrue);
      expect(isExampleScript('function init(){}'), isFalse);
    });

    test('test markers', () {
      expect(isTestScript('// test case'), isTrue);
      expect(isTestScript('// spec'), isTrue);
      expect(isTestScript('// unit'), isTrue);
      expect(isTestScript('function init(){}'), isFalse);
    });

    test('defaultContext: production is the residual', () {
      expect(defaultContext('// example').isProduction, isFalse);
      expect(defaultContext('// test').isProduction, isFalse);
      expect(defaultContext('function init(){}').isProduction, isTrue);
    });
  });

  group('validate_basic', () {
    test('empty source is rejected', () {
      final r = runStaticStages('   \n  \t ', _prod);
      expect(r.syntaxErrors, contains('JavaScript source cannot be empty'));
    });
  });

  group('validate_security_patterns — dangerous calls', () {
    test('eval() call is blocked', () {
      final r = runStaticStages('eval("1"); $_iVu', _prod);
      expect(r.syntaxErrors,
          contains('eval() detected - dynamic code execution not allowed'));
    });

    test('Function() constructor is blocked', () {
      final r = runStaticStages('var x = Function("return 1"); $_iVu', _prod);
      expect(
          r.syntaxErrors,
          contains(
              'Function() constructor detected - dynamic code execution not allowed'));
    });

    test('require() is blocked', () {
      final r = runStaticStages('require("fs"); $_iVu', _prod);
      expect(r.syntaxErrors, contains('require() - module loading not allowed'));
    });

    test('dynamic import() is blocked', () {
      final r = runStaticStages('import("x"); $_iVu', _prod);
      expect(r.syntaxErrors, contains('dynamic import() not allowed'));
    });

    test('benign *Function / *eval substring identifiers are NOT flagged', () {
      // NOTE: `\$Function` is an escaped dollar (literal JS identifier
      // `$Function`) — unescaped `$Function` would interpolate the Dart
      // `Function` type into a bare call and trip the gate.
      final script = 'function assertFunction(x){return x;} '
          'const isFunction=(x)=>x; function myeval(x){return x;} '
          'function _Function(x){return x;} function \$Function(x){return x;} $_iVu';
      final r = runStaticStages(script, _prod);
      expect(r.syntaxErrors.where((e) => e.contains('Function')), isEmpty);
      expect(r.syntaxErrors.where((e) => e.contains('eval')), isEmpty);
    });

    test('new Function / globalThis.Function / bare Function are blocked', () {
      for (final s in [
        'var x = new Function("return 1"); $_iVu',
        'var x = globalThis.Function("return 1"); $_iVu',
        'var f = Function("x","return x"); $_iVu',
      ]) {
        final r = runStaticStages(s, _prod);
        expect(r.syntaxErrors.any((e) => e.contains('Function')), isTrue,
            reason: 'should block Function in: $s');
      }
    });
  });

  group('validate_security_patterns — member access / tampering', () {
    test('process. / globalThis[ / delete globalThis are blocked', () {
      expect(runStaticStages('process.uptime; $_iVu', _prod).syntaxErrors,
          contains('process access not allowed'));
      expect(runStaticStages('globalThis["x"]; $_iVu', _prod).syntaxErrors,
          contains('globalThis property access by key not allowed'));
      expect(runStaticStages('delete globalThis.x; $_iVu', _prod).syntaxErrors,
          contains('globalThis tampering not allowed'));
    });
  });

  group('validate_security_patterns — secrets', () {
    test('production: hardcoded private_key is an error', () {
      final r = runStaticStages('var pk = "private_key"; $_iVu', _prod);
      expect(
          r.syntaxErrors,
          contains(
              'Hardcoded private key detected - use environment variables or secure storage'));
    });

    test('production: potential secret (password + quotes + len>100) is an error', () {
      final long = 'var password = "x"${' ' * 100}';
      final r = runStaticStages('$long $_iVu', _prod);
      expect(
          r.syntaxErrors,
          anyElement(contains(
              'Potential hardcoded secret detected - use environment variables or secure storage')));
    });

    test('non-production: sk-/pk_ is a WARNING, not an error', () {
      final r = runStaticStages('var k = "sk-test1234"; $_iVu', _nonProd);
      expect(r.isValid, isTrue);
      expect(r.warnings, contains('Potential real secret detected in example/test code'));
    });
  });

  group('validate_security_patterns — HTML/JS + URLs', () {
    test('<script and javascript: are blocked', () {
      expect(runStaticStages('var x = "<script>"; $_iVu', _prod).syntaxErrors,
          contains('Dangerous HTML/JavaScript pattern detected'));
      expect(runStaticStages('var x = "javascript:"; $_iVu', _prod).syntaxErrors,
          contains('Dangerous HTML/JavaScript pattern detected'));
    });

    test('localhost URL: production → error, non-production → warning', () {
      // The URL must be a bare whitespace token (Rust scans
      // `split_whitespace` + `starts_with("http")` — a leading quote would
      // hide it).
      final prod = runStaticStages('var u = http://localhost:8080 end $_iVu', _prod);
      expect(
          prod.syntaxErrors,
          anyElement(
              contains('Localhost URL in production code: http://localhost:8080')));
      final nonProd =
          runStaticStages('var u = http://localhost:8080 end $_iVu', _nonProd);
      expect(nonProd.warnings,
          anyElement(contains('Localhost URL detected: http://localhost:8080')));
    });

    test('insecure http:// in production → warning', () {
      final r =
          runStaticStages('// ref http://example.com $_iVu', _prod);
      expect(
          r.warnings,
          anyElement(
              contains('Insecure HTTP URL detected: http://example.com')));
    });
  });

  group('validate_esm_format', () {
    test('top-level import / export are blocked', () {
      expect(
          runStaticStages('import x from "y"; $_iVu', _prod).syntaxErrors,
          contains(
              'ESM top-level import/export is not allowed - scripts must use function init/view/update'));
      expect(
          runStaticStages('export function init(){} function view(){} function update(){}', _prod)
              .syntaxErrors,
          contains(
              'ESM top-level import/export is not allowed - scripts must use function init/view/update'));
    });

    test('identifier suffixes (imported / exports) are NOT flagged', () {
      final r = runStaticStages(
          'var imported = 1; var exports = 2; $_iVu', _prod);
      expect(r.syntaxErrors.where((e) => e.contains('ESM')), isEmpty);
    });
  });

  group('validate_intl', () {
    test('Intl.* is blocked', () {
      final r =
          runStaticStages('var s = Intl.NumberFormat(); $_iVu', _prod);
      expect(
          r.syntaxErrors,
          contains(
              'Intl.* is not allowed - the runtime ships without ICU; use the locale-free icp_format_* helpers'));
    });
  });

  group('validate_icp_integration', () {
    test('invalid canister ID format: production → error, else → warning', () {
      final prod = runStaticStages(
          'var cid = canister_id "short"; $_iVu', _prod);
      expect(
          prod.syntaxErrors,
          anyElement(contains('Invalid canister ID format: short')));
      final nonProd = runStaticStages(
          'var cid = canister_id "short"; $_iVu', _nonProd);
      expect(nonProd.warnings,
          anyElement(contains('Potentially invalid canister ID format: short')));
    });

    test('example/test canister starting with test/mock/demo/example is skipped', () {
      final r = runStaticStages(
          'var cid = canister_id "testabc"; $_iVu', _nonProd);
      expect(
          r.warnings.where((w) => w.contains('canister ID format')), isEmpty,
          reason: 'test-prefixed canister IDs are allowed in example/test code');
    });

    test('ICP calls without effect/result handler: production → error', () {
      final r = runStaticStages(
          'var e = { kind: "icp_call" }; $_iVu', _prod);
      expect(
          r.syntaxErrors,
          contains(
              'Script uses ICP calls but missing effect/result handler in update() function'));
    });

    test('ICP calls WITH effect/result handler: no error', () {
      final r = runStaticStages(
          'var e = { kind: "icp_call" }; var h = "effect/result"; $_iVu', _prod);
      expect(
          r.syntaxErrors.where((e) => e.contains('effect/result')),
          isEmpty);
    });

    test('canister call line missing args → warning', () {
      final r = runStaticStages(
          'var line = { canister_id: "a-b-c-d-e-f-g-h", method: "m", kind: "k" }; $_iVu',
          _prod);
      expect(r.warnings,
          contains('Canister call missing args field - may cause runtime errors'));
    });
  });

  group('validate_performance_patterns', () {
    test('infinite-loop patterns warn (production only)', () {
      for (final pat in ['while (true)', 'while(true)', 'for (;;)', 'for(;;)']) {
        final r = runStaticStages('$pat {} $_iVu', _prod);
        expect(r.warnings,
            contains('Possible infinite loop detected - ensure termination'),
            reason: 'missing warning for: $pat');
      }
      // Non-production: no infinite-loop warning.
      final np = runStaticStages('while (true) {} $_iVu', _nonProd);
      expect(np.warnings.where((w) => w.contains('infinite loop')), isEmpty);
    });

    test('very large integer literal warns', () {
      // Bare 15-digit token (no trailing `;` — Rust scans whitespace tokens).
      final r = runStaticStages('var n = 123456789012345 end $_iVu', _prod);
      expect(
          r.warnings,
          contains(
              'Very large numbers detected - ensure they fit within safe integer limits'));
    });

    test('>50 .push( calls warn (optimize)', () {
      final pushes = List<String>.filled(51, 'a.push(1)').join('; ');
      final r = runStaticStages('$pushes $_iVu', _prod);
      expect(
          r.warnings,
          contains(
              'Many array.push operations detected - consider optimizing for better performance'));
    });

    test('apparent recursion warns (production)', () {
      // `foo(` appears twice (definition + call) → recursion warning.
      final r = runStaticStages(
          'function foo(x){ foo(x); } $_iVu', _prod);
      expect(
          r.warnings,
          contains(
              "Function 'foo' may be recursive - ensure base case exists"));
    });
  });

  group('validate_data_structures', () {
    test('uninitialised state field warns (production)', () {
      // The line must literally start with `state.` (Rust scans per-line
      // `strip_prefix("state.")`); `state.mystery` is never initialised.
      final r = runStaticStages(
          'state.mystery;\n$_iVu', _prod);
      expect(
          r.warnings,
          contains(
              "State field 'state.mystery' may be undefined - ensure it's initialized in init()"));
    });

    test('>100 .push( calls warn (pre-allocate)', () {
      final pushes = List<String>.filled(101, 'a.push(1)').join('; ');
      final r = runStaticStages('$pushes $_iVu', _prod);
      expect(
          r.warnings,
          contains(
              'Many array.push operations detected - consider pre-allocating arrays for better performance'));
    });
  });

  group('validate_ui_nodes', () {
    test('conditional UI expression missing type is an error', () {
      final r = runStaticStages(
          'var x = cond && { props: {} }; $_iVu', _prod);
      expect(
          r.syntaxErrors,
          contains(
              'Conditional UI expression missing type field - this will cause "UI node missing type" error'));
    });

    test('empty UI node type is an error', () {
      final r = runStaticStages(
          'function view(s){ return { type: "", props: {} }; } '
          'function init(){return {state:{},effects:[]};} '
          'function update(m,s){return {state:s,effects:[]};}', _prod);
      expect(r.syntaxErrors, contains('UI node with empty type found'));
    });

    test('unknown UI node type warns; known types do not', () {
      final unknown = runStaticStages(
          'function view(s){ return { type: "mystery_node", props: {} }; } '
          'function init(){return {state:{},effects:[]};} '
          'function update(m,s){return {state:s,effects:[]};}', _prod);
      expect(
          unknown.warnings,
          anyElement(contains('Unknown UI node type: "mystery_node"')));
      for (final t in ['column', 'row', 'text', 'button', 'table']) {
        final ok = runStaticStages(
            'function view(s){ return { type: "$t", props: {} }; } '
            'function init(){return {state:{},effects:[]};} '
            'function update(m,s){return {state:s,effects:[]};}', _prod);
        expect(ok.warnings.where((w) => w.contains('Unknown UI node type')), isEmpty,
            reason: '$t should be allowlisted');
      }
    });
  });

  group('run_static_stages — validity + ordering', () {
    test('a clean bundle is valid with no syntax errors', () {
      final r = runStaticStages(_iVu, _prod);
      expect(r.syntaxErrors, isEmpty);
      expect(r.isValid, isTrue);
      expect(r.characterCount, greaterThan(0));
    });

    test('is_valid is the conjunction of no syntax errors', () {
      final bad = runStaticStages('eval("1"); $_iVu', _prod);
      expect(bad.isValid, isFalse);
      final good = runStaticStages(_iVu, _prod);
      expect(good.isValid, isTrue);
    });
  });
}
