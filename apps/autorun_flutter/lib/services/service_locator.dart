import 'package:get_it/get_it.dart';

import 'icpay_service.dart';
import 'script_runner.dart';

/// Process-wide service locator.
///
/// Replaces ad-hoc static seams (e.g. the former
/// `DappsScreen.testBridgeOverride` mutable global) with a typed, testable
/// registry. Production calls [setupServiceLocator] once at boot before
/// `runApp`; tests register overrides via [registerTestScriptBridge] and tear
/// the registry down via [resetServiceLocator] so nothing leaks across runs.
final GetIt getIt = GetIt.instance;

/// Production service wiring. Called once from `main()` before `runApp`.
///
/// Deliberately does NOT register a [ScriptBridge] — production relies on the
/// real FFI bridge constructed inside `DappRunnerScreen`. Only integration tests
/// inject a canned [ScriptBridge] (via [registerTestScriptBridge]) so they can
/// drive the catalog→runner→canister flow with deterministic responses while
/// still exercising the real app boot.
void setupServiceLocator() {
  // ICPay client is a process-wide singleton so config is fetched once and
  // cached. Tests override it via `getIt.unregister<IcpayService>()` followed
  // by a test-double registration (mirroring registerTestScriptBridge).
  if (!getIt.isRegistered<IcpayService>()) {
    getIt.registerSingleton<IcpayService>(IcpayService());
  }
}

/// The optional test-only [ScriptBridge] override, or `null` in production.
///
/// `DappsScreen` consults this so a canned bridge installed by an integration
/// test propagates through the catalog→runner push. `null` when nothing is
/// registered → `DappRunnerScreen` builds its own real FFI bridge.
ScriptBridge? get scriptBridgeOverride =>
    getIt.isRegistered<ScriptBridge>() ? getIt<ScriptBridge>() : null;

/// Registers a test-only [ScriptBridge] override. Idempotent within a
/// registration scope (replaces any prior registration).
void registerTestScriptBridge(ScriptBridge bridge) {
  if (getIt.isRegistered<ScriptBridge>()) {
    getIt.unregister<ScriptBridge>();
  }
  getIt.registerSingleton<ScriptBridge>(bridge);
}

/// Clears the entire registry. Call in test `tearDown` so no override leaks
/// into subsequent tests or production paths.
Future<void> resetServiceLocator() => getIt.reset();
