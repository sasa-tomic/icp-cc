// R-3 WU-2/WU-3 — Browser parity-suite entrypoint for QuickJS-on-Web.
//
// This is NOT the production app entry (`lib/main.dart`). It is built ONLY for
// the parity verification step:
//   flutter build web --target=tool/web_probe_parity_main.dart
//
// It is Flutter-free (see `web_probe_main.dart` for the rationale): the point
// is to prove the Dart→JS engine primitive produces the SAME envelopes the
// native engine does, not to render UI. Avoiding the binding also avoids
// auto-registering the `passkeys` web plugin (its Corbado SDK throws without
// its bundle.js — unrelated to R-3).
//
// The probe loads the vendored quickjs-emscripten bundle, runs the jsExec +
// jsApp* golden-vector catalogues through the REAL [WebQuickJsEngine], and
// publishes a combined result to the DOM for the headless browser harness
// (`scripts/quickjs_web_probe/verify_parity.js`) to assert:
//   1. `document.title` = JSON of [ParityProbeResult].
//   2. A `<div id="parity-result">` with a human-readable summary.
//
// On any failure `allPassed` is false and each failing vector carries a
// `detail` string, so the harness reports the failure loudly.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:icp_autorun/rust/web/js_exec_golden_vectors.dart';
import 'package:icp_autorun/rust/web/js_app_golden_vectors.dart';
import 'package:icp_autorun/rust/web/js_validation_golden_vectors.dart';
import 'package:icp_autorun/rust/web/js_static_analysis.dart';
import 'package:icp_autorun/rust/web/quickjs_engine.dart';

Future<void> main() async {
  ParityProbeResult result;
  try {
    final engine = await WebQuickJsEngine.bootstrap();
    final jsExecChecks = _runJsExecVectors(engine);
    final jsAppChecks = _runJsAppVectors(engine);
    final jsValidationChecks = _runJsValidationVectors(engine);
    result = ParityProbeResult(
      loaded: true,
      version: engine.version,
      checks: <ParityCheck>[...jsExecChecks, ...jsAppChecks, ...jsValidationChecks],
    );
  } catch (e) {
    // A bootstrap failure is surfaced loudly (loaded=false, single check) so
    // the readiness/UI path renders a clear message rather than degrading.
    result = ParityProbeResult(
      loaded: false,
      version: '',
      checks: <ParityCheck>[
        ParityCheck(
          name: 'bootstrap',
          pass: false,
          detail: 'QuickJS bootstrap failed: $e',
        ),
      ],
    );
  }
  _publish(jsonEncode(result.toJson()), result);
}

List<ParityCheck> _runJsExecVectors(WebQuickJsEngine engine) {
  final checks = <ParityCheck>[];
  for (final v in jsExecGoldenVectors) {
    String detail = '';
    try {
      final out = engine.executeJsJson(v.script, jsonArg: v.jsonArg);
      final decoded = jsonDecode(out);
      if (decoded is! Map<String, dynamic>) {
        detail = 'envelope not an object: $out';
      } else if ((decoded['ok'] as bool?) != v.expectOk) {
        detail = "ok(${decoded['ok']}) != expected(${v.expectOk}): $out";
      } else {
        final fail = v.assertion(decoded);
        detail = fail ?? '';
      }
      checks.add(ParityCheck(
        name: 'jsExec/${v.name}',
        pass: detail.isEmpty,
        detail: detail.isEmpty ? out : detail,
      ));
    } catch (e) {
      checks.add(ParityCheck(
        name: 'jsExec/${v.name}',
        pass: false,
        detail: 'threw: $e',
      ));
    }
  }
  return checks;
}

List<ParityCheck> _runJsAppVectors(WebQuickJsEngine engine) {
  final checks = <ParityCheck>[];
  for (final v in jsAppGoldenVectors) {
    String detail = '';
    String out = '';
    try {
      final checkpoints = v.run(engine);
      out = jsonEncode(checkpoints);
      final fail = v.assertion(checkpoints);
      detail = fail ?? '';
    } catch (e) {
      detail = 'threw: $e';
    }
    checks.add(ParityCheck(
      name: 'jsApp/${v.name}',
      pass: detail.isEmpty,
      detail: detail.isEmpty ? out : detail,
    ));
  }
  return checks;
}

