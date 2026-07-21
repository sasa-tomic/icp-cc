// WEB-1 — Passkey-on-Web PoC + production verification probe.
//
// This is NOT the production app entry (`lib/main.dart`). It is built ONLY for
// the WEB-1 passkey-on-Web e2e verification:
//   flutter build web --target=tool/web_probe_passkey_main.dart
//
// WHY THIS EXISTS
//
// Flutter Web's a11y semantics tree (`flt-semantics`) cannot be enabled
// headlessly (see docs/OPEN_ISSUES.md #WEB-1). That blocks DOM-based
// Playwright assertions against the full Flutter UI. But the WebAuthn
// *browser API itself* (`navigator.credentials.create` / `.get`) works
// perfectly under Playwright 1.61+'s modern `browserContext.credentials`
// virtual authenticator. So this probe isolates the passkey flow end-to-end
// against the REAL Flutter Web bundle (canvaskit, real pure-Dart crypto,
// real backend) and publishes the result to `document.title` + a `<div>` —
// the same pattern the existing R-3 / R-3b probes (`tool/web_probe_*`)
// already use. The Playwright spec reads the JSON and asserts.
//
// The probe drives the REAL production code paths:
//   1. `KeypairGenerator.generate(algorithm: ed25519)` — real Ed25519 via
//      the pure-Dart Web impl (R-2 parity). No FFI on Web.
//   2. `MarketplaceOpenApiService.registerAccount(...)` — real signed
//      POST /api/v1/accounts against the live backend.
//   3. `PasskeyService().registerPasskey(...)` — the SAME method the
//      PasskeyManagementScreen's "Add Passkey" FAB calls. This invokes the
//      `passkeys` package's `PasskeyAuthenticator.register`, which calls
//      `navigator.credentials.create` in the browser. The virtual
//      authenticator installed by Playwright satisfies the call headlessly.
//   4. `PasskeyService().listPasskeys(accountId)` — confirms the passkey
//      landed in the backend (defense-in-depth: proves the full
//      register/start → WebAuthn → register/finish → list round-trip).
//
// NEGATIVE PATH
//
// When the env var `WEB_PASSKEY_PROBE_EXPECT_FAILURE=1` is set (baked via
// --dart-define), the probe expects the WebAuthn call to FAIL and reports
// a step result accordingly. The Playwright spec uses this to assert the
// loud-actionable-error path when no virtual authenticator is installed.
//
// Output format (JSON, single line, published to document.title):
//
//   {"allPassed":true,"phase":"complete","checks":[{"name":"...","pass":true,
//    "detail":"..."},...],"accountId":"...","username":"...","passkeyId":"...",
//    "rpId":"...","origin":"..."}
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/utils/keypair_generator.dart';

const bool _kExpectFailureCompiled =
    bool.fromEnvironment('WEB_PASSKEY_PROBE_EXPECT_FAILURE', defaultValue: false);

/// Runtime override: when the page is loaded with `?expectFailure=1` the probe
/// flips into negative-path mode without a rebuild. The compile-time define
/// above remains as a build-time default for CI that wants to ship a
/// negative-only bundle.
bool get _kExpectFailure {
  if (_kExpectFailureCompiled) return true;
  try {
    final loc = globalContext.getProperty<JSObject>('location'.toJS);
    final search = loc.getProperty<JSString>('search'.toJS).toDart;
    return search.contains('expectFailure=1') ||
        search.contains('expectFailure=true');
  } catch (_) {
    return false;
  }
}

Future<void> main() async {
  final checks = <_Check>[];
  try {
    await _run(checks);
  } catch (e, st) {
    checks.add(_Check('uncaught', false, '$e\n$st'));
  }
  // If we're expecting failure, flip the verdict: at least one step must have
  // failed LOUDLY with a recognizable WebAuthn error (TimeoutException counts
  // — see the timeout guard in `_run` for why headless Chromium without a
  // virtual authenticator hangs forever).
  var allPassed = checks.every((c) => c.pass);
  if (_kExpectFailure) {
    final loudFail = checks.any((c) =>
        !c.pass && (c.detail.contains('WebAuthn') ||
            c.detail.contains('NotAllowed') ||
            c.detail.contains('SecurityError') ||
            c.detail.contains('PasskeyException') ||
            c.detail.contains('TimeoutException')));
    allPassed = loudFail;
    checks.add(_Check('expect_failure_path', loudFail,
        loudFail ? 'saw expected WebAuthn failure' : 'no loud WebAuthn failure observed'));
  }
  _publish(_Result(
    allPassed: allPassed,
    phase: _kExpectFailure ? 'expect_failure' : 'complete',
    checks: checks,
    apiEndpoint: AppConfig.apiEndpoint,
    rpOrigin: _rpOrigin(),
  ));
}

