import 'package:icp_autorun/services/connectivity_service.dart';

/// A [ConnectivityService] that performs no network I/O.
///
/// Inject this into [ConnectivityScope] in widget tests (via its `service`
/// parameter) to avoid the real service's `Socket.connect`, whose 5s timeout
/// is an uncancellable timer that leaks into the test's FakeAsync and trips
/// the `!timersPending` invariant.
class FakeConnectivityService extends ConnectivityService {
  @override
  Future<bool> checkConnectivity() async => true;
}
