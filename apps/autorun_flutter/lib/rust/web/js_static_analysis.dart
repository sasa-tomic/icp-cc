// R-3 WU-5 — Pure-Dart port of the JS `static_analysis` module.
//
// Faithful, line-for-line port of `crates/icp_core/src/js_engine.rs:25-635`
// (the `static_analysis` mod + the `JsValidationContext` / `JsValidationResult`
// types defined at `js_engine.rs:9-23`). Every rule, every message string, and
// the rule APPLICATION ORDER are identical to the native reference, so a bundle
// produces the SAME `{is_valid, syntax_errors, warnings, line_count,
// character_count}` on Web as on native for the static (text-only) stages.
//
// ## Why this file is pure-Dart (no `dart:js_interop`)
// Static analysis is deterministic TEXT inspection — it never runs QuickJS.
// It therefore runs UNCHANGED on both the Dart VM and the JS (web) target, so
// the same code paths ship to the browser AND are exhaustively unit-tested in
// `flutter test` (see `test/features/web/js_static_analysis_test.dart`). This
// file is imported directly by `native_bridge_web.dart` with NO conditional
// import — unlike the runtime execution stage (`quickjs_engine.dart`), which
// needs `dart:js_interop` and so lives behind a conditional-import access
// module.
//
// ## Parity caveats (documented, not divergent)
// - `line_count`: Rust uses `str::lines().count()` (splits on `\n` / `\r\n`,
//   final terminator optional). [_rustLines] replicates this exactly (verified
//   against the Rust reference for edge cases — see the VM test).
// - `character_count`: Rust uses `str::len()` = UTF-8 BYTE length. We use
//   `utf8.encode(script).length` for byte-for-byte parity (ASCII bundles are
//   unaffected; non-ASCII matches native exactly).
// - Identifier checks use ASCII (bundles are ASCII); this matches the native
//   `is_ident_char` (`is_ascii_alphanumeric`) helper.
library;

import 'dart:convert';

/// Mirrors `JsValidationContext` (`js_engine.rs:9-14`). The validation context
/// is EITHER supplied explicitly by the caller (the `validateJsComprehensive`
/// FFI path — `ffi.rs:359-363`) OR auto-detected from the script text (the
/// `lint_js` path — `runtime.rs:258` passes `None` → [defaultContext]).
class JsValidationContext {
  const JsValidationContext({
    required this.isExample,
    required this.isTest,
    required this.isProduction,
  });
  final bool isExample;
  final bool isTest;
  final bool isProduction;
}

/// Mirrors `JsValidationResult` (`js_engine.rs:16-23`).
class JsValidationResult {
  JsValidationResult({
    required this.isValid,
    required this.syntaxErrors,
    required this.warnings,
    required this.lineCount,
    required this.characterCount,
  });

  bool isValid;
  final List<String> syntaxErrors;
  final List<String> warnings;
  final int lineCount;
  final int characterCount;
}

/// `fresh_result` (`js_engine.rs:28-36`).
JsValidationResult freshResult(String script) => JsValidationResult(
      isValid: true,
      syntaxErrors: <String>[],
      warnings: <String>[],
      lineCount: _rustLines(script).length,
      characterCount: utf8.encode(script).length,
    );

/// `default_context` (`js_engine.rs:38-46`). Auto-detects example/test markers;
/// `is_production = !is_example && !is_test` (production is the residual).
JsValidationContext defaultContext(String script) {
  final isExample = isExampleScript(script);
  final isTest = isTestScript(script);
  return JsValidationContext(
    isExample: isExample,
    isTest: isTest,
    isProduction: !isExample && !isTest,
  );
}

/// `is_example_script` (`js_engine.rs:48-56`).
bool isExampleScript(String script) {
  final lower = script.toLowerCase();
  return lower.contains('// example') ||
      lower.contains('// demo') ||
      lower.contains('// tutorial') ||
      lower.contains('// sample') ||
      lower.contains('/* example') ||
      lower.contains('/* demo');
}

/// `is_test_script` (`js_engine.rs:58-61`).
bool isTestScript(String script) {
  final lower = script.toLowerCase();
  return lower.contains('// test') ||
      lower.contains('// spec') ||
      lower.contains('// unit');
}

/// `validate_basic` (`js_engine.rs:63-69`).
void validateBasic(String script, JsValidationResult result) {
  if (script.trim().isEmpty) {
    result.syntaxErrors.add('JavaScript source cannot be empty');
  }
}

