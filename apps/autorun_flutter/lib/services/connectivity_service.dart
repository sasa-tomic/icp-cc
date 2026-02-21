import 'dart:async';
import 'dart:io';

/// Service for monitoring network connectivity status.
///
/// Uses Socket connections to check actual internet reachability
/// rather than just network interface status.
class ConnectivityService {
  /// Host to check connectivity against
  static const String _connectivityHost = 'google.com';

  /// Port to check connectivity on
  static const int _connectivityPort = 80;

  /// Default timeout for connectivity checks
  static const Duration _defaultTimeout = Duration(seconds: 5);

  /// Default interval for periodic connectivity checks
  static const Duration _defaultCheckInterval = Duration(seconds: 30);

  final StreamController<bool> _isOnlineController =
      StreamController<bool>.broadcast();

  Timer? _periodicCheckTimer;
  bool _isDisposed = false;

  /// Stream of online status changes.
  ///
  /// Emits `true` when online, `false` when offline.
  /// This is a broadcast stream, so multiple listeners can subscribe.
  Stream<bool> get isOnline => _isOnlineController.stream;

  /// Current online status.
  ///
  /// Defaults to `true` (optimistic) until first check completes.
  bool get currentStatus => _currentStatus;
  bool _currentStatus = true;

  /// Checks connectivity by attempting to connect to a reliable host.
  ///
  /// Returns `true` if connection succeeds, `false` otherwise.
  /// Never throws - all exceptions are caught and result in `false`.
  Future<bool> checkConnectivity() async {
    if (_isDisposed) {
      return false;
    }

    bool isOnline = false;

    try {
      final socket = await Socket.connect(
        _connectivityHost,
        _connectivityPort,
        timeout: _defaultTimeout,
      );
      await socket.close();
      isOnline = true;
    } on SocketException {
      isOnline = false;
    } on TimeoutException {
      isOnline = false;
    } catch (e) {
      // Any other exception means offline
      isOnline = false;
    }

    if (!_isDisposed && _currentStatus != isOnline) {
      _currentStatus = isOnline;
      _isOnlineController.add(isOnline);
    }

    return isOnline;
  }

  /// Starts periodic connectivity checking.
  ///
  /// The service will check connectivity at the specified [interval]
  /// and emit status changes via [isOnline] stream.
  void startPeriodicCheck({Duration? interval}) {
    _periodicCheckTimer?.cancel();

    final checkInterval = interval ?? _defaultCheckInterval;

    // Emit current status first so listeners get immediate feedback
    if (!_isDisposed) {
      _isOnlineController.add(_currentStatus);
    }

    // Do an immediate check
    checkConnectivity();

    // Then check periodically
    _periodicCheckTimer = Timer.periodic(checkInterval, (_) {
      checkConnectivity();
    });
  }

  /// Stops periodic connectivity checking.
  void stopPeriodicCheck() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
  }

  /// Disposes the service and releases resources.
  ///
  /// After calling this method, the service should not be used.
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    stopPeriodicCheck();
    await _isOnlineController.close();
  }
}
