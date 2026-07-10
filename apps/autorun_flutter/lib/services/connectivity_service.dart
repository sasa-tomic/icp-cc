/// Monitors reachability of the app's backend (IH-1, UXR-2/AUD-4/AUD-11).
///
/// Pure-Dart facade split via a **conditional import** — exactly mirroring the
/// `json_store.dart` / `native_bridge.dart` pattern. This file imports NO
/// `dart:io` and NO `dart:html`, so it compiles cleanly on every target:
///
///   import 'connectivity_service_io.dart'
///       if (dart.library.html) 'connectivity_service_web.dart' as platform;
///
/// Only the platform **probe** differs; the stream / timer / dispose logic is
/// shared here (DRY). See [ConnectivityService] for the contract.
///
/// ## Why this replaced the old `Socket.connect('google.com', 80)`
/// - **Web** (`dart:io` Socket throws `UnsupportedError` in a browser) used to
///   be swallowed by a catch-all → `isOnline=false` → every Web user saw a
///   permanent false "You're offline" banner. The Web probe now reads
///   `window.navigator.onLine` + the `online`/`offline` DOM events.
/// - **Native** used to probe a third party (google.com); a backend outage
///   showed "online" while a google-blocked-but-backend-reachable network
///   showed "offline". The native probe now hits the **actual** backend health
///   endpoint (`${AppConfig.apiEndpoint}/api/v1/health`).
/// - The forbidden generic `catch (e)` is gone: only typed transport errors map
///   to offline, logged loudly with the status / cause.
library;

import 'dart:async';

// Conditional platform probe: native → HTTP health GET (dart:io); web →
// navigator.onLine + DOM events (dart:js_interop). This facade stays
// dart:io/html-free so it compiles on every target.
import 'connectivity_service_io.dart'
    if (dart.library.html) 'connectivity_service_web.dart' as platform;

/// Active reachability probe: returns `true` when the backend is reachable and
/// healthy, `false` on a genuine transport failure. Injected so the shared
/// [ConnectivityService] logic is unit-testable without real I/O.
typedef ConnectivityProbe = Future<bool> Function();

/// Service monitoring reachability of the app's backend.
///
/// Emits transitions on [isOnline] only when the status actually changes.
/// Defaults come from the conditional import: [ConnectivityProbe] probes the
/// real backend (native) or `navigator.onLine` (web); the optional [onChange]
/// signal is the browser's `online`/`offline` DOM events (web) or `null`
/// (native, which relies on the periodic timer).
class ConnectivityService {
  /// Creates a connectivity service.
  ///
  /// Pass [probe] / [onChange] to inject deterministic fakes in tests. In
  /// production, omit both and the platform defaults are used.
  ConnectivityService({ConnectivityProbe? probe, Stream<void>? onChange})
      : _probe = probe ?? platform.defaultConnectivityProbe,
        _onChange = onChange ?? platform.defaultConnectivityChangeSignal;

  final ConnectivityProbe _probe;
  final Stream<void>? _onChange;

  final StreamController<bool> _isOnlineController =
      StreamController<bool>.broadcast();
  Timer? _periodicCheckTimer;
  StreamSubscription<void>? _onChangeSub;
  bool _isDisposed = false;

  /// Default interval for periodic connectivity checks.
  static const Duration defaultCheckInterval = Duration(seconds: 30);

  /// Stream of online status changes.
  ///
  /// Emits `true` when online, `false` when offline. Broadcast, so multiple
  /// listeners can subscribe.
  Stream<bool> get isOnline => _isOnlineController.stream;

  /// Current online status. Defaults to `true` (optimistic) until the first
  /// probe completes.
  bool get currentStatus => _currentStatus;
  bool _currentStatus = true;

  /// Runs one reachability probe and, on a status change, emits the new value
  /// on [isOnline]. Returns the probed status.
  ///
  /// The platform probe is responsible for mapping genuine transport failures
  /// (typed: `SocketException` / `TimeoutException` / `HttpException`) to
  /// `false` with a loud log; this method does NOT swallow errors.
  Future<bool> checkConnectivity() async {
    if (_isDisposed) {
      return false;
    }

    final bool next = await _probe();

    if (!_isDisposed && _currentStatus != next) {
      _currentStatus = next;
      _isOnlineController.add(next);
    }

    return next;
  }

  /// Starts periodic connectivity checking.
  ///
  /// Emits the current status immediately, runs one probe at once, then re-probes
  /// every [interval] (default [defaultCheckInterval]). On Web, the browser's
  /// `online`/`offline` events also trigger an immediate re-probe so a
  /// transition shows up instantly instead of after up to one interval.
  void startPeriodicCheck({Duration? interval}) {
    _periodicCheckTimer?.cancel();
    _onChangeSub?.cancel();

    final Duration checkInterval = interval ?? defaultCheckInterval;

    if (!_isDisposed) {
      _isOnlineController.add(_currentStatus);
    }

    checkConnectivity();

    _periodicCheckTimer =
        Timer.periodic(checkInterval, (_) => checkConnectivity());

    final Stream<void>? change = _onChange;
    if (change != null && !_isDisposed) {
      _onChangeSub = change.listen((_) => checkConnectivity());
    }
  }

  /// Stops periodic connectivity checking and cancels any change-signal
  /// subscription.
  void stopPeriodicCheck() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    _onChangeSub?.cancel();
    _onChangeSub = null;
  }

  /// Disposes the service and releases resources.
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    stopPeriodicCheck();
    await _isOnlineController.close();
  }
}
