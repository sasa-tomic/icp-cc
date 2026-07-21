// UX-H12 — interactive authenticated canister calls from the Call Builder
// sheet.
//
// Before UX-H12 the Canister Client sheet's "Call" button only ever invoked
// `RustBridgeLoader.callAnonymous` even though the bridge has supported
// `callAuthenticated` since R-3b WU-4 (and the script-app host has used it
// since STEP-1). This test exercises the new "Sign as active profile" toggle
// end-to-end through the same fake bridge pattern the rest of the sheet tests
// use, with a REAL Ed25519 keypair from `TestKeypairFactory` (AGENTS.md:
// never mock cryptography).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/services/secure_storage_readiness.dart';
import 'package:icp_autorun/widgets/canister_client_sheet.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';

import '../../shared/fake_secure_keypair_repository.dart';
import '../../shared/test_keypair_factory.dart';

/// Which bridge path the most recent call dispatched through.
enum _CallKind { anonymous, authenticated }

/// Records every canister call the sheet makes and returns canned JSON so the
/// call round-trip completes without touching the network. Mirrors the fake
/// in `test/canister_client_sheet_test.dart` and adds recording state so the
/// tests can assert on which path was taken and with which key material.
class _RecordingBridge extends RustBridgeLoader {
  _CallKind? lastCall;
  String? lastPrivateKeyB64;
  String? lastCanisterId;
  String? lastMethod;
  int anonymousCalls = 0;
  int authenticatedCalls = 0;

  @override
  Future<String?> fetchCandid(
      {required String canisterId, String? host}) async {
    if (canisterId == 'ryjl3-tyaaa-aaaaa-aaaba-cai') {
      return '''
service: {
  account_balance_dfx: (record {}) -> (record {});
}
''';
    }
    return null;
  }

  @override
  String? parseCandid({required String candidText}) {
    if (candidText.contains('account_balance_dfx')) {
      return '{"methods":[{"name":"account_balance_dfx","kind":"query","args":[],"rets":[]}]}';
    }
    return null;
  }

  @override
  Future<String?> callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) async {
    lastCall = _CallKind.anonymous;
    lastCanisterId = canisterId;
    lastMethod = method;
    anonymousCalls++;
    return '{"result":"anonymous-ok"}';
  }

  @override
  Future<String?> callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) async {
    lastCall = _CallKind.authenticated;
    lastPrivateKeyB64 = privateKeyB64;
    lastCanisterId = canisterId;
    lastMethod = method;
    authenticatedCalls++;
    return '{"result":"authenticated-ok","principal":"recorded-caller"}';
  }
}

/// Builds a [ProfileController] backed by an in-memory repository seeded with
/// [keypair], with that profile activated. Mirrors the helper in
/// `test/widgets/profile_menu_test_harness.dart` (DRY: same in-memory
/// repository, same activation dance).
Future<ProfileController> _controllerWithKeypair(ProfileKeypair keypair) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final repository = FakeSecureKeypairRepository(<ProfileKeypair>[keypair]);
  final controller =
      ProfileController(profileRepository: repository.profileRepository);
  await controller.ensureLoaded();
  if (controller.profiles.isNotEmpty) {
    await controller.setActiveProfile(controller.profiles.first.id);
  }
  return controller;
}

const String _kCanisterId = 'ryjl3-tyaaa-aaaaa-aaaba-cai';
const String _kMethodName = 'account_balance_dfx';

/// Drives the sheet to the "ready" state (canister loaded, method selected) so
/// the call button + sign-as-profile toggle are visible.
Future<void> _driveToReady(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('canisterField')),
    _kCanisterId,
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('methodChip_$_kMethodName')));
  await tester.pumpAndSettle();
}

