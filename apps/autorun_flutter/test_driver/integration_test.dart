import 'package:integration_test/integration_test_driver.dart';

// Standard flutter_driver adapter for integration_test on non-VM surfaces
// (Web via `flutter drive -d chrome`). Boots the integration-test binding in
// the app under test and bridges it to flutter_driver over the service
// protocol. No app logic lives here.
//
// NOTE: the Tier-2 web real-app path (`flutter drive` web) is currently
// BLOCKED on Flutter 3.38.3 (integration_test-on-web unsupported — see
// integration_test/e2e/web_drive_smoke_test.dart header). This adapter is kept
// so the path works unchanged once Flutter ships that support.
Future<void> main() => integrationDriver();