/// `validate_event_handlers` (`js_engine.rs:71-107`). Cross-checks UI
/// `on(Press|Change|Submit|Input)` handlers against `msg.type === "..."` cases
/// in `update()`, warning on orphaned handlers / message types.
void validateEventHandlers(String script, JsValidationResult result) {
  final eventHandlerRegex =
      RegExp(r'on(Press|Change|Submit|Input)\s*:\s*\{\s*type\s*:\s*"([^"]+)"');
  final eventHandlers = <String>[];
  for (final m in eventHandlerRegex.allMatches(script)) {
    final handler = m.group(2);
    if (handler != null) eventHandlers.add(handler);
  }

  final messageTypeRegex = RegExp(r'msg\.type\s*===?\s*"([^"]+)"');
  final messageTypes = <String>[];
  for (final m in messageTypeRegex.allMatches(script)) {
    final msgType = m.group(1);
    if (msgType != null) messageTypes.add(msgType);
  }

  for (final handler in eventHandlers) {
    if (!messageTypes.contains(handler) && !handler.startsWith('effect/')) {
      result.warnings.add(
          "Event handler '$handler' has no corresponding case in update() function");
    }
  }
  for (final msgType in messageTypes) {
    if (!eventHandlers.contains(msgType) && !msgType.startsWith('effect/')) {
      result.warnings.add(
          "Message handler '$msgType' has no corresponding UI event handler");
    }
  }
}

/// `validate_security_patterns` (`js_engine.rs:109-213`). The security core:
/// forbids dynamic-code-execution / module-loading primitives, globalThis
/// tampering, hardcoded secrets (production), and dangerous HTML/JS patterns.
void validateSecurityPatterns(
  String script,
  JsValidationContext context,
  JsValidationResult result,
) {
  // Dynamic-code-execution and module-loading primitives (`js_engine.rs:120-135`).
  const nameMessage = <(String, String)>[
    ('eval', 'eval() detected - dynamic code execution not allowed'),
    (
      'Function',
      'Function() constructor detected - dynamic code execution not allowed'
    ),
    ('import', 'dynamic import() not allowed'),
    ('require', 'require() - module loading not allowed'),
  ];
  for (final (name, message) in nameMessage) {
    if (dangerousCallPresent(script, name)) {
      result.syntaxErrors.add(message);
    }
  }

  // Member-access / tampering primitives (`js_engine.rs:139-153`).
  if (script.contains('process.')) {
    result.syntaxErrors.add('process access not allowed');
  }
  if (script.contains('globalThis[')) {
    result.syntaxErrors
        .add('globalThis property access by key not allowed');
  }
  if (script.contains('delete globalThis')) {
    result.syntaxErrors.add('globalThis tampering not allowed');
  }

  // Hardcoded-secret detection (`js_engine.rs:155-177`).
  if (context.isProduction) {
    if (script.contains('private_key') &&
        (script.contains('"') || script.contains("'"))) {
      result.syntaxErrors.add(
          'Hardcoded private key detected - use environment variables or secure storage');
    }
    if ((script.contains('password') ||
            script.contains('token') ||
            script.contains('api_key')) &&
        (script.contains('"') || script.contains("'")) &&
        script.length > 100) {
      result.syntaxErrors.add(
          'Potential hardcoded secret detected - use environment variables or secure storage');
    }
  } else if (script.contains('sk-') || script.contains('pk_')) {
    result.warnings
        .add('Potential real secret detected in example/test code');
  }

  // Dangerous HTML/JS (`js_engine.rs:179-183`).
  if (script.contains('<script') || script.contains('javascript:')) {
    result.syntaxErrors.add('Dangerous HTML/JavaScript pattern detected');
  }

  // URL checks (`js_engine.rs:185-212`).
  if (script.contains('http://') || script.contains('https://')) {
    final words = _splitWhitespace(script);
    for (final word in words) {
      if (word.startsWith('http://') || word.startsWith('https://')) {
        final url = _trimMatchesTrailing(word);
        if (url.contains('localhost') || url.contains('127.0.0.1')) {
          if (context.isProduction) {
            result.syntaxErrors.add('Localhost URL in production code: $url');
          } else {
            result.warnings
                .add('Localhost URL detected: $url - ensure this is intentional');
          }
        }
        if (url.startsWith('http://') && context.isProduction) {
          result.warnings
              .add('Insecure HTTP URL detected: $url - consider using HTTPS');
        }
      }
    }
  }
}

