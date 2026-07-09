// R-3 WU-1 — Browser probe entrypoint for the QuickJS-on-Web primitive.
//
// This is NOT the production app entry (`lib/main.dart`). It is built ONLY for
// the WU-1 verification step:
//   flutter build web --target lib/web_probe_main.dart
//
// It is intentionally FLUTTER-FREE (no `WidgetsFlutterBinding` / `runApp`):
// the point of WU-1 is to prove the Dart→JS interop primitive, not to render
// UI. Avoiding the binding also avoids auto-registering the app's web plugins
// (e.g. the `passkeys` Corbado SDK, which would throw without its bundle.js —
// unrelated to R-3).
//
// The probe loads the vendored quickjs-emscripten bundle, runs
// [WebQuickJsEngine.runProbe], and publishes the result to the DOM so a
// headless browser harness (Playwright) can assert on it:
//   1. `document.title` = JSON of [QuickJsProbeResult] (polled by the harness).
//   2. A `<div id="probe-result">` appended to <body> with a human-readable
//      summary (visible when a human opens the built app).
//
// On any failure it sets `document.title` to `{"loaded":false,"error":...}` so
// the harness reports the failure loudly rather than hanging.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'rust/web/quickjs_engine.dart';

Future<void> main() async {
  QuickJsProbeResult result;
  try {
    final engine = await WebQuickJsEngine.bootstrap();
    result = await engine.runProbe();
    // engine.dispose() is a no-op: the loaded WASM module lives for the page
    // lifetime (it has no public dispose — see quickjs_engine.dart).
  } catch (e) {
    result = QuickJsProbeResult(
      loaded: false,
      version: '',
      evalResult: null,
      argRoundtrip: null,
      memoryLimitHalted: false,
      memoryLimitError: null,
      interruptHalted: false,
      interruptError: null,
      interruptElapsedMs: -1,
      dartClosureInterruptFired: false,
      error: e.toString(),
    );
  }

  _publishResult(jsonEncode(result.toJson()), result);
}

void _publishResult(String json, QuickJsProbeResult r) {
  // 1. document.title = JSON (the harness polls this).
  final doc = globalContext.getProperty<JSObject>('document'.toJS);
  doc.setProperty('title'.toJS, json.toJS);
  // 2. Append a <div id="probe-result"> with a human-readable summary.
  final div = doc.callMethod<JSObject>('createElement'.toJS, 'div'.toJS)
    ..setProperty('id'.toJS, 'probe-result'.toJS);
  final summary = StringBuffer()
    ..writeln('QuickJS-on-Web probe (R-3 WU-1)')
    ..writeln('loaded: ${r.loaded}  version: ${r.version}')
    ..writeln('eval 1+2 = ${r.evalResult}')
    ..writeln('arg.n*2 = ${r.argRoundtrip}')
    ..writeln('memory limit halted: ${r.memoryLimitHalted} (${r.memoryLimitError})')
    ..writeln('interrupt halted: ${r.interruptHalted} '
        'in ${r.interruptElapsedMs}ms (${r.interruptError})')
    ..writeln('dart-closure interrupt fired: ${r.dartClosureInterruptFired}');
  if (r.error != null) summary.writeln('ERROR: ${r.error}');
  div.setProperty('innerText'.toJS, summary.toString().toJS);
  final body = doc.getProperty<JSObject>('body'.toJS);
  body.callMethod('appendChild'.toJS, div);
}
