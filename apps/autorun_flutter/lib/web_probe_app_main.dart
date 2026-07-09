// R-3 WU-4 — Production-path probe for QuickJS-on-Web.
//
// This is NOT the production app entry (`lib/main.dart`). It is built ONLY for
// the WU-4 verification step:
//   flutter build web --target=lib/web_probe_app_main.dart
//
// Unlike the parity probe (WU-2/WU-3, which drives the raw WebQuickJsEngine),
// THIS probe exercises the REAL production script-execution stack end-to-end:
//   probeQuickJsReadiness()  (the readiness gate)
//     -> RustScriptBridge(RustBridgeLoader())  (the bridge the UI constructs)
//       -> ScriptAppRuntime  (the production host: init/view/update)
// It runs the shipped `lib/examples/01_hello_world.js` init→view→update through
// that stack and publishes the result for the headless browser harness
// (`scripts/quickjs_web_probe/verify_app.js`).
//
// Proving this path is the WU-4 bar: "a real script actually runs in the built
// web app". (Driving the full Flutter UI headlessly needs the passkeys Corbado
// SDK + a real display; this Flutter-free entrypoint isolates the R-3 path.)
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'rust/native_bridge.dart';
import 'rust/web/js_app_golden_vectors.dart' show ScriptLifecycles;
import 'services/script_runner.dart';

Future<void> main() async {
  final checks = <_AppCheck>[];
  // The readiness gate the production host (ScriptAppHost._boot) runs first.
  final readiness = await probeQuickJsReadiness();
  if (readiness is QuickJsUnavailable) {
    checks.add(_AppCheck('readiness', false,
        'QuickJS engine unavailable: ${readiness.reason} / ${readiness.detail}'));
    _publish(_AppResult(false, checks));
    return;
  }
  checks.add(_AppCheck('readiness', true, 'QuickJsReady'));

  // The EXACT production host the UI constructs (script_app_host.dart /
  // scripts_screen.dart build this same RustScriptBridge).
  final runtime = ScriptAppRuntime(RustScriptBridge(const RustBridgeLoader()));
  const script = ScriptLifecycles.helloWorld;

  try {
    // init() -> {ok, state:{count:0,name:""}}
    final initOut = await runtime.init(script: script);
    final initState = initOut['state'] as Map<String, dynamic>;
    checks.add(_AppCheck(
        'init',
        initState['count'] == 0 && initState['name'] == '',
        'state=$initState'));

    // view(state) -> {ok, ui:{type:"column", children:[{text:"Hello, world!"},...]}}
    final viewOut =
        await runtime.view(script: script, state: initState);
    final ui = viewOut['ui'] as Map<String, dynamic>;
    final greeting = _firstText(ui);
    checks.add(_AppCheck(
        'view',
        ui['type'] == 'column' && greeting == 'Hello, world!',
        'ui.type=${ui['type']} greeting=$greeting'));

    // update({type:inc}) -> state.count = 1
    final incOut = await runtime.update(
        script: script,
        msg: <String, dynamic>{'type': 'inc'},
        state: initState);
    final incState = incOut['state'] as Map<String, dynamic>;
    checks.add(_AppCheck('update_inc', incState['count'] == 1,
        'count=${incState['count']}'));

    // update({type:set_name,value:Web}) -> name=Web, then view -> "Hello, Web!"
    final nameOut = await runtime.update(
        script: script,
        msg: <String, dynamic>{'type': 'set_name', 'value': 'Web'},
        state: incState);
    final nameState = nameOut['state'] as Map<String, dynamic>;
    final namedView =
        await runtime.view(script: script, state: nameState);
    final namedGreeting =
        _firstText(namedView['ui'] as Map<String, dynamic>);
    checks.add(_AppCheck(
        'update_set_name_and_re_view',
        nameState['name'] == 'Web' && namedGreeting == 'Hello, Web!',
        'name=${nameState['name']} greeting=$namedGreeting'));
  } catch (e, st) {
    checks.add(_AppCheck('production_path', false, 'threw: $e\n$st'));
  }

  _publish(_AppResult(checks.every((c) => c.pass), checks));
}

String? _firstText(Map<String, dynamic> ui) {
  final children = ui['children'];
  if (children is List) {
    for (final child in children) {
      if (child is Map && child['type'] == 'text') {
        final props = child['props'];
        if (props is Map) return props['text']?.toString();
      }
    }
  }
  return null;
}

void _publish(_AppResult r) {
  final json = jsonEncode(r.toJson());
  final doc = globalContext.getProperty<JSObject>('document'.toJS);
  doc.setProperty('title'.toJS, json.toJS);
  final div = doc.callMethod<JSObject>('createElement'.toJS, 'div'.toJS)
    ..setProperty('id'.toJS, 'app-result'.toJS);
  final sb = StringBuffer()
    ..writeln('QuickJS-on-Web PRODUCTION-path probe (R-3 WU-4)')
    ..writeln('allPassed: ${r.allPassed}');
  for (final c in r.checks) {
    sb.writeln('  [${c.pass ? "PASS" : "FAIL"}] ${c.name}: ${c.detail}');
  }
  div.setProperty('innerText'.toJS, sb.toString().toJS);
  doc.getProperty<JSObject>('body'.toJS).callMethod('appendChild'.toJS, div);
}

class _AppCheck {
  _AppCheck(this.name, this.pass, this.detail);
  final String name;
  final bool pass;
  final String detail;
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'pass': pass,
        'detail': detail,
      };
}

class _AppResult {
  _AppResult(this.allPassed, this.checks);
  final bool allPassed;
  final List<_AppCheck> checks;
  Map<String, Object?> toJson() => <String, Object?>{
        'allPassed': allPassed,
        'checks': checks.map((c) => c.toJson()).toList(),
      };
}