/// `validate_esm_format` (`js_engine.rs:491-511`). Rejects top-level ESM
/// `import` / `export` — bundles must use function `init`/`view`/`update`.
void validateEsmFormat(String script, JsValidationResult result) {
  for (final line in _rustLines(script)) {
    final trimmed = _trimStart(line);
    for (final kw in <String>['import', 'export']) {
      if (trimmed.startsWith(kw)) {
        final rest = trimmed.substring(kw.length);
        final boundary = rest.isEmpty
            ? true
            : !_isAlphaNumericOrUnderscore(rest.codeUnitAt(0));
        if (boundary) {
          result.syntaxErrors.add(
              'ESM top-level import/export is not allowed - scripts must use function init/view/update');
          break; // only the inner `kw` loop — one ESM error per line max.
        }
      }
    }
  }
}

/// `validate_intl` (`js_engine.rs:513-521`). The runtime ships without ICU;
/// `Intl.*` is forbidden (use the locale-free `icp_format_*` helpers).
void validateIntl(String script, JsValidationResult result) {
  final intlRe = RegExp(r'\bIntl\s*\.');
  if (intlRe.hasMatch(script)) {
    result.syntaxErrors.add(
        'Intl.* is not allowed - the runtime ships without ICU; use the locale-free icp_format_* helpers');
  }
}

/// `validate_icp_integration` (`js_engine.rs:251-341`). Validates canister-ID
/// literals, requires an `effect/result` handler when ICP calls are emitted,
/// and warns on canister calls missing an `args` field.
void validateIcpIntegration(
  String script,
  JsValidationContext context,
  JsValidationResult result,
) {
  // Canister-ID literal validation (`js_engine.rs:256-305`).
  var pos = 0;
  while (true) {
    final canisterStart = script.indexOf('canister_id', pos);
    if (canisterStart == -1) break;
    final absoluteStart = canisterStart;
    final remaining = script.substring(absoluteStart);
    final quoteStartRel = _findFirstQuote(remaining);
    if (quoteStartRel == -1) break;
    final quoteCode = remaining.codeUnitAt(quoteStartRel);
    final quotePos = absoluteStart + quoteStartRel;
    final afterQuote = script.substring(quotePos + 1);
    final relEnd = afterQuote.indexOf(String.fromCharCode(quoteCode));
    if (relEnd == -1) break;
    final absoluteEnd = quotePos + 1 + relEnd;
    final canisterId = script.substring(quotePos + 1, absoluteEnd);

    if (context.isExample || context.isTest) {
      final canisterLower = canisterId.toLowerCase();
      if (canisterLower.startsWith('test') ||
          canisterLower.startsWith('mock') ||
          canisterLower.startsWith('demo') ||
          canisterLower.startsWith('example')) {
        pos = absoluteEnd;
        continue;
      }
    }

    if (canisterId.length < 10 ||
        canisterId.length > 63 ||
        !canisterId.contains('-')) {
      if (context.isProduction) {
        result.syntaxErrors.add(
            'Invalid canister ID format: $canisterId. Expected format: xxxxx-xxxxx-xxxxx-xxxxx-xxxxx-xxx-xxx');
      } else {
        result.warnings.add('Potentially invalid canister ID format: $canisterId');
      }
    }

    pos = absoluteEnd;
  }

  // ICP-call effect/result handler (`js_engine.rs:307-326`).
  if (script.contains('kind: "icp_call"') ||
      script.contains('kind:"icp_call"') ||
      script.contains('kind: "icp_batch"') ||
      script.contains('kind:"icp_batch"')) {
    final scriptLower = script.toLowerCase();
    if (!scriptLower.contains('effect/result')) {
      if (context.isProduction) {
        result.syntaxErrors.add(
            'Script uses ICP calls but missing effect/result handler in update() function');
      } else {
        result.warnings.add(
            'Script uses ICP calls but missing effect/result handler in update() function');
      }
    }
  }

  // Canister call missing args (`js_engine.rs:328-340`).
  if (script.contains('canister_id') &&
      script.contains('method') &&
      script.contains('kind')) {
    for (final line in _rustLines(script)) {
      if (line.contains('canister_id') &&
          line.contains('method') &&
          line.contains('kind') &&
          !line.contains('args')) {
        result.warnings
            .add('Canister call missing args field - may cause runtime errors');
      }
    }
  }
}

