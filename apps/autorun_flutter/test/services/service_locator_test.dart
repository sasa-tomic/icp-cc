import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/services/service_locator.dart';

/// A trivial [ScriptBridge] stand-in so tests can register a concrete instance
/// without exercising the real FFI canister transport.
class _FakeScriptBridge implements ScriptBridge {
  const _FakeScriptBridge();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  // Ensure a clean registry between tests — the locator is process-wide.
  tearDown(resetServiceLocator);

  test('scriptBridgeOverride is null when nothing is registered (production)',
      () {
    setupServiceLocator();
    expect(scriptBridgeOverride, isNull,
        reason: 'Production must NOT install a ScriptBridge — DappRunnerScreen '
            'builds its own real FFI bridge when the override is null.');
  });

  test('registerTestScriptBridge exposes the bridge through the locator', () {
    const bridge = _FakeScriptBridge();
    registerTestScriptBridge(bridge);
    expect(identical(scriptBridgeOverride, bridge), isTrue);
  });

  test('registerTestScriptBridge is idempotent (replaces prior registration)',
      () {
    const first = _FakeScriptBridge();
    const second = _FakeScriptBridge();
    registerTestScriptBridge(first);
    registerTestScriptBridge(second);
    expect(identical(scriptBridgeOverride, second), isTrue,
        reason: 'A second registration must replace the first, not throw.');
  });

  test('resetServiceLocator clears the override so it cannot leak into prod',
      () async {
    registerTestScriptBridge(const _FakeScriptBridge());
    expect(scriptBridgeOverride, isNotNull);
    await resetServiceLocator();
    expect(scriptBridgeOverride, isNull,
        reason: 'tearDown must restore the production (null) state.');
  });
}