// R-3 WU-5 — runs each validate/lint vector through the FULL Web pipeline
// (pure-Dart static stages + the engine runtime stage), then asserts the
// resulting JsValidationResult + the lint envelope shape (the
// `lint_js_returns_json_shape` parity bar).
List<ParityCheck> _runJsValidationVectors(WebQuickJsEngine engine) {
  final checks = <ParityCheck>[];
  for (final v in jsValidationGoldenVectors) {
    String detail = '';
    try {
      final context = v.context ?? defaultContext(v.script);
      final result = runStaticStages(v.script, context);
      // runtime.rs:193-195 — only run the engine stage when static passes.
      if (result.isValid) {
        result.syntaxErrors.addAll(engine.validateRuntimeStage(v.script));
        result.isValid = result.syntaxErrors.isEmpty;
      }
      if (result.isValid != v.expectValid) {
        detail = 'isValid(${result.isValid}) != expected(${v.expectValid}); '
            'errors=${result.syntaxErrors}';
      } else {
        detail = v.assertion(result) ?? '';
      }
      // Also assert the lint envelope shape (`lint_js` keys present) — mirrors
      // the native `lint_js_returns_json_shape` test for every vector.
      if (detail.isEmpty) {
        final lintEnv = _lintEnvelope(result);
        for (final key in <String>['ok', 'errors', 'warnings', 'line_count']) {
          if (!lintEnv.containsKey(key)) {
            detail = 'lint envelope missing key "$key": $lintEnv';
            break;
          }
        }
        if (detail.isEmpty &&
            (lintEnv['line_count'] is! int ||
                lintEnv['character_count'] is! int)) {
          detail = 'lint envelope counts not ints: $lintEnv';
        }
      }
      checks.add(ParityCheck(
        name: 'jsValidation/${v.name}',
        pass: detail.isEmpty,
        detail: detail.isEmpty ? jsonEncode(_validateEnvelope(result)) : detail,
      ));
    } catch (e) {
      checks.add(ParityCheck(
        name: 'jsValidation/${v.name}',
        pass: false,
        detail: 'threw: $e',
      ));
    }
  }
  return checks;
}

/// The `icp_js_validate_comprehensive` FFI envelope (`ffi.rs:366-373`).
Map<String, Object?> _validateEnvelope(JsValidationResult r) =>
    <String, Object?>{
      'is_valid': r.isValid,
      'syntax_errors': r.syntaxErrors,
      'warnings': r.warnings,
      'line_count': r.lineCount,
      'character_count': r.characterCount,
    };

/// The `lint_js` envelope (`runtime.rs:257-267`).
Map<String, Object?> _lintEnvelope(JsValidationResult r) =>
    <String, Object?>{
      'ok': r.isValid,
      'errors': r.syntaxErrors
          .map((e) => <String, Object?>{'message': e})
          .toList(growable: false),
      'warnings': r.warnings,
      'line_count': r.lineCount,
      'character_count': r.characterCount,
    };

void _publish(String json, ParityProbeResult r) {
  final doc = globalContext.getProperty<JSObject>('document'.toJS);
  doc.setProperty('title'.toJS, json.toJS);
  final div = doc.callMethod<JSObject>('createElement'.toJS, 'div'.toJS)
    ..setProperty('id'.toJS, 'parity-result'.toJS);
  final summary = StringBuffer()
    ..writeln('QuickJS-on-Web parity probe (R-3 WU-2/WU-3)')
    ..writeln('loaded: ${r.loaded}  version: ${r.version}')
    ..writeln('allPassed: ${r.allPassed}  '
        '(${r.checks.where((c) => c.pass).length}/${r.checks.length} vectors)');
  for (final c in r.checks) {
    summary.writeln('  [${c.pass ? "PASS" : "FAIL"}] ${c.name}');
    if (!c.pass) summary.writeln('        ${c.detail}');
  }
  div.setProperty('innerText'.toJS, summary.toString().toJS);
  doc.getProperty<JSObject>('body'.toJS).callMethod('appendChild'.toJS, div);
}

// ── pure-Dart result types (also asserted by the VM contract test) ──────────

class ParityCheck {
  ParityCheck({required this.name, required this.pass, required this.detail});
  final String name;
  final bool pass;
  final String detail;
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'pass': pass,
        if (detail.isNotEmpty) 'detail': detail,
      };
}

class ParityProbeResult {
  ParityProbeResult({
    required this.loaded,
    required this.version,
    required this.checks,
  });
  final bool loaded;
  final String version;
  final List<ParityCheck> checks;

  bool get allPassed => loaded && checks.every((c) => c.pass);

  Map<String, Object?> toJson() => <String, Object?>{
        'loaded': loaded,
        'version': version,
        'allPassed': allPassed,
        'checks': checks.map((c) => c.toJson()).toList(),
      };
}
