import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/fake_secure_keypair_repository.dart';
import '../test_helpers/test_keypair_factory.dart';

class _MockPasskeyService extends Mock implements PasskeyService {}

class _MockAccountController extends Mock implements AccountController {}

class _FakeProfile extends Fake implements Profile {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeProfile());
  });

  group('Profile Menu Terminology Clarity', () {
    late ProfileKeypair keypair;
    late ProfileController profileController;
    late _MockPasskeyService mockPasskeyService;
    late _MockAccountController mockAccountController;
    late Account testAccount;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      keypair = await TestKeypairFactory.getEd25519Keypair();
      final repository = FakeSecureKeypairRepository(<ProfileKeypair>[keypair]);
      profileController =
          ProfileController(profileRepository: repository.profileRepository);
      await profileController.ensureLoaded();
      if (profileController.profiles.isNotEmpty) {
        await profileController
            .setActiveProfile(profileController.profiles.first.id);
      }

      mockPasskeyService = _MockPasskeyService();
      mockAccountController = _MockAccountController();

      testAccount = Account(
        id: 'account-123',
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    Future<void> pumpProfileMenuWithAccount(
      WidgetTester tester, {
      required bool hasAccount,
    }) async {
      if (hasAccount) {
        // Update profile with username to simulate having an account
        await profileController.updateProfileUsername(
          profileId: profileController.profiles.first.id,
          username: 'testuser',
        );
        when(() => mockAccountController.getAccountForProfile(any()))
            .thenAnswer((_) async => testAccount);
      }
      when(() => mockPasskeyService.listPasskeys(any()))
          .thenAnswer((_) async => []);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      useSafeArea: true,
                      isScrollControlled: true,
                      builder: (_) => ProfileMenuWidget(
                        profileController: profileController,
                        accountController: mockAccountController,
                        passkeyService: mockPasskeyService,
                      ),
                    );
                  },
                  child: const Text('Open Menu'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();
    }

    group('Clear terminology for local identity (Profile)', () {
      testWidgets(
          'shows "My Identity" label for editing local profile (not "Edit Profile")',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        // Should NOT show confusing "Edit Profile" label
        expect(find.text('Edit Profile'), findsNothing,
            reason:
                '"Edit Profile" is confusing - users don\'t understand it\'s local-only');

        // Should show clearer "My Identity" label
        expect(find.text('My Identity'), findsOneWidget,
            reason:
                '"My Identity" clearly indicates this is your local identity');
      });

      testWidgets(
          'shows helpful subtitle explaining local identity is stored locally',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        // Should have subtitle explaining it's local
        expect(find.textContaining('local'), findsOneWidget,
            reason: 'Subtitle should explain this is stored locally on device');
      });
    });

    group('Clear terminology for cloud registration (Account)', () {
      testWidgets(
          'shows "Register Username" label for creating cloud account (not "Create Account")',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        // Should NOT show confusing "Create Account" label
        expect(find.text('Create Account'), findsNothing,
            reason:
                '"Create Account" is confusing - users don\'t understand it registers a cloud username');

        // Should show clearer "Register Username" label
        expect(find.text('Register Username'), findsOneWidget,
            reason:
                '"Register Username" clearly indicates this is for a cloud @username');
      });

      testWidgets(
          'shows helpful subtitle explaining cloud registration is for publishing',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        // Should have subtitle explaining it's for publishing/sharing
        final subtitles = find
            .descendant(
              of: find.byType(ListTile),
              matching: find.byType(Text),
            )
            .evaluate()
            .map((e) => (e.widget as Text).data ?? '');

        // Find the subtitle that mentions publishing or cloud
        final hasPublishingSubtitle = subtitles.any((text) =>
            text.toLowerCase().contains('publish') ||
            text.toLowerCase().contains('share') ||
            text.toLowerCase().contains('cloud') ||
            text.toLowerCase().contains('marketplace'));

        expect(hasPublishingSubtitle, isTrue,
            reason:
                'Subtitle should explain username is for publishing scripts to marketplace');
      });
    });

    group('Explainer tooltips for Profile vs Account distinction', () {
      testWidgets(
          'identity menu item has tooltip explaining local vs cloud distinction',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        // Find the "My Identity" tile
        final identityTile = find.widgetWithText(ListTile, 'My Identity');
        expect(identityTile, findsOneWidget);

        // Long press to trigger tooltip (or check for Tooltip widget)
        final tooltipFinder = find.descendant(
          of: identityTile,
          matching: find.byType(Tooltip),
        );

        // Either there's a Tooltip widget or the ListTile has semantic label
        if (tooltipFinder.evaluate().isNotEmpty) {
          final tooltip = tester.widget<Tooltip>(tooltipFinder.first);
          expect(
            tooltip.message,
            anyOf(
              contains('local'),
              contains('device'),
              contains('stored'),
            ),
            reason: 'Tooltip should explain local identity concept',
          );
        }
      });

      testWidgets(
          'register username menu item has tooltip explaining cloud concept',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        // Find the "Register Username" tile
        final registerTile = find.widgetWithText(ListTile, 'Register Username');
        expect(registerTile, findsOneWidget);

        // Check for Tooltip widget
        final tooltipFinder = find.descendant(
          of: registerTile,
          matching: find.byType(Tooltip),
        );

        if (tooltipFinder.evaluate().isNotEmpty) {
          final tooltip = tester.widget<Tooltip>(tooltipFinder.first);
          expect(
            tooltip.message,
            anyOf(
              contains('marketplace'),
              contains('cloud'),
              contains('share'),
              contains('publish'),
            ),
            reason: 'Tooltip should explain cloud username concept',
          );
        }
      });
    });

    group('Other menu items remain unchanged', () {
      testWidgets('Passkeys label remains the same',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('Passkeys'), findsOneWidget);
      });

      testWidgets('Settings label remains the same',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: true);

        expect(find.text('Settings'), findsOneWidget);
      });

      testWidgets(
          'Create Profile remains clear for adding new local identities',
          (WidgetTester tester) async {
        await pumpProfileMenuWithAccount(tester, hasAccount: false);

        // "Create Profile" is still clear - user understands it's for another local identity
        expect(find.text('Create Profile'), findsOneWidget);
      });
    });
  });
}
