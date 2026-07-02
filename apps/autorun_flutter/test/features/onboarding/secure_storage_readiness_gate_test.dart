// WU-S2 widget tests for the UnifiedSetupWizard secure-storage readiness gate.
//
// Written failing-first: the wizard must (a) render a blocking, actionable
// panel (NOT a raw exception) when secrets can't be persisted, with a Retry;
// (b) proceed to create the profile when storage is ready; (c) recover via
// Retry after the user fixes the keyring.
//
// The readiness probe is platform-AVAILABILITY (not crypto), so we inject a
// [SecureStorageReadiness] subclass whose `check()` returns a fixed result.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/services/secure_storage_readiness.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/test_keypair_factory.dart';

/// A readiness service that returns a fixed result. The legit test seam:
/// readiness is platform availability, not cryptography.
class _FixedReadiness extends SecureStorageReadiness {
  _FixedReadiness(this.result);
  final StorageReadiness result;

  @override
  Future<StorageReadiness> check() async => result;
}

/// Returns `result` on the first call, then `nextResult` thereafter (Retry path).
class _ToggleReadiness extends SecureStorageReadiness {
  _ToggleReadiness(this.first, this.nextResult);
  final StorageReadiness first;
  final StorageReadiness nextResult;
  int calls = 0;

  @override
  Future<StorageReadiness> check() async {
    calls += 1;
    return calls == 1 ? first : nextResult;
  }
}

