import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../services/offline_banner_dismiss_service.dart';

/// Provides connectivity state to descendant widgets.
///
/// Use [ConnectivityScope.of] to access the connectivity state.
/// The scope manages a [ConnectivityService] and [OfflineBannerDismissService]
/// and provides [isOnline] state and banner visibility logic.
class ConnectivityScope extends StatefulWidget {
  /// Creates a connectivity scope.
  ///
  /// Pass [service] to inject a custom [ConnectivityService] (e.g. a no-I/O
  /// fake in widget tests; the real service performs an uncancellable
  /// `Socket.connect` whose 5s timeout leaks a pending timer under FakeAsync).
  const ConnectivityScope({
    super.key,
    required this.child,
    this.service,
  });

  /// The child widget to wrap.
  final Widget child;

  /// Optional injected connectivity service.
  ///
  /// When null (the default in production), the scope creates its own
  /// [ConnectivityService].
  final ConnectivityService? service;

  /// Gets the connectivity state from the nearest [ConnectivityScope].
  ///
  /// Set [listen] to false to get the state without rebuilding on changes.
  static ConnectivityState of(BuildContext context, {bool listen = true}) {
    if (listen) {
      return context
          .dependOnInheritedWidgetOfExactType<_ConnectivityInherited>()!
          .state;
    }
    return context
        .findAncestorWidgetOfExactType<_ConnectivityInherited>()!
        .state;
  }

  @override
  State<ConnectivityScope> createState() => ConnectivityState();
}

/// The state for [ConnectivityScope].
///
/// Provides access to:
/// - [isOnline]: Current connectivity status
/// - [showBanner]: Whether the offline banner should be shown
/// - [dismissBanner]: Dismiss the banner (hides for 1 hour)
class ConnectivityState extends State<ConnectivityScope> {
  late final ConnectivityService _connectivityService;
  late final OfflineBannerDismissService _dismissService;

  bool _isOnline = true;
  bool _showBanner = false;
  StreamSubscription<bool>? _subscription;

  /// Current online status.
  bool get isOnline => _isOnline;

  /// Whether the offline banner should be shown.
  ///
  /// Returns true when offline AND the banner hasn't been recently dismissed.
  bool get showBanner => _showBanner && !_isOnline;

  @override
  void initState() {
    super.initState();
    _connectivityService = widget.service ?? ConnectivityService();
    _dismissService = OfflineBannerDismissService();
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    // Check if banner was previously dismissed
    final shouldShow = await _dismissService.shouldShowBanner();
    if (mounted) {
      setState(() {
        _showBanner = shouldShow;
      });
    }

    // Subscribe to connectivity changes
    _subscription = _connectivityService.isOnline.listen((isOnline) {
      if (mounted && _isOnline != isOnline) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });

    // Start periodic connectivity checking
    _connectivityService.startPeriodicCheck();
  }

  /// Dismisses the offline banner for 1 hour.
  Future<void> dismissBanner() async {
    await _dismissService.dismissBanner();
    if (mounted) {
      setState(() {
        _showBanner = false;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _connectivityService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ConnectivityInherited(
      state: this,
      child: widget.child,
    );
  }
}

/// Inherited widget that provides [ConnectivityState] to descendants.
class _ConnectivityInherited extends InheritedWidget {
  const _ConnectivityInherited({
    required this.state,
    required super.child,
  });

  final ConnectivityState state;

  @override
  bool updateShouldNotify(_ConnectivityInherited oldWidget) {
    return state._isOnline != oldWidget.state._isOnline ||
        state._showBanner != oldWidget.state._showBanner;
  }
}
