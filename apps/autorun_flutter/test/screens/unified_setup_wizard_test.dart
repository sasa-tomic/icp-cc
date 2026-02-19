import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';

import '../test_helpers/test_keypair_factory.dart';

class _FakeProfileController extends ChangeNotifier
    implements ProfileController {
  final List<Profile> _profiles = [];
  bool _isBusy = false;
  String? _activeProfileId;

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
  Future<void> deleteProfile(String profileId) async {}

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

        expect(find.text('Username (optional)'), findsOneWidget);
        expect(find.text('Marketplace'), findsOneWidget);
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
  });
}