/// `validate_performance_patterns` (`js_engine.rs:343-404`).
void validatePerformancePatterns(
  String script,
  JsValidationContext context,
  JsValidationResult result,
) {
  if (context.isProduction) {
    // Infinite-loop patterns (`js_engine.rs:349-357`).
    const infiniteLoopPatterns = [
      'while (true)',
      'while(true)',
      'for (;;)',
      'for(;;)',
    ];
    for (final pat in infiniteLoopPatterns) {
      if (script.contains(pat)) {
        result.warnings
            .add('Possible infinite loop detected - ensure termination');
        break;
      }
    }

    // Possible recursion (`js_engine.rs:359-384`).
    final lines = _rustLines(script);
    final limit = lines.length < 100 ? lines.length : 100;
    for (var i = 0; i < limit; i++) {
      final trimmed = lines[i].trim();
      String? rest;
      if (trimmed.startsWith('function ')) {
        rest = trimmed.substring('function '.length);
      } else if (trimmed.startsWith('const ')) {
        rest = trimmed.substring('const '.length);
      } else if (trimmed.startsWith('let ')) {
        rest = trimmed.substring('let '.length);
      }
      if (rest == null) continue;
      final parenStart = rest.indexOf('(');
      if (parenStart == -1) continue;
      final namePart = rest.substring(0, parenStart).trim();
      final funcName = _lastTokenOnSpaceOrEquals(namePart).trim();
      if (funcName.isEmpty) continue;
      if (funcName == 'init' || funcName == 'view' || funcName == 'update') {
        continue;
      }
      final callPattern = '$funcName(';
      if (_countOccurrences(script, callPattern) > 1) {
        result.warnings
            .add("Function '$funcName' may be recursive - ensure base case exists");
      }
    }
  }

  // Very large integer literals (`js_engine.rs:387-395`).
  for (final word in _splitWhitespace(script)) {
    if (word.length >= 15 && word.runes.every(_isAsciiDigit)) {
      result.warnings.add(
          'Very large numbers detected - ensure they fit within safe integer limits');
      break;
    }
  }

  // Excessive `.push(` (`js_engine.rs:397-403`).
  if (_countOccurrences(script, '.push(') > 50) {
    result.warnings.add(
        'Many array.push operations detected - consider optimizing for better performance');
  }
}

/// `validate_data_structures` (`js_engine.rs:406-489`).
void validateDataStructures(
  String script,
  JsValidationContext context,
  JsValidationResult result,
) {
  if (context.isProduction) {
    // Uninitialised state fields (`js_engine.rs:412-444`).
    const knownStateFields = {
      'last_action',
      'show_info',
      'counter',
      'balance',
      'transactions',
    };
    final stateFields = <String>[];
    for (final line in _rustLines(script)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('state.')) {
        final rest = trimmed.substring('state.'.length);
        final fieldEnd = _indexOfNonAlphaUnderscore(rest);
        final field = rest.substring(0, fieldEnd);
        if (field.isNotEmpty && !knownStateFields.contains(field)) {
          stateFields.add(field);
        }
      }
    }

    for (final field in stateFields) {
      final initPattern = '$field:';
      final initPattern2 = '$field =';
      if (!script.contains(initPattern) && !script.contains(initPattern2)) {
        result.warnings.add(
            "State field 'state.$field' may be undefined - ensure it's initialized in init()");
      }
    }

    // String concatenation inside loops (`js_engine.rs:447-480`).
    if ((script.contains('for (') || script.contains('for(')) &&
        script.contains('+') &&
        script.contains('{')) {
      var inLoop = false;
      var depth = 0;
      var concatCount = 0;
      for (final line in _rustLines(script)) {
        final trimmed = line.trim();
        if ((trimmed.startsWith('for (') || trimmed.startsWith('for(')) &&
            trimmed.contains('{')) {
          inLoop = true;
          depth = 1;
          concatCount = 0;
          continue;
        }
        if (inLoop) {
          depth += _countOccurrences(trimmed, '{');
          depth -= _countOccurrences(trimmed, '}');
          concatCount += _countOccurrences(trimmed, '.concat(');
          if (depth <= 0) {
            if (concatCount > 5) {
              result.warnings.add(
                  'String concatenation in loop detected - consider using array.join for better performance');
            }
            inLoop = false;
          }
        }
      }
    }
  }

  // Excessive `.push(` — pre-allocation hint (`js_engine.rs:482-488`).
  if (_countOccurrences(script, '.push(') > 100) {
    result.warnings.add(
        'Many array.push operations detected - consider pre-allocating arrays for better performance');
  }
}

