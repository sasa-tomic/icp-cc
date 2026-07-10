/// Web (browser) probe for [ConnectivityService] (IH-1).
///
/// Selected by [connectivity_service.dart]'s conditional import when
/// `dart.library.html` is available (the browser). Reads the browser's
/// `navigator.onLine` flag — no network probe, no `dart:io` `Socket` (which
/// throws `UnsupportedError` in a browser and previously left every Web user
/// under a permanent false "You're offline" banner even though
/// `navigator.onLine` was `true`).
///
/// [defaultConnectivityChangeSignal] bridges the browser's `online`/`offline`
/// DOM events so [ConnectivityService.startPeriodicCheck] can re-probe
/// instantly on a transition instead of waiting up to one poll interval.
///
/// Uses `dart:js_interop` + `dart:js_interop_unsafe` via `globalContext` — the
/// established Web-interop style elsewhere in this package (e.g.
/// `lib/rust/web/*`). This file is Web-only and is never selected for the Dart
/// VM target, so the rest of the package stays `dart:io`-free on Web.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Returns the browser's current online status. Browsers keep this flag current
/// across Wi-Fi/Ethernet/airplane-mode changes. In a browser `globalContext` is
/// `window`, so `navigator` is reachable directly off it.
Future<bool> defaultConnectivityProbe() async {
  final JSObject navigator =
      globalContext.getProperty<JSObject>('navigator'.toJS);
  return navigator.getProperty<JSBoolean>('onLine'.toJS).toDart;
}

Stream<void>? _changeSignal;

/// A broadcast signal that fires whenever the browser dispatches `online` or
/// `offline`. Lazily built once and cached so repeated start/stop cycles share
/// a single pair of DOM-event subscriptions. `null` is never returned on Web.
Stream<void>? get defaultConnectivityChangeSignal {
  final Stream<void>? cached = _changeSignal;
  if (cached != null) {
    return cached;
  }
  // Bridge the two DOM events into one void change signal. `globalContext` is
  // `window` in a browser, so `addEventListener` is reachable off it.
  final StreamController<void> controller = StreamController<void>.broadcast();
  final JSFunction handler = (() {
    controller.add(null);
  }).toJS;
  globalContext.callMethod<JSAny?>('addEventListener'.toJS, 'online'.toJS, handler);
  globalContext.callMethod<JSAny?>('addEventListener'.toJS, 'offline'.toJS, handler);
  _changeSignal = controller.stream;
  return _changeSignal;
}