void main() {
  // The principal is non-deterministic across CI runs (depends on the rust
  // FFI's derivation for the test mnemonic); we only assert structural
  // properties, never the literal value.

  testWidgets(
      'auth toggle is OFF by default; tapping Call uses callAnonymous '
      '(no regression on the pre-UX-H12 default path)', (tester) async {
    final keypair = await TestKeypairFactory.getEd25519Keypair();
    final controller = await _controllerWithKeypair(keypair);
    final bridge = _RecordingBridge();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileScope(
          controller: controller,
          child: CanisterClientSheet(bridge: bridge),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await _driveToReady(tester);

    final switchWidget = tester.widget<SwitchListTile>(
      find.byKey(const Key('signAsActiveProfileSwitch')),
    );
    expect(switchWidget.value, isFalse,
        reason: 'Default must remain anonymous — UX-H12 is opt-in.');

    await tester.tap(find.byKey(const Key('callButton')));
    await tester.pumpAndSettle();

    expect(bridge.lastCall, _CallKind.anonymous);
    expect(bridge.anonymousCalls, 1);
    expect(bridge.authenticatedCalls, 0);
    expect(bridge.lastPrivateKeyB64, isNull);
  });

  testWidgets(
      'with an active keypair, toggling "Sign as active profile" ON then '
      'tapping Call dispatches callAuthenticated with that keypair', (tester) async {
    final ProfileKeypair keypair = await TestKeypairFactory.getEd25519Keypair();
    final controller = await _controllerWithKeypair(keypair);
    final bridge = _RecordingBridge();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileScope(
          controller: controller,
          child: CanisterClientSheet(bridge: bridge),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await _driveToReady(tester);

    // Toggle ON — the switch must be enabled because an active keypair exists.
    final switchBefore = tester.widget<SwitchListTile>(
      find.byKey(const Key('signAsActiveProfileSwitch')),
    );
    expect(switchBefore.onChanged, isNotNull,
        reason: 'Toggle must be enabled when an active keypair exists.');
    await tester.tap(find.byKey(const Key('signAsActiveProfileSwitch')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(
          find.byKey(const Key('signAsActiveProfileSwitch'))).value,
      isTrue,
      reason: 'Tapping the toggle must flip the signed intent on.',
    );

    // Principal is rendered (NEVER the private key — security).
    expect(find.textContaining('Principal:'), findsOneWidget);

    await tester.tap(find.byKey(const Key('callButton')));
    await tester.pumpAndSettle();

    // The bridge MUST have been called via the authenticated path with the
    // active keypair's private key. NO crypto is mocked — this is the real
    // base64 key material the bridge would sign with.
    expect(bridge.lastCall, _CallKind.authenticated);
    expect(bridge.authenticatedCalls, 1);
    expect(bridge.anonymousCalls, 0);
    expect(bridge.lastPrivateKeyB64, keypair.privateKey);
    expect(bridge.lastCanisterId, _kCanisterId);
    expect(bridge.lastMethod, _kMethodName);

    // The result section renders the bridge's authenticated payload.
    expect(find.text('Result'), findsOneWidget);
    expect(find.textContaining('authenticated-ok'), findsOneWidget);
  });

  testWidgets(
      'security: the b64 private key material NEVER appears in the rendered '
      'result text (no leak through the JSON view)', (tester) async {
    final ProfileKeypair keypair = await TestKeypairFactory.getEd25519Keypair();
    final controller = await _controllerWithKeypair(keypair);
    final bridge = _RecordingBridge();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileScope(
          controller: controller,
          child: CanisterClientSheet(bridge: bridge),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await _driveToReady(tester);

    await tester.tap(find.byKey(const Key('signAsActiveProfileSwitch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('callButton')));
    await tester.pumpAndSettle();

    // The result section rendered the bridge's payload.
    expect(find.text('Result'), findsOneWidget);
    expect(find.textContaining('authenticated-ok'), findsOneWidget);

    // Sweep EVERY SelectableText the sheet rendered: none of them may carry
    // the b64 private key. The result JSON is the obvious vector; sweeping
    // all of them guards against a future leak through a different surface.
    final selectableTexts = tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    );
    expect(selectableTexts, isNotEmpty,
        reason: 'Result section should have rendered at least one SelectableText.');
    for (final t in selectableTexts) {
      expect((t.data ?? '').contains(keypair.privateKey), isFalse,
          reason: 'Private key material must never appear in any rendered text.');
    }
  });

  testWidgets(
      'no ProfileScope ancestor → switch is disabled and the create-profile '
      'CTA subtitle is shown (no anonymous regression)', (tester) async {
    final bridge = _RecordingBridge();

    // Deliberately mount WITHOUT a ProfileScope ancestor — mirrors the
    // sheet's legacy test mount and exercises the off-tree path.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CanisterClientSheet(bridge: bridge),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await _driveToReady(tester);

    final switchWidget = tester.widget<SwitchListTile>(
      find.byKey(const Key('signAsActiveProfileSwitch')),
    );
    expect(switchWidget.onChanged, isNull,
        reason: 'Toggle must be disabled when no ProfileScope/keypair exists.');
    expect(switchWidget.value, isFalse);

    // The CTA hint is rendered.
    expect(find.byKey(const Key('signAsActiveProfileCreateCta')),
        findsOneWidget);
    expect(find.text('Create a profile to sign calls as your identity.'),
        findsOneWidget);

    // Tapping the toggle does nothing (disabled). The default anonymous path
    // is unchanged when no signing was ever requested.
    await tester.tap(find.byKey(const Key('signAsActiveProfileSwitch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('callButton')));
    await tester.pumpAndSettle();

    expect(bridge.lastCall, _CallKind.anonymous);
    expect(bridge.authenticatedCalls, 0);
  });

  testWidgets(
      'ProfileScope present but no active profile → CTA opens the wizard '
      '(real controller; keyless user deep-link)', (tester) async {
    // Real controller with NO profiles — the keyless-user production state.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = FakeSecureKeypairRepository(<ProfileKeypair>[]);
    final controller =
        ProfileController(profileRepository: repository.profileRepository);
    await controller.ensureLoaded();

    final bridge = _RecordingBridge();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileScope(
          controller: controller,
          child: CanisterClientSheet(
            bridge: bridge,
            // Inject a fixed-ready probe so the test is hermetic — the real
            // probe would shell out to gnome-keyring-daemon on a Linux host
            // and pumpAndSettle would never converge. Mirrors the deep-link
            // test in dapp_runner_screen_test.dart.
            testSecureStorageReadiness: _FixedReadiness(const StorageReady()),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await _driveToReady(tester);

    // Toggle is disabled (no keypair) but the CTA is tappable.
    final switchWidget = tester.widget<SwitchListTile>(
      find.byKey(const Key('signAsActiveProfileSwitch')),
    );
    expect(switchWidget.onChanged, isNull,
        reason: 'No active keypair → toggle must be disabled.');
    expect(find.byKey(const Key('signAsActiveProfileCreateCta')),
        findsOneWidget);

    // Tap the CTA → the wizard pushes onto the navigator. ONE tap → the real
    // wizard (not a stub/dead-end). Same widget the first-run gate uses.
    await tester.tap(find.byKey(const Key('signAsActiveProfileCreateCta')));
    await tester.pumpAndSettle();

    expect(find.byType(UnifiedSetupWizard), findsOneWidget);
  });

  testWidgets(
      'mid-session profile removal: toggle was ON, profile disappeared → '
      'tapping Call surfaces a LOUD friendly SnackBar (never silent anonymous '
      'fallback, never a raw StateError)', (tester) async {
    final ProfileKeypair keypair = await TestKeypairFactory.getEd25519Keypair();
    final controller = await _controllerWithKeypair(keypair);
    final bridge = _RecordingBridge();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileScope(
          controller: controller,
          child: CanisterClientSheet(bridge: bridge),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await _driveToReady(tester);

    // Toggle sign-as-profile ON while the keypair exists.
    await tester.tap(find.byKey(const Key('signAsActiveProfileSwitch')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(
          find.byKey(const Key('signAsActiveProfileSwitch'))).value,
      isTrue,
    );

    // Simulate mid-session profile removal: drop the active profile from the
    // SAME controller. The widget tree (and thus _CanisterClientSheetState)
    // is preserved; ProfileScope notifies its descendants and the toggle
    // re-renders disabled. _signAsActiveProfile stays true (defensive check).
    await controller.setActiveProfile(null);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(
          find.byKey(const Key('signAsActiveProfileSwitch'))).onChanged,
      isNull,
      reason: 'Profile gone → toggle must re-render disabled.',
    );

    // Tap Call. The signed intent must NOT silently degrade to anonymous
    // (AGENTS.md) and must NOT throw a raw StateError to the user.
    await tester.tap(find.byKey(const Key('callButton')));
    await tester.pumpAndSettle();

    expect(bridge.lastCall, isNull,
        reason: 'No bridge call should have been attempted.');
    expect(bridge.authenticatedCalls, 0);
    expect(bridge.anonymousCalls, 0,
        reason: 'Never silently fall back to anonymous on a signed intent.');

    // The friendly SnackBar surfaces — text from friendlyErrorMessage
    // (ErrorCategory.userMessage), not a raw `StateError`/`Exception:` dump.
    expect(find.byType(SnackBar), findsOneWidget);
    final snackbarText =
        tester.widget<SnackBar>(find.byType(SnackBar)).content;
    expect(snackbarText, isA<Text>());
    final message = (snackbarText as Text).data ?? '';
    expect(message.contains('Cannot sign call'), isTrue,
        reason: 'Context prefix from friendlyErrorMessage must be present.');
    expect(message.contains('StateError'), isFalse,
        reason: 'Never surface a raw type name.');
    expect(message.contains('Exception:'), isFalse,
        reason: 'Never surface a raw Exception prefix.');
  });
}

/// A [SecureStorageReadiness] that returns a fixed result, so the deep-link
/// navigation test is hermetic (the real probe would shell out to
/// gnome-keyring-daemon on a Linux host and pumpAndSettle would never
/// converge). Readiness is platform availability, not cryptography — the legit
/// test seam, mirroring `dapp_runner_screen_test.dart`'s `_FixedReadiness`.
class _FixedReadiness extends SecureStorageReadiness {
  _FixedReadiness(this.result);
  final StorageReadiness result;

  @override
  Future<StorageReadiness> check() async => result;
}