/// `validate_ui_nodes` (`js_engine.rs:523-615`).
void validateUiNodes(String script, JsValidationResult result) {
  // Conditional UI expression missing type (`js_engine.rs:524-531`).
  for (final line in _rustLines(script)) {
    if ((line.contains('&& {') || line.contains('||{')) &&
        !line.contains('type')) {
      result.syntaxErrors.add(
          'Conditional UI expression missing type field - this will cause "UI node missing type" error');
    }
  }

  // Empty type (`js_engine.rs:533-546`).
  for (final line in _rustLines(script)) {
    if ((line.contains('type:') || line.contains('type :')) &&
        (line.contains('"type":""') ||
            line.contains('"type": ""') ||
            line.contains('type: ""') ||
            line.contains('type:""') ||
            line.contains("type: ''") ||
            line.contains("type:''"))) {
      result.syntaxErrors.add('UI node with empty type found');
    }
  }

  // Unknown type warning (`js_engine.rs:548-584`).
  const validTypes = [
    'column',
    'row',
    'section',
    'text',
    'button',
    'toggle',
    'text_field',
    'select',
    'image',
    'list',
    'paginated_list',
    'result_display',
    'table',
  ];
  for (final line in _rustLines(script)) {
    final idx = line.indexOf('type:');
    if (idx == -1) continue;
    final after = line.substring(idx + 'type:'.length);
    final trimmedPart = _trimStart(after);
    if (trimmedPart.isEmpty) continue;
    final firstCode = trimmedPart.codeUnitAt(0);
    int quote;
    if (firstCode == 34) {
      quote = 34; // "
    } else if (firstCode == 39) {
      quote = 39; // '
    } else {
      continue;
    }
    final rest = trimmedPart.substring(1);
    final end = rest.indexOf(String.fromCharCode(quote));
    if (end == -1) continue;
    final typeValue = rest.substring(0, end);
    if (typeValue.isNotEmpty && !validTypes.contains(typeValue)) {
      result.warnings.add(
          'Unknown UI node type: "$typeValue" - valid types are: ${validTypes.join(', ')}');
    }
  }

  // `return { ... }` block — node missing type (`js_engine.rs:586-614`).
  if (script.contains('return {') || script.contains('return{')) {
    var inReturn = false;
    var braceCount = 0;
    for (final line in _rustLines(script)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('return {') || trimmed.startsWith('return{')) {
        inReturn = true;
        braceCount = _countOccurrences(trimmed, '{') -
            _countOccurrences(trimmed, '}');
        continue;
      }
      if (inReturn) {
        braceCount += _countOccurrences(trimmed, '{');
        braceCount -= _countOccurrences(trimmed, '}');
        if (trimmed.contains('{') &&
            trimmed.contains('}') &&
            !trimmed.contains('type') &&
            (trimmed.contains('props') || trimmed.contains('children'))) {
          result.syntaxErrors.add('UI node missing type field');
        }
        if (braceCount <= 0) {
          inReturn = false;
        }
      }
    }
  }
}

/// `run_static_stages` (`js_engine.rs:617-634`). Runs all static (text-only)
/// validators in the SAME order as native so the first-surfacing error matches.
/// [context] is auto-detected via [defaultContext] when null (the `lint_js`
/// path).
JsValidationResult runStaticStages(
  String script,
  JsValidationContext? context,
) {
  final ctx = context ?? defaultContext(script);
  final result = freshResult(script);
  validateBasic(script, result);
  validateEventHandlers(script, result);
  validateSecurityPatterns(script, ctx, result);
  validateEsmFormat(script, result);
  validateIntl(script, result);
  validateIcpIntegration(script, ctx, result);
  validatePerformancePatterns(script, ctx, result);
  validateDataStructures(script, ctx, result);
  validateUiNodes(script, result);
  result.isValid = result.syntaxErrors.isEmpty;
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure-Dart helpers replicating Rust `str` / slice semantics exactly.
// ─────────────────────────────────────────────────────────────────────────────

/// Replicates Rust `str::lines()` (`js_engine.rs:33,492,etc.`): splits on `\n`
/// and `\r\n`, with the final line terminator optional. Verified against the
/// Rust reference for the edge cases: `""`→0, `"a"`→1, `"a\n"`→1, `"a\nb"`→2,
/// `"\n"`→1, `"\n\n"`→2.
List<String> _rustLines(String s) {
  if (s.isEmpty) return const <String>[];
  final lines = <String>[];
  final buf = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 10) {
      // `\n`
      lines.add(buf.toString());
      buf.clear();
      i++;
    } else if (c == 13 && i + 1 < s.length && s.codeUnitAt(i + 1) == 10) {
      // `\r\n`
      lines.add(buf.toString());
      buf.clear();
      i += 2;
    } else {
      buf.writeCharCode(c);
      i++;
    }
  }
  // The final line terminator is optional: if the string did NOT end in `\n`
  // (covers both lone `\n` and `\r\n` endings), the residual buffer is a line.
  if (s.codeUnitAt(s.length - 1) != 10) {
    lines.add(buf.toString());
  }
  return lines;
}

