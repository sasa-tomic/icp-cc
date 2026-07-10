/// Native (non-Web) probe for [ConnectivityService] (IH-1).
///
/// Selected by [connectivity_service.dart]'s conditional import on every
/// non-Web target. Probes the **actual** backend health endpoint
/// (`${AppConfig.apiEndpoint}/api/v1/health`) with a short HTTP GET, NOT a third
/// party like google.com — so "online" means the app's own backend is up.
///
/// Only the typed transport family (`SocketException` / `TimeoutException` /
/// `HttpException`) maps to offline, each logged loudly. A non-2xx health
/// response is logged and treated as offline. Any other error propagates
/// (fail-fast) — there is NO catch-all here. Native has no OS connectivity-changed
/// signal wired (we rely on the periodic timer), so [defaultConnectivityChangeSignal]
/// is `null`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../theme/app_design_system.dart';

/// Probes the real backend health endpoint. Returns `true` when it answers 2xx,
/// `false` on a genuine transport failure (typed, logged) or a non-2xx response.
Future<bool> defaultConnectivityProbe() async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = AppDurations.browseTimeout;
  try {
    final Uri uri = Uri.parse('${AppConfig.apiEndpoint}/api/v1/health');
    final HttpClientRequest request = await client.getUrl(uri);
    final HttpClientResponse response =
        await request.close().timeout(AppDurations.browseTimeout);
    final bool ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      debugPrint('ConnectivityService: backend health probe for $uri returned '
          'HTTP ${response.statusCode} — treating as offline.');
    }
    return ok;
  } on SocketException catch (e) {
    debugPrint('ConnectivityService: backend unreachable (transport): $e');
    return false;
  } on TimeoutException catch (e) {
    debugPrint('ConnectivityService: backend health probe timed out: $e');
    return false;
  } on HttpException catch (e) {
    debugPrint('ConnectivityService: backend HTTP error: $e');
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Native has no OS connectivity-changed signal wired here, so the periodic
/// timer in [ConnectivityService] drives re-checks. Always `null`.
Stream<void>? get defaultConnectivityChangeSignal => null;