const _unavailable = StorageUnavailable(
  reason: 'Test keyring is down',
  explanation: 'Test explanation body.',
  fixCommand: 'sudo apt-get install -y test-keyring',
  fixHint: 'Test fix hint.',
  technicalDetail: 'PlatformException(Libsecret error, raw, null, null)',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedSetupWizard secure-storage readiness gate (WU-S2)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets(
        'on StorageUnavailable shows the actionable panel, not a raw exception, '
        'with a Retry button', (tester) async {
      final profileController = _StubProfileController();
      final accountController = AccountController();

      await tester.pumpWidget(MaterialApp(
        home: UnifiedSetupWizard(
          profileController: profileController,
          accountController: accountController,
          secureStorageReadiness: _FixedReadiness(const StorageUnavailable(
            reason: 'Test keyring is down',
            explanation: 'Test explanation body.',
            fixCommand: 'sudo apt-get install -y test-keyring',
            fixHint: 'Test fix hint.',
            technicalDetail:
                'PlatformException(Libsecret error, raw, null, null)',
          )),
        ),
      ));
      await tester.pumpAndSettle();

      // The actionable panel renders (NOT the form).
      expect(find.text('Test keyring is down'), findsOneWidget);
      expect(find.text('Test explanation body.'), findsOneWidget);
      expect(find.text('sudo apt-get install -y test-keyring'), findsOneWidget);
      expect(find.text('Test fix hint.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // The profile form is NOT shown.
      expect(find.text('Display Name'), findsNothing);

      // NEW-4: no raw 'PlatformException(…)' string is in the widget tree by
      // default (it lives behind the "Show details" affordance, which is
      // collapsed — so it is not built).
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('Libsecret error'), findsNothing);
    });

    testWidgets('on StorageReady the form renders and a profile can be created',
        (tester) async {
      final profileController = _OkProfileController();
      final accountController = AccountController();

      UnifiedSetupResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<UnifiedSetupResult>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => UnifiedSetupWizard(
                      profileController: profileController,
                      accountController: accountController,
                      secureStorageReadiness:
                          _FixedReadiness(const StorageReady()),
                    ),
                  ),
                );
              },
              child: const Text('Launch'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      // Readiness OK → the form renders.
      expect(find.text('Display Name'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Ready User');
      await tester.pump(); // let onChanged→setState enable the button.
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
      await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Profile was created → success screen.
      expect(find.text('Success!'), findsOneWidget);
      expect(find.text('Start Exploring'), findsOneWidget);
      expect(profileController.profiles, isNotEmpty);
      expect(profileController.profiles.first.name, 'Ready User');

      await tester.ensureVisible(find.text('Start Exploring'));
      await tester.tap(find.text('Start Exploring'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.profile.name, 'Ready User');
    });

    testWidgets('Retry re-probes and recovers to the form when storage heals',
        (tester) async {
      final profileController = _StubProfileController();
      final accountController = AccountController();
      final readiness = _ToggleReadiness(_unavailable, const StorageReady());

      await tester.pumpWidget(MaterialApp(
        home: UnifiedSetupWizard(
          profileController: profileController,
          accountController: accountController,
          secureStorageReadiness: readiness,
        ),
      ));
      await tester.pumpAndSettle();

      // Initially unavailable → panel.
      expect(find.text('Test keyring is down'), findsOneWidget);
      expect(find.text('Display Name'), findsNothing);

      // User fixes the keyring out-of-band, then taps Retry.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Recovered → form now renders.
      expect(find.text('Display Name'), findsOneWidget);
      expect(find.text('Test keyring is down'), findsNothing);
      expect(readiness.calls, 2);
    });

    testWidgets('a residual createProfile error is humanized, never raw',
        (tester) async {
      // Readiness OK so the form renders, but make createProfile throw a
      // PlatformException (simulating the keyring going down between probe and
      // create). The wizard must humanize it — never show 'PlatformException'.
      final profileController = _ThrowingProfileController();
      final accountController = AccountController();

      await tester.pumpWidget(MaterialApp(
        home: UnifiedSetupWizard(
          profileController: profileController,
          accountController: accountController,
          secureStorageReadiness: _FixedReadiness(const StorageReady()),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Boom User');
      await tester.pump(); // let onChanged→setState enable the button.
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
      await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // An error banner is shown, but it is friendly — never the raw
      // 'PlatformException(…)' string (NEW-4).
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('keyring'), findsOneWidget);
    });
  });
}

/// A ProfileController whose createProfile SUCCEEDS using a real (pre-generated)
/// test keypair — avoids the unit-test host's missing libicp_core.so, which the
/// real ProfileController.createProfile needs via KeypairGenerator FFI. Used to
/// prove the readiness gate does not block the happy path.
class _OkProfileController extends _StubProfileController {
  final List<Profile> _profiles = <Profile>[];
  String? _activeId;

  @override
  List<Profile> get profiles => List<Profile>.unmodifiable(_profiles);

  @override
  Profile? get activeProfile =>
      _profiles.where((Profile p) => p.id == _activeId).firstOrNull;

  @override
  bool get hasActiveProfile => _activeId != null;

  @override
  String? get activeProfileId => _activeId;

  @override
  Future<Profile> createProfile({
    required String profileName,
    required KeyAlgorithm algorithm,
    String? mnemonic,
    bool setAsActive = false,
  }) async {
    final keypair = await TestKeypairFactory.getEd25519Keypair();
    final now = DateTime.now().toUtc();
    final profile = Profile(
      id: 'profile-${_profiles.length}',
      name: profileName,
      keypairs: <ProfileKeypair>[keypair],
      username: null,
      createdAt: now,
      updatedAt: now,
    );
    _profiles.add(profile);
    if (setAsActive) _activeId = profile.id;
    notifyListeners();
    return profile;
  }
}

/// A ProfileController whose createProfile throws the exact libsecret
/// PlatformException the app sees on a keyring-less Linux box (NEW-2), to
/// exercise the wizard's residual-error humanization (NEW-4).
class _ThrowingProfileController extends _StubProfileController {
  @override
  Future<Profile> createProfile({
    required String profileName,
    required KeyAlgorithm algorithm,
    String? mnemonic,
    bool setAsActive = false,
  }) async {
    throw PlatformException(
      code: 'Libsecret error',
      message: 'Failed to unlock the keyring',
      details: null,
    );
  }
}

/// A minimal stub that satisfies the ProfileController surface the wizard
/// touches, so we don't reimplement every method. Uses noSuchMethod for the
/// unused surface.
class _StubProfileController extends ChangeNotifier
    implements ProfileController {
  @override
  List<Profile> get profiles => const <Profile>[];

  @override
  bool get isBusy => false;

  @override
  String? get activeProfileId => null;

  @override
  bool get hasActiveProfile => false;

  @override
  Profile? get activeProfile => null;

  @override
  ProfileKeypair? get activeKeypair => null;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> refresh() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