/// `is_ident_char` (`js_engine.rs:247-249`) — ASCII alphanumeric, `_`, or `$`.
bool _isIdentChar(int c) =>
    (c >= 48 && c <= 57) || // 0-9
    (c >= 65 && c <= 90) || // A-Z
    (c >= 97 && c <= 122) || // a-z
    c == 95 || // _
    c == 36; // $

/// ASCII alphanumeric or `_` (ESM boundary check, `js_engine.rs:499`).
bool _isAlphaNumberOrUnderscore(int c) =>
    (c >= 48 && c <= 57) ||
    (c >= 65 && c <= 90) ||
    (c >= 97 && c <= 122) ||
    c == 95;

bool _isAlphaNumericOrUnderscore(int c) => _isAlphaNumberOrUnderscore(c);

bool _isAsciiDigit(int c) => c >= 48 && c <= 57;

/// `dangerous_call_present` (`js_engine.rs:230-245`): true if [name] appears as
/// a call site (`name` optionally followed by whitespace then `(`) where the
/// character immediately before `name` is NOT an identifier character.
bool dangerousCallPresent(String script, String name) {
  var searchFrom = 0;
  while (true) {
    final start = script.indexOf(name, searchFrom);
    if (start == -1) return false;
    final precededByIdent = start > 0 && _isIdentChar(script.codeUnitAt(start - 1));
    if (!precededByIdent) {
      final rest = script.substring(start + name.length);
      if (_trimStart(rest).startsWith('(')) {
        return true;
      }
    }
    searchFrom = start + name.length;
  }
}

/// Rust `str::trim_start()` — strip leading ASCII/Unicode whitespace.
String _trimStart(String s) => s.replaceFirst(RegExp(r'^\s+'), '');

/// Rust `str::split_whitespace().collect()` — split on runs of whitespace,
/// dropping empties.
List<String> _splitWhitespace(String s) =>
    s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList(growable: false);

/// Rust `word.trim_matches(|c| c==','||c==';'||c==')'||c=='('||c=='"'||c=='\'')`
/// (`js_engine.rs:189-191`) — strip trailing punctuation from a URL token.
String _trimMatchesTrailing(String word) {
  var end = word.length;
  while (end > 0) {
    final c = word.codeUnitAt(end - 1);
    if (c == 44 || c == 59 || c == 41 || c == 40 || c == 34 || c == 39) {
      end--;
    } else {
      break;
    }
  }
  return word.substring(0, end);
}

/// Index of the first `"` (34) or `'` (39) in [s], or -1 (`js_engine.rs:261`).
int _findFirstQuote(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 34 || c == 39) return i;
  }
  return -1;
}

/// Index of the first char that is NOT (alphanumeric or `_`), or length
/// (`js_engine.rs:417-418`).
int _indexOfNonAlphaUnderscore(String s) {
  for (var i = 0; i < s.length; i++) {
    if (!_isAlphaNumberOrUnderscore(s.codeUnitAt(i))) return i;
  }
  return s.length;
}

/// Rust `name_part.rsplit([' ', '=']).next()` (`js_engine.rs:368`) — the token
/// after the last space or `=`.
String _lastTokenOnSpaceOrEquals(String s) {
  var lastIdx = -1;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 32 || c == 61) lastIdx = i; // space or '='
  }
  return lastIdx == -1 ? s : s.substring(lastIdx + 1);
}

/// Non-overlapping count of a LITERAL needle (mirrors Rust `str::matches(&str)
/// .count()`).
int _countOccurrences(String s, String needle) {
  if (needle.isEmpty) return 0;
  return RegExp(RegExp.escape(needle)).allMatches(s).length;
}
