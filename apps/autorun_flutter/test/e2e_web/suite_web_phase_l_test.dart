// ignore_for_file: lines_longer_than_80_chars

// Phase L — Web Tier A 6 deferred flows (3 passkey + 3 deeplink).
//
// WHAT THIS PROVES
//   `flutter test -d chrome` boots the REAL app's passkey + deeplink surfaces
//   against substrate fakes at the smallest I/O boundary. Real Dart business
//   logic runs end-to-end (`PasskeyService` signature generation, real
//   `DeepLinkService` URI parsing); only the literal browser WebAuthn API
//   and the OS launcher events are substrate-faked.
//
// FLOWS COVERED (6 — Phase L Web Tier A)
//   1. `passkey.list`           — empty/list state renders correctly.
//   2. `passkey.register`       — substrate credential exchange + UI success.
//   3. `passkey.delete`         — substrate HTTP delete + list refresh.
//   4. `deeplink.open_script`   — synthetic URI emits script event on stream.
//   5. `deeplink.purchase_unavailable` — unknown host ignored gracefully.
//   6. `deeplink.invalid_scheme`— wrong-scheme URI ignored gracefully.
//
// WHY THESE FLOWS WERE DEFERRED
//   Both surfaces need platform hooks unavailable under `flutter test -d chrome`:
//     - Passkey: `PasskeyPlatform.isSupported` is FALSE (test compiles for VM
//       on linux host); browser `navigator.credentials.create` is unreachable.
//     - Deeplink: `_KeypairAppState._initDeepLinks` early-returns on linux
//       (kIsWeb=false, defaultTargetPlatform==linux), so the app listener is
//       never wired.
//   Phase L resolves both with the smallest-boundary seams sanctioned by the
//   Phase C rule:
//     - `PasskeyPlatform.isSupportedOverrideForTesting` flips the platform
//       flag for the suite (the Web surface under test).
//     - `NativePasskeyAuthenticator.registerOverrideForTesting` substitutes
//       a deterministic in-process credential for the browser WebAuthn call.
//     - `DeepLinkService.instance.handleLink` (a public API) is invoked
//       directly; the test subscribes to `linkStream` to assert dispatch.
//
// Run via: `just e2e-web` (default suite list now includes this file).
@TestOn('browser')
@Tags(['web'])
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/passkey_management_screen.dart';
import 'package:icp_autorun/services/deep_link_service.dart';
import 'package:icp_autorun/services/passkey_authenticator.dart';
import 'package:icp_autorun/utils/passkey_platform.dart';

import '../shared/test_keypair_factory.dart';
import '../../integration_test/e2e/e2e_driver.dart';
import '../../integration_test/e2e/flow_catalog.dart';
import 'substrate/substrate.dart';

/// The account id the passkey flows route against. Stable so flows can
/// pre-seed + assert state across phases.
const String _kAccountId = 'account-phase-l-passkey';

/// The test device name `passkey.register` asserts on. Derived from
/// `defaultTargetPlatform` to match `_PasskeyManagementScreenState
/// ._getDeviceName` exactly. Under `flutter test -d chrome` the test
/// binding reports `TargetPlatform.android` (Flutter's default for chrome —
/// web doesn't have its own TargetPlatform enum), so the expected name is
/// "Android Device" — NOT "Linux Device" (that would be the linux desktop
/// test binding). Resolving dynamically keeps the assertion correct under
/// any future binding change.
String get _kRegisteredDeviceName => switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'iOS Device',
      TargetPlatform.android => 'Android Device',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows PC',
      TargetPlatform.linux => 'Linux Device',
      TargetPlatform.fuchsia => 'Fuchsia Device',
    };