Future<void> _run(List<_Check> checks) async {
  // Generate a unique username so this run can be torn down cleanly and
  // never collides with a prior run.
  final username = 'e2eweb${DateTime.now().millisecondsSinceEpoch}';
  final displayName = 'E2E Web Passkey Probe';
  checks.add(_Check('username_chosen', true, username));

  // 1. Keypair generation (real Ed25519 via pure-Dart Web impl).
  final ProfileKeypair keypair;
  try {
    keypair = await KeypairGenerator.generate(
      algorithm: KeyAlgorithm.ed25519,
      label: 'E2E Web Passkey Probe',
    );
    checks.add(_Check('keypair', keypair.publicKey.isNotEmpty,
        'pubkey=${keypair.publicKey.substring(0, 12)}… principal=${keypair.principal}'));
  } catch (e, st) {
    checks.add(_Check('keypair', false, '$e\n$st'));
    return;
  }

  // 2. Account registration (signed POST /api/v1/accounts).
  final Account account;
  try {
    final marketplace = MarketplaceOpenApiService();
    final controller = AccountController(
      marketplaceService: marketplace,
      profileController: null,
    );
    account = await controller.registerAccount(
      keypair: keypair,
      username: username,
      displayName: displayName,
    );
    checks.add(_Check('register_account', account.id.isNotEmpty,
        'id=${account.id} username=${account.username}'));
  } catch (e, st) {
    checks.add(_Check('register_account', false, '$e\n$st'));
    return;
  }

  // 3. Passkey registration — the heart of WEB-1. This calls
  //    `PasskeyService().registerPasskey(...)`, which:
  //      a. POSTs /passkey/register/start (signed) → gets WebAuthn options
  //      b. Calls `NativePasskeyAuthenticator.register(options)` →
  //         `navigator.credentials.create(options)` in the browser
  //      c. POSTs /passkey/register/finish with the credential → backend
  //         stores it under account_id
  //    The virtual authenticator installed by Playwright satisfies step (b).
  PasskeyRegistrationResult? registration;
  try {
    // Keypair generation above already triggered the Web impl selection via
    // the conditional-import split in `package:icp_autorun/rust/native_bridge.dart`
    // — no separate init step is needed on Web.
    //
    // Bound the WebAuthn round-trip with an explicit timeout. On the NEGATIVE
    // path (no virtual authenticator), `navigator.credentials.create` does NOT
    // return — Chromium pops a UI affordance that headless mode never clears.
    // Without this bound the probe would hang forever; the loud-timeout
    // failure IS the negative-path signal the harness asserts on.
    registration = await PasskeyService().registerPasskey(
      keypair: keypair,
      accountId: account.id,
      username: account.username,
      deviceName: 'E2E Virtual Authenticator',
    ).timeout(const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
            'WebAuthn navigator.credentials.create did not complete within 20s '
            '(expected when no virtual authenticator is installed)'));
    checks.add(_Check('register_passkey', registration.id.isNotEmpty,
        'passkeyId=${registration.id} createdAt=${registration.createdAt}'));
  } catch (e, st) {
    // EXPECT-FAILURE mode: record the failure loudly with its full type +
    // message. The probe continues so we can also report whether the
    // backend list endpoint sees zero passkeys (defense-in-depth: nothing
    // half-landed).
    checks.add(_Check('register_passkey', false,
        '${e.runtimeType}: $e\n$st'));
    if (!_kExpectFailure) return;
  }

  // 4. Backend verification — list passkeys for the account. Proves the
  //    full round-trip landed; not just the local return value.
  try {
    final passkeys = await PasskeyService().listPasskeys(account.id);
    final count = passkeys.length;
    final match = registration?.id != null &&
        passkeys.any((p) => p.id == registration!.id);
    checks.add(_Check('list_passkeys',
        _kExpectFailure ? count == 0 : match,
        'count=$count expectedMatch=$match ids=${passkeys.map((p) => p.id).join(',')}'));
  } catch (e, st) {
    checks.add(_Check('list_passkeys', false, '${e.runtimeType}: $e\n$st'));
  }
}

/// The browser origin, surfaced to the harness for diagnostics.
String _rpOrigin() {
  try {
    final loc = globalContext.getProperty<JSObject>('location'.toJS);
    final href = loc.getProperty<JSString>('href'.toJS).toDart;
    return href;
  } catch (_) {
    return '<unknown>';
  }
}

void _publish(_Result r) {
  final json = jsonEncode(r.toJson());
  final doc = globalContext.getProperty<JSObject>('document'.toJS);
  doc.setProperty('title'.toJS, json.toJS);
  final div = doc.callMethod<JSObject>('createElement'.toJS, 'div'.toJS)
    ..setProperty('id'.toJS, 'passkey-result'.toJS);
  final sb = StringBuffer()
    ..writeln('WEB-1 Passkey-on-Web probe')
    ..writeln('phase: ${r.phase}')
    ..writeln('allPassed: ${r.allPassed}')
    ..writeln('apiEndpoint: ${r.apiEndpoint}')
    ..writeln('origin: ${r.rpOrigin}')
    ..writeln('checks:');
  for (final c in r.checks) {
    sb.writeln('  [${c.pass ? "PASS" : "FAIL"}] ${c.name}: ${c.detail}');
  }
  div.setProperty('innerText'.toJS, sb.toString().toJS);
  doc.getProperty<JSObject>('body'.toJS).callMethod('appendChild'.toJS, div);
  // Also console.log so the harness sees a clean line in the browser console.
  final console = globalContext.getProperty<JSObject>('console'.toJS);
  console.callMethod('log'.toJS, 'WEB-1 probe result: $json'.toJS);
}

class _Check {
  _Check(this.name, this.pass, this.detail);
  final String name;
  final bool pass;
  final String detail;
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'pass': pass,
        'detail': detail,
      };
}

class _Result {
  _Result({
    required this.allPassed,
    required this.phase,
    required this.checks,
    required this.apiEndpoint,
    required this.rpOrigin,
  });
  final bool allPassed;
  final String phase;
  final List<_Check> checks;
  final String apiEndpoint;
  final String rpOrigin;

  Map<String, Object?> toJson() => <String, Object?>{
        'allPassed': allPassed,
        'phase': phase,
        'checks': checks.map((c) => c.toJson()).toList(),
        'apiEndpoint': apiEndpoint,
        'rpOrigin': rpOrigin,
      };
}
