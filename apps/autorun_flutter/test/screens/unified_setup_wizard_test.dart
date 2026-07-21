import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/passkey_management_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/screens/vault_password_setup_screen.dart';

import '../shared/test_keypair_factory.dart';

class _FakeProfileController extends ChangeNotifier
    implements ProfileController {
  final List<Profile> _profiles = [];
  bool _isBusy = false;
  String? _activeProfileId;
  int deleteProfileCallCount = 0;

  @override
  List<Profile> get profiles => List.unmodifiable(_profiles);

  @override
  bool get isBusy => _isBusy;

  @override
  String? get activeProfileId => _activeProfileId;

  @override
  bool get hasActiveProfile => _activeProfileId != null;

  @override
  Profile? get activeProfile => _profiles.isNotEmpty ? _profiles.first : null;

  @override
  ProfileKeypair? get activeKeypair => activeProfile?.primaryKeypair;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<Profile> createProfile({
    required String profileName,
    required KeyAlgorithm algorithm,
    String? mnemonic,
    bool setAsActive = false,
  }) async {
    _isBusy = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 50));

    final keypair = await TestKeypairFactory.getEd25519Keypair();
    final now = DateTime.now().toUtc();
    final profile = Profile(
      id: 'test-profile-${_profiles.length}',
      name: profileName,
      keypairs: [keypair],
      username: null,
      createdAt: now,
      updatedAt: now,
    );

    _profiles.add(profile);
    if (setAsActive) {
      _activeProfileId = profile.id;
    }

    _isBusy = false;
    notifyListeners();
    return profile;
  }

  @override
  Future<void> updateProfileUsername({
    required String profileId,
    required String username,
  }) async {
    final index = _profiles.indexWhere((p) => p.id == profileId);
    if (index >= 0) {
      _profiles[index] = _profiles[index].copyWith(username: username);
      notifyListeners();
    }
  }

  @override
  Future<void> setActiveProfile(String? id) async {
    _activeProfileId = id;
    notifyListeners();
  }

  @override
  Future<void> updateProfileName({
    required String profileId,
    required String name,
  }) async {}

  @override
  Future<Profile> addKeypairToProfile({
    required String profileId,
    required KeyAlgorithm algorithm,
    String? label,
    String? mnemonic,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> setActiveKeypair({
    required String profileId,
    required String keypairId,
  }) async {}

  @override
  Future<void> updateKeypairLabel({
    required String profileId,
    required String keypairId,
    required String label,
  }) async {}

  @override
  Future<void> deleteKeypair({
    required String profileId,
    required String keypairId,
  }) async {}

  @override
  Future<void> deleteProfile(String profileId) async {
    deleteProfileCallCount += 1;
    _profiles.removeWhere((p) => p.id == profileId);
    if (_activeProfileId == profileId) {
      _activeProfileId = _profiles.isNotEmpty ? _profiles.first.id : null;
    }
    notifyListeners();
  }

  @override
  Profile? findById(String id) {
    return _profiles.where((p) => p.id == id).firstOrNull;
  }

  @override
  Future<String> exportProfileBackup(String profileId, String password) async {
    throw UnimplementedError();
  }

  @override
  Future<Profile> importProfileBackup(
      String encryptedJson, String password) async {
    throw UnimplementedError();
  }

  @override
  Profile? findByKeypairId(String keypairId) {
    throw UnimplementedError();
  }
}

class _FakeAccountController extends ChangeNotifier
    implements AccountController {
  final Map<String, Account> _accounts = {};
  final Map<String, bool> _availabilityCache = {};
  bool _isBusy = false;

  /// When non-null, [registerAccount] throws this object instead of registering.
  /// Tests set this to simulate marketplace registration failure (UX-CRIT-2).
  Object? registrationFailure;

  @override
  bool get isBusy => _isBusy;

  @override
  Account? getAccount(String username) => _accounts[username];

  @override
  bool hasAccount(String username) => _accounts.containsKey(username);

  @override
  Future<Account> registerAccount({
    required ProfileKeypair keypair,
    required String username,
    required String displayName,
    String? contactEmail,
    String? contactTelegram,
    String? contactTwitter,
    String? contactDiscord,
    String? websiteUrl,
    String? bio,
  }) async {
    _isBusy = true;
    notifyListeners();

    if (registrationFailure != null) {
      _isBusy = false;
      notifyListeners();
      throw registrationFailure!;
    }

    if (_accounts.containsKey(username.toLowerCase())) {
      _isBusy = false;
      notifyListeners();
      throw Exception('Username already taken');
    }

    final account = Account(
      id: 'account-${_accounts.length}',
      username: username.toLowerCase(),
      displayName: displayName,
      publicKeys: [
        AccountPublicKey(
          id: 'key-1',
          publicKey: keypair.publicKey,
          icPrincipal: 'test-principal',
          isActive: true,
          addedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _accounts[username.toLowerCase()] = account;
    _isBusy = false;
    notifyListeners();
    return account;
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    final normalized = username.toLowerCase();
    return !_accounts.containsKey(normalized) &&
        !_availabilityCache.containsKey(normalized);
  }

  @override
  UsernameValidation validateUsername(String username) {
    if (username.isEmpty) {
      return UsernameValidation.invalid('Username is required');
    }
    if (username.length < 3) {
      return UsernameValidation.invalid(
          'Username must be at least 3 characters');
    }
    if (username.length > 32) {
      return UsernameValidation.invalid(
          'Username must be at most 32 characters');
    }
    final validPattern = RegExp(r'^[a-z0-9][a-z0-9_-]*[a-z0-9]$|^[a-z0-9]$');
    if (!validPattern.hasMatch(username.toLowerCase())) {
      return UsernameValidation.invalid(
          'Username can only contain lowercase letters, numbers, _ and -');
    }
    return const UsernameValidation(isValid: true);
  }

  @override
  Future<Account?> fetchAccount(String username) async {
    return _accounts[username.toLowerCase()];
  }

  @override
  Future<Account?> refreshAccount(String username) async {
    return fetchAccount(username);
  }

  @override
  Future<AccountPublicKey> addKeypairToAccount({
    required Profile profile,
    required KeyAlgorithm algorithm,
    String? keypairLabel,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Account?> getAccountForProfile(Profile profile) async {
    if (profile.username == null) return null;
    return _accounts[profile.username!];
  }

  @override
  Future<AccountPublicKey> removePublicKey({
    required String username,
    required String keyId,
    required ProfileKeypair signingKeypair,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Account> updateProfile({
    required String username,
    required ProfileKeypair signingKeypair,
    String? displayName,
    String? contactEmail,
    String? contactTelegram,
    String? contactTwitter,
    String? contactDiscord,
    String? websiteUrl,
    String? bio,
  }) async {
    throw UnimplementedError();
  }

  @override
  void clearCache() {
    _accounts.clear();
    _availabilityCache.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedSetupWizard', () {
    late _FakeProfileController profileController;
    late _FakeAccountController accountController;

    setUp(() {
      profileController = _FakeProfileController();
      accountController = _FakeAccountController();
    });

    group('UI Elements', () {
      testWidgets('displays display name field', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Display Name'), findsOneWidget);
      });

      testWidgets('displays optional username field with skip option',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        // UXR5-5: the field's purpose is folded into a single label so it's
        // unambiguous — no free-floating "Marketplace" chip disconnected from
        // the input it describes.
        expect(find.text('Marketplace username (optional)'), findsOneWidget);
        expect(find.text('Marketplace'), findsNothing,
            reason: 'The bare Marketplace chip must not float above the field; '
                'it is now part of the label.');
      });

      testWidgets('displays create button', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Get Started'), findsWidgets);
      });
    });

    group('Button Behavior', () {
      testWidgets('create button is disabled when display name is empty',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        final button = find.widgetWithText(FilledButton, 'Get Started');
        expect(button, findsOneWidget);

        final filledButton = tester.widget<FilledButton>(button);
        expect(filledButton.onPressed, isNull);
      });

      testWidgets(
          'create button is enabled when display name is filled (local-only)',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Test User');
        await tester.pump();

        final button = find.widgetWithText(FilledButton, 'Get Started');
        final filledButton = tester.widget<FilledButton>(button);
        expect(filledButton.onPressed, isNotNull);
      });

      testWidgets('create button is disabled when username is invalid',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Test User');
        await tester.enterText(find.byType(TextFormField).at(1), 'ab');
        await tester.pump(const Duration(milliseconds: 600));

        final button = find.widgetWithText(FilledButton, 'Get Started');
        final filledButton = tester.widget<FilledButton>(button);
        expect(filledButton.onPressed, isNull);
      });
    });

    group('Local-Only Profile Creation', () {
      testWidgets('creates profile without account when username is empty',
          (tester) async {
        UnifiedSetupResult? result;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<UnifiedSetupResult>(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (context) => UnifiedSetupWizard(
                        profileController: profileController,
                        accountController: accountController,
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

        await tester.enterText(find.byType(TextFormField).first, 'Local User');
        await tester.pump();

        await tester
            .ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Start Exploring'));
        await tester.tap(find.text('Start Exploring'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.profile, isNotNull);
        expect(result!.profile.name, equals('Local User'));
        expect(result!.profile.username, isNull);
        expect(result!.account, isNull);
      });
    });

    group('Full Account Creation', () {
      testWidgets('creates profile and account when username is provided',
          (tester) async {
        UnifiedSetupResult? result;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<UnifiedSetupResult>(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (context) => UnifiedSetupWizard(
                        profileController: profileController,
                        accountController: accountController,
                        connectivityProbe: () async => true,
                        isPasskeySupported: () => false,
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

        await tester.enterText(find.byType(TextFormField).first, 'Full User');
        await tester.enterText(find.byType(TextFormField).at(1), 'fulluser123');
        await tester.pump(const Duration(milliseconds: 600));

        await tester
            .ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        await tester.pumpAndSettle();

        // UX-H6: the security prompt is shown after a successful account
        // registration. Dismiss it to reach the success screen.
        expect(find.text('Secure your account'), findsOneWidget);
        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Start Exploring'));
        await tester.tap(find.text('Start Exploring'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.profile, isNotNull);
        expect(result!.profile.name, equals('Full User'));
        expect(result!.profile.username, equals('fulluser123'));
        expect(result!.account, isNotNull);
        expect(result!.account!.username, equals('fulluser123'));
      });

      testWidgets('shows error when username is already taken', (tester) async {
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        await accountController.registerAccount(
          keypair: keypair,
          username: 'takenuser',
          displayName: 'Existing User',
        );

        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pump();

        await tester.enterText(find.byType(TextFormField).first, 'New User');
        await tester.enterText(find.byType(TextFormField).at(1), 'takenuser');

        await tester.pump(const Duration(milliseconds: 600));

        expect(find.textContaining('already taken'), findsOneWidget);
      });
    });

    group('Registration failure rollback (UX-CRIT-2)', () {
      testWidgets(
          'rolls back the profile when registerAccount throws; retry then succeeds',
          (tester) async {
        // First submit: marketplace registration fails. The wizard must roll
        // back the local profile so a retry doesn't fork into a second orphan.
        accountController.registrationFailure =
            Exception('marketplace is down');

        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
            connectivityProbe: () async => true,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(
            find.byType(TextFormField).first, 'Crashme User');
        await tester.enterText(
            find.byType(TextFormField).at(1), 'crashme123');
        await tester.pump(const Duration(milliseconds: 600));

        await tester
            .ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // Specific error language — NOT the generic "Could not create the
        // profile" message that used to lie about a profile that DID exist.
        expect(find.textContaining('registration failed'), findsOneWidget);
        expect(find.textContaining('Profile created locally, but'),
            findsOneWidget);

        // Rollback worked: no orphan profile, deleteProfile was called once.
        expect(profileController.profiles, isEmpty);
        expect(profileController.deleteProfileCallCount, 1);

        // Second submit: clear the failure and let registration succeed.
        accountController.registrationFailure = null;

        // Re-tap Get Started (same form values are still in the fields).
        await tester
            .ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // Exactly one profile exists — not two.
        expect(profileController.profiles, hasLength(1));
        expect(profileController.deleteProfileCallCount, 1,
            reason: 'rollback must not run again on the successful retry');
      });
    });

    group('Username Validation', () {
      testWidgets('shows validation error for short username', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Test User');
        await tester.enterText(find.byType(TextFormField).at(1), 'ab');
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.textContaining('at least 3'), findsOneWidget);
      });

      testWidgets('shows validation error for invalid characters',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Test User');
        await tester.enterText(find.byType(TextFormField).at(1), '_invalid');
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.textContaining('start'), findsOneWidget);
      });
    });

    group('Success State', () {
      testWidgets('shows success screen after profile creation',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(
            find.byType(TextFormField).first, 'Success User');
        await tester.pump();

        await tester
            .ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(find.text('Success!'), findsOneWidget);
        expect(find.text('Start Exploring'), findsOneWidget);
      });
    });

    group('Keyboard completion (UX-9/UX-10)', () {
      testWidgets(
          'Enter on display name (with empty username) moves focus to the '
          'username field instead of submitting', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Keyboard User');
        await tester.pump();

        // Display name is the first field and has TextInputAction.next.
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();

        final usernameField =
            tester.widget<TextField>(find.byType(TextField).at(1));
        expect(usernameField.focusNode?.hasFocus, isTrue,
            reason: 'Enter on display name should move focus to username.');

        // The wizard has NOT submitted — still on the form screen.
        expect(find.text('Get Started'), findsWidgets);
        expect(find.text('Success!'), findsNothing);
        expect(profileController.profiles, isEmpty);
      });

      testWidgets(
          'Enter on username (valid form) submits the wizard via the keyboard',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
            connectivityProbe: () async => true,
            isPasskeySupported: () => false,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Enter Sub');
        await tester.enterText(find.byType(TextFormField).at(1), 'entersub');
        await tester.pump(const Duration(milliseconds: 600));

        // Username is the last field and has TextInputAction.done.
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        // UX-H6: security prompt appears after account creation; dismiss it
        // to reach the success screen.
        expect(find.text('Secure your account'), findsOneWidget);
        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();

        expect(find.text('Success!'), findsOneWidget,
            reason: 'Enter on the username field should submit the wizard.');
        expect(profileController.profiles, hasLength(1));
        expect(profileController.profiles.first.username, 'entersub');
      });

      testWidgets(
          'Enter on display name with empty value does not move focus and '
          'does not submit (form invalid)', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
          ),
        ));
        await tester.pumpAndSettle();

        // Don't enter anything — display name stays empty.
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();

        // The wizard stays put; no profile created.
        expect(find.text('Get Started'), findsWidgets);
        expect(find.text('Success!'), findsNothing);
        expect(profileController.profiles, isEmpty);
      });
    });

    group('Connectivity precheck (UX-21)', () {
      testWidgets(
          'when the marketplace backend is unreachable, shows a friendly '
          'inline error, creates NO profile, and stays on the wizard',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
            connectivityProbe: () async => false,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Offline User');
        await tester.enterText(find.byType(TextFormField).at(1), 'offline123');
        await tester.pump(const Duration(milliseconds: 600));

        await tester
            .ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        expect(
            find.textContaining("Can't reach the marketplace backend"),
            findsOneWidget,
            reason: 'Connectivity failure must show a friendly inline error.');
        expect(profileController.profiles, isEmpty,
            reason: 'No profile should be persisted when the precheck fails.');
        expect(find.text('Get Started'), findsWidgets,
            reason: 'The wizard must remain on screen.');
        expect(find.text('Success!'), findsNothing);
      });

      testWidgets(
          'when the probe succeeds, registration proceeds normally '
          '(one profile + one account)', (tester) async {
        var probeCalls = 0;
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
            connectivityProbe: () async {
              probeCalls += 1;
              return true;
            },
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Online User');
        await tester.enterText(find.byType(TextFormField).at(1), 'online123');
        await tester.pump(const Duration(milliseconds: 600));

        await tester
            .ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(profileController.profiles, hasLength(1),
            reason: 'Registration should succeed when the probe returns true.');
        expect(profileController.profiles.first.username, 'online123');
        expect(probeCalls, 1,
            reason: 'The probe must be invoked exactly once per submit.');
      });

      testWidgets(
          'skips the probe entirely when the username is empty (local-only)',
          (tester) async {
        var probeCalls = 0;
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
            connectivityProbe: () async {
              probeCalls += 1;
              return false; // would block if invoked
            },
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Local User');
        await tester.pump();

        await tester
            .ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(profileController.profiles, hasLength(1),
            reason: 'Local-only profiles must not require connectivity.');
        expect(probeCalls, 0,
            reason: 'The probe must not fire when the username is empty.');
      });
    });

    // ─────────────────────────────────────────────────────────────────────
    // UX-H6 — post-registration security prompt (vault + passkey).
    // ─────────────────────────────────────────────────────────────────────
    // Both onboarding wizards call the shared
    // `showPostRegistrationSecurityPrompt` helper after a successful account
    // registration. Local-only profiles (no marketplace username) skip the
    // prompt entirely — vault + passkey are account-scoped.
    group('UX-H6 post-registration security prompt', () {
      /// Shared pump harness — fills the form, submits, and waits for the
      /// prompt to appear. Caller then drives the prompt (tap a tile or
      /// Skip). Returns once the dialog is on screen.
      Future<void> fillAndSubmitAndWaitForPrompt(
        WidgetTester tester, {
        bool Function()? isPasskeySupported,
      }) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
            connectivityProbe: () async => true,
            isPasskeySupported:
                isPasskeySupported ?? (() => true),
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Alice');
        await tester.enterText(
            find.byType(TextFormField).at(1), 'alice123');
        await tester.pump(const Duration(milliseconds: 600));

        await tester
            .ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(find.text('Secure your account'), findsOneWidget,
            reason: 'UX-H6: shared security prompt must appear after a '
                'successful account registration.');
      }

      testWidgets(
          'shows the prompt with vault + passkey tiles after registering an '
          'account', (tester) async {
        await fillAndSubmitAndWaitForPrompt(tester);

        expect(find.text('Set up vault password'), findsOneWidget);
        expect(find.text('Enroll a passkey'), findsOneWidget);
        expect(find.text('Skip for now'), findsOneWidget);

        // Body acknowledges the just-registered @username.
        expect(find.textContaining('@alice123'), findsOneWidget);
      });

      testWidgets(
          'does NOT show the prompt after a local-only profile creation '
          '(no account)', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: UnifiedSetupWizard(
            profileController: profileController,
            accountController: accountController,
            isPasskeySupported: () => true,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Local');
        await tester.pump();

        await tester
            .ensureVisible(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        // Local-only: no account, so neither vault nor passkey applies — the
        // success screen shows directly.
        expect(find.text('Secure your account'), findsNothing,
            reason: 'UX-H6: prompt only fires when an account was registered.');
        expect(find.text('Success!'), findsOneWidget);
      });

      testWidgets(
          'tap "Set up vault password" pushes VaultPasswordSetupScreen; the '
          'success screen follows once the vault screen is popped',
          (tester) async {
        await fillAndSubmitAndWaitForPrompt(tester);

        await tester.tap(find.text('Set up vault password'));
        await tester.pumpAndSettle();

        expect(find.byType(VaultPasswordSetupScreen), findsOneWidget,
            reason: 'UX-H6: tapping the vault tile pushes the vault screen.');

        // Simulate the user finishing vault setup (pop the vault screen).
        final NavigatorState navigator =
            tester.state(find.byType(Navigator).first);
        navigator.pop();
        await tester.pumpAndSettle();

        // The wizard's success screen is now shown.
        expect(find.text('Success!'), findsOneWidget);
        expect(find.text('Start Exploring'), findsOneWidget);
      });

      testWidgets(
          'tap "Enroll a passkey" pushes PasskeyManagementScreen; the '
          'success screen follows once the passkey screen is popped',
          (tester) async {
        await fillAndSubmitAndWaitForPrompt(tester);

        await tester.tap(find.text('Enroll a passkey'));
        await tester.pumpAndSettle();

        expect(find.byType(PasskeyManagementScreen), findsOneWidget,
            reason: 'UX-H6: tapping the passkey tile pushes the passkey '
                'management screen.');

        // Simulate the user finishing passkey enrollment (pop).
        final NavigatorState navigator =
            tester.state(find.byType(Navigator).first);
        navigator.pop();
        await tester.pumpAndSettle();

        expect(find.text('Success!'), findsOneWidget);
        expect(find.text('Start Exploring'), findsOneWidget);
      });

      testWidgets(
          'tap "Skip for now" closes the prompt and shows the success screen',
          (tester) async {
        await fillAndSubmitAndWaitForPrompt(tester);

        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();

        expect(find.text('Secure your account'), findsNothing,
            reason: 'Skip dismisses the dialog.');
        expect(find.text('Success!'), findsOneWidget);
        expect(find.text('Start Exploring'), findsOneWidget);
      });

      testWidgets(
          'when isPasskeySupported returns false, the passkey tile is '
          'disabled but the prompt still appears with the vault tile '
          'available', (tester) async {
        await fillAndSubmitAndWaitForPrompt(
          tester,
          isPasskeySupported: () => false,
        );

        // Passkey tile paints (never silently disappears)...
        expect(find.text('Enroll a passkey'), findsOneWidget);
        // ...with the honest "this device doesn't support them" copy.
        expect(find.textContaining("doesn't support them"), findsOneWidget);

        // The vault tile is fully actionable.
        await tester.tap(find.text('Set up vault password'));
        await tester.pumpAndSettle();
        expect(find.byType(VaultPasswordSetupScreen), findsOneWidget);
      });
    });
  });
}