void main() {
  // Install the substrate ONCE for the suite. The server is kept in a
  // suite-scoped variable so the passkey flows can pre-seed state and
  // assert post-conditions directly on `SubstratePasskeyStore`.
  final substrateServer = defaultServer();
  SubstratePasskeyStore passkeyStore =
      substrateServer.passkeyStoreForTesting;

  setUpAll(() {
    installSubstratePrefs();
    installSubstrateSecureStorage();
    installSubstrateHttp(substrateServer);
    installSubstratePathProvider();
    installSubstrateAppLinksSilencer();
    installSubstratePackageInfo();

    // Pretend to be the Web surface so `PasskeyPlatform.isSupported` is
    // TRUE (otherwise PasskeyManagementScreen renders the "Linux desktop
    // unsupported" panel and the list/register/delete UI is unreachable).
    // Mirrors what the real app sees in a browser.
    PasskeyPlatform.isSupportedOverrideForTesting = true;

    // Substitute the browser WebAuthn call (`navigator.credentials.create`)
    // with a deterministic in-process response. The real
    // `PasskeyService.registerPasskey` runs unchanged — challenge fetch
    // (substrate HTTP), signature generation (real Ed25519), and finish
    // POST (substrate HTTP) all execute against real app code.
    NativePasskeyAuthenticator.registerOverrideForTesting =
        (Map<String, dynamic> options) async {
      // Return a minimal credential JSON. The substrate's finish handler
      // doesn't verify the WebAuthn attestation signature — it just stores
      // the envelope and returns a registration result. The shape matches
      // what `package:passkeys` returns from `PasskeyAuthenticator.register`
      // (id, rawId, type, response.{clientDataJSON, attestationObject,
      // transports}).
      return <String, dynamic>{
        'id': 'substrate-credential-id',
        'rawId': 'substrate-credential-id',
        'type': 'public-key',
        'response': <String, dynamic>{
          'clientDataJSON': 'substrate-client-data',
          'attestationObject': 'substrate-attestation',
          'transports': <String>['internal'],
        },
      };
    };
  });

  tearDownAll(() {
    // Restore production behaviour so the override doesn't leak into other
    // suites in the same process.
    PasskeyPlatform.isSupportedOverrideForTesting = null;
    NativePasskeyAuthenticator.registerOverrideForTesting = null;
    DeepLinkService.resetForTesting();
  });

  final driver = E2EDriver(surface: E2ESurface.web, substrateAware: true);

  final registry = FlowRegistry()
    ..register('passkey.list', (tester, d) => _passkeyListFlow(tester, d))
    ..register(
        'passkey.register', (tester, d) => _passkeyRegisterFlow(tester, d, passkeyStore))
    ..register(
        'passkey.delete', (tester, d) => _passkeyDeleteFlow(tester, d, passkeyStore))
    ..register('deeplink.open_script',
        (tester, d) => _deeplinkOpenScriptFlow(tester, d))
    ..register('deeplink.purchase_unavailable',
        (tester, d) => _deeplinkPurchaseUnavailableFlow(tester, d))
    ..register('deeplink.invalid_scheme',
        (tester, d) => _deeplinkInvalidSchemeFlow(tester, d));

  // ── Passkey flows ───────────────────────────────────────────────────────
  //
  // The three passkey flows run sequentially in ONE testWidgets body so the
  // substrate's in-memory passkey store persists across phases:
  //   phase 1 (list):       empty state.
  //   phase 2 (register):   store gains 1 passkey.
  //   phase 3 (delete):     store empties again.
  // This mirrors the desktop suite's "phases share state" pattern.
  testWidgets(
      'web e2e Tier A Phase L — passkey flows (3 phases against substrate HTTP)',
      (tester) async {
    driver.phase('PHASE L', 'passkey flows — substrate HTTP boundary');

    // Reset the substrate store to a clean slate so a re-run of the suite
    // doesn't see stale state from a prior failed run.
    passkeyStore.clearForTesting();

    driver.phase('L.1', 'passkey.list');
    await registry.runFor('passkey.list')!(tester, driver);
    driver.phase('L.1', 'OK — passkey.list');

    driver.phase('L.2', 'passkey.register');
    await registry.runFor('passkey.register')!(tester, driver);
    driver.phase('L.2', 'OK — passkey.register');

    driver.phase('L.3', 'passkey.delete');
    await registry.runFor('passkey.delete')!(tester, driver);
    driver.phase('L.3', 'OK — passkey.delete');

    // Drain flutter_cache_manager's cleanup timer so the binding's
    // timersPending invariant doesn't trip on teardown (same workaround the
    // Tier A 7-flow suite uses).
    await tester.pump(const Duration(seconds: 11));

    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE-PHASE-L-PASSKEY',
        '${cov.implemented}/${cov.total} flows registered');
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ── Deeplink flows ──────────────────────────────────────────────────────
  //
  // The three deeplink flows each subscribe to DeepLinkService.linkStream,
  // emit a synthetic URI through DeepLinkService.handleLink (the same public
  // API the app's listener subscribes to on non-linux surfaces), and assert
  // what the stream did (or did not) dispatch.
  testWidgets(
      'web e2e Tier A Phase L — deeplink flows (3 phases, synthetic URIs)',
      (tester) async {
    driver.phase('PHASE L', 'deeplink flows — DeepLinkService boundary');

    // Pump a trivial MaterialApp so the test binding has a widget tree to
    // advance (without this, the binding's post-test idle wait can hang
    // indefinitely — the deeplink flows don't mount any widgets themselves,
    // but the binding still expects something to pump). The actual
    // assertions are against DeepLinkService.stream, NOT the widget tree.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pump(const Duration(milliseconds: 50));

    driver.phase('L.4', 'deeplink.open_script');
    await registry.runFor('deeplink.open_script')!(tester, driver);
    driver.phase('L.4', 'OK — deeplink.open_script');

    driver.phase('L.5', 'deeplink.purchase_unavailable');
    await registry.runFor('deeplink.purchase_unavailable')!(tester, driver);
    driver.phase('L.5', 'OK — deeplink.purchase_unavailable');

    driver.phase('L.6', 'deeplink.invalid_scheme');
    await registry.runFor('deeplink.invalid_scheme')!(tester, driver);
    driver.phase('L.6', 'OK — deeplink.invalid_scheme');

    final cov = FlowCatalog.coverageReport(registry);
    driver.phase('COVERAGE-PHASE-L-DEEPLINK',
        '${cov.implemented}/${cov.total} flows registered');
  }, timeout: const Timeout(Duration(seconds: 60)));
}

// ── Flow bodies ─────────────────────────────────────────────────────────────

/// `passkey.list` — pump PasskeyManagementScreen against an empty substrate
/// store, assert the "No Passkeys Yet" empty state renders.
Future<void> _passkeyListFlow(WidgetTester tester, E2EDriver driver) async {
  // The substrate's passkey store is reset to empty in the test body before
  // this phase runs. Pump the screen directly (its catalog entry is
  // `passkey_management_screen.dart`); driving the full app would require
  // creating a profile + registered account first, which adds 30+ seconds
  // of setup that's irrelevant to this surface contract.
  final keypair = await TestKeypairFactory.getEd25519Keypair();
  await tester.pumpWidget(MaterialApp(
    home: PasskeyManagementScreen(
      accountId: _kAccountId,
      username: 'phase-l-tester',
      keypair: keypair,
    ),
  ));

  // Drive the unawaited initState chain (PasskeyService.listPasskeys HTTP
  // round-trip) via runAsync so the substrate round-trip completes.
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync<void>(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    if (!driver.present(find.byType(CircularProgressIndicator), tester)) break;
  }

  // Contract: with an empty store, the empty-state renders.
  expect(driver.present(find.text('No Passkeys Yet'), tester), isTrue,
      reason: 'PasskeyManagementScreen with empty substrate must show '
          '"No Passkeys Yet" empty state.');
  expect(driver.present(find.text('Add Passkey'), tester), isTrue,
      reason: 'The "Add Passkey" FAB must always be present.');
}

/// `passkey.register` — tap the FAB, expect the substrate credential
/// exchange to complete and the new device to appear in the list.
Future<void> _passkeyRegisterFlow(
    WidgetTester tester, E2EDriver driver, SubstratePasskeyStore store) async {
  // Re-pump the screen so initState re-runs against the (still empty)
  // substrate store. Using a UNIQUE key forces Flutter to recreate the
  // state — otherwise the previous phase's state is reused.
  final keypair = await TestKeypairFactory.getEd25519Keypair();
  await tester.pumpWidget(MaterialApp(
    home: PasskeyManagementScreen(
      key: UniqueKey(),
      accountId: _kAccountId,
      username: 'phase-l-tester',
      keypair: keypair,
    ),
  ));
  // Drive the initial list-load round-trip.
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync<void>(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    if (!driver.present(find.byType(CircularProgressIndicator), tester)) break;
  }
  expect(driver.present(find.text('No Passkeys Yet'), tester), isTrue,
      reason: 'Precondition: substrate passkey store is empty before register.');
  expect(store.total, 0, reason: 'Precondition: substrate store empty.');

  // Tap the FAB → triggers _addPasskey → PasskeyService.registerPasskey
  // (substrate HTTP /passkey/register/start + NativePasskeyAuthenticator
  // override + substrate HTTP /passkey/register/finish).
  // FloatingActionButton.extended renders the label as a Text descendant;
  // locate by type + label text rather than tooltip (no tooltip set).
  final fabByLabel = find.ancestor(
    of: find.text('Add Passkey'),
    matching: find.byType(FloatingActionButton),
  );
  expect(fabByLabel, findsWidgets,
      reason: 'Add Passkey FAB must be reachable.');
  await tester.tap(fabByLabel.first);

  // Drive the async register chain. The full chain is: HTTP start →
  // NativePasskeyAuthenticator override → HTTP finish → SnackBar + list
  // reload → setState.
  for (var i = 0; i < 30; i++) {
    await tester
        .runAsync<void>(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    if (driver.present(find.text('Passkey added successfully'), tester)) break;
  }

  expect(driver.present(find.text('Passkey added successfully'), tester), isTrue,
      reason: 'Register flow must surface the "Passkey added successfully" '
          'SnackBar after the substrate credential exchange completes.');
  expect(store.total, 1,
      reason: 'Register must add exactly 1 passkey to the substrate store: '
          'got ${store.total}.');

  // Dismiss the SnackBar so it doesn't cover the list item.
  final scaffoldEl = find.byType(Scaffold).evaluate().firstOrNull;
  if (scaffoldEl != null) {
    ScaffoldMessenger.of(scaffoldEl).removeCurrentSnackBar();
  }
  await tester.pump(const Duration(milliseconds: 300));

  // The list reload (_loadPasskeys) was fired by _addPasskey after the
  // SnackBar; pump until the new device name appears.
  for (var i = 0; i < 30; i++) {
    await tester
        .runAsync<void>(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    if (driver.present(find.text(_kRegisteredDeviceName), tester)) break;
  }
  expect(driver.present(find.text(_kRegisteredDeviceName), tester), isTrue,
      reason: 'After register, the new device ("$_kRegisteredDeviceName") '
          'must appear in the passkey list.');
}

/// `passkey.delete` — the passkey from phase 2 exists; tap delete, confirm,
/// assert the list returns to empty.
Future<void> _passkeyDeleteFlow(
    WidgetTester tester, E2EDriver driver, SubstratePasskeyStore store) async {
  expect(store.total, 1,
      reason: 'Precondition: phase 2 register must have left 1 passkey.');
  // Re-pump the screen with a fresh key so initState re-runs and the list
  // loads from substrate.
  final keypair = await TestKeypairFactory.getEd25519Keypair();
  await tester.pumpWidget(MaterialApp(
    home: PasskeyManagementScreen(
      key: UniqueKey(),
      accountId: _kAccountId,
      username: 'phase-l-tester',
      keypair: keypair,
    ),
  ));
  for (var i = 0; i < 15; i++) {
    await tester
        .runAsync<void>(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    if (driver.present(find.text(_kRegisteredDeviceName), tester)) break;
  }
  expect(driver.present(find.text(_kRegisteredDeviceName), tester), isTrue,
      reason: 'Precondition: registered passkey must be visible before delete.');

  // Tap the per-card delete IconButton. The card uses Icons.delete_outline.
  await tester.tap(find.byIcon(Icons.delete_outline).first);
  await tester.pump(const Duration(milliseconds: 300));

  // Confirm dialog appears. Tap "Delete".
  expect(driver.present(find.text('Delete Passkey?'), tester), isTrue,
      reason: 'Tapping delete must show the "Delete Passkey?" confirm dialog.');
  // The dialog has TWO TextButtons — "Cancel" and "Delete". Tap "Delete".
  final deleteButton = find.descendant(
    of: find.byType(TextButton),
    matching: find.text('Delete'),
  );
  expect(deleteButton, findsWidgets,
      reason: 'Confirm dialog must have a Delete action.');
  await tester.tap(deleteButton.first);
  // Drive the async delete chain: HTTP DELETE → SnackBar + list reload.
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync<void>(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    if (driver.present(find.text('Passkey deleted'), tester)) break;
  }

  expect(driver.present(find.text('Passkey deleted'), tester), isTrue,
      reason: 'Delete must surface the "Passkey deleted" SnackBar.');
  // Wait for the list to reload.
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync<void>(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    if (driver.present(find.text('No Passkeys Yet'), tester)) break;
  }
  expect(driver.present(find.text('No Passkeys Yet'), tester), isTrue,
      reason: 'After delete, the list must return to the empty state.');
  expect(store.total, 0,
      reason: 'After delete, the substrate store must be empty.');
}

/// `deeplink.open_script` — pump a synthetic `icpautorun://script/{id}` URI
/// through DeepLinkService.handleLink and assert the stream emits the right
/// DeepLinkData. The real parsing code runs (parseUri, scheme check, host
/// check, path-segment extraction).
Future<void> _deeplinkOpenScriptFlow(
    WidgetTester tester, E2EDriver driver) async {
  // The DeepLinkService is a singleton; reset for a clean slate so a
  // prior flow's events don't pollute this one. (Also reset on tearDownAll.)
  DeepLinkService.resetForTesting();
  const scriptId = 'interactive-counter';
  final uri = Uri.parse('icpautorun://script/$scriptId');

  // `collectSubstrateDeepLinks` runs the body inside `tester.runAsync` so
  // the Future.delayed inside completes in wall-clock time (the binding's
  // fake clock never advances real Timers).
  final emitted = await collectSubstrateDeepLinks(tester, () async {
    emitSubstrateDeepLink(uri);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  expect(emitted.length, 1, reason: 'A valid script URI must emit exactly one '
      'DeepLinkData event on linkStream.');
  expect(emitted.first.type, DeepLinkType.script,
      reason: 'Event type must be DeepLinkType.script for a script URI.');
  expect(emitted.first.scriptId, scriptId,
      reason: 'Event scriptId must be the path-segment of the URI.');
  driver.phase('L.4-emit', 'script URI dispatched: ${emitted.first}');
}

/// `deeplink.purchase_unavailable` — pump a synthetic URI with the
/// `purchase` host (unknown to DeepLinkService; only `script` is handled).
/// The service gracefully ignores it: no event emitted, no exception.
/// This is the "purchase unavailable on this platform" semantics — there's
/// no `purchase` host handler because purchases route through the script
/// details dialog's Buy CTA, not deep links.
Future<void> _deeplinkPurchaseUnavailableFlow(
    WidgetTester tester, E2EDriver driver) async {
  DeepLinkService.resetForTesting();
  final uri = Uri.parse('icpautorun://purchase/paid-seed-script');

  final emitted = await collectSubstrateDeepLinks(tester, () async {
    emitSubstrateDeepLink(uri);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  expect(emitted, isEmpty,
      reason: 'Unknown host ("purchase") must be silently ignored — no '
          'DeepLinkData emitted, no exception. The current DeepLinkService '
          'has no "purchase" host; the actual "purchase unavailable" UI is '
          'reached via the script details dialog Buy CTA, not via this URI '
          'host. This flow proves the service does not fabricate a script '
          'event for an unrecognised purchase URI.');
  driver.phase('L.5-ignore', 'purchase URI ignored (no event)');
}

/// `deeplink.invalid_scheme` — pump a URI with a WRONG scheme. The service
/// rejects it at the scheme check (parseUri returns null, no event emitted).
Future<void> _deeplinkInvalidSchemeFlow(
    WidgetTester tester, E2EDriver driver) async {
  DeepLinkService.resetForTesting();

  // Try multiple wrong schemes — all must be ignored.
  final uris = <Uri>[
    Uri.parse('https://example.com/foo'),
    Uri.parse('unrecognized://bar'),
    Uri.parse('http://localhost:8099/x'),
  ];

  final emitted = await collectSubstrateDeepLinks(tester, () async {
    for (final uri in uris) {
      emitSubstrateDeepLink(uri);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  expect(emitted, isEmpty,
      reason: 'Wrong-scheme URIs (${uris.map((u) => u.scheme).join(", ")}) '
          'must be silently ignored — no DeepLinkData emitted, no exception. '
          'Only `icpautorun://` URIs are dispatched.');
  driver.phase('L.6-ignore', '${uris.length} invalid-scheme URIs ignored');
}
