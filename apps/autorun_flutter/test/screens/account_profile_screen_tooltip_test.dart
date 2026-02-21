import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/screens/account_profile_screen.dart';
import 'package:icp_autorun/utils/tech_terms.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/fake_secure_keypair_repository.dart';
import '../test_helpers/test_keypair_factory.dart';

class _MockAccountController extends Mock implements AccountController {}

class _FakeProfile extends Fake implements Profile {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeProfile());
  });

  group('Account Profile Screen Contextual Help', () {
    late ProfileKeypair keypair;
    late ProfileController profileController;
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
        await profileController.updateProfileUsername(
          profileId: profileController.profiles.first.id,
          username: 'testuser',
        );
      }

      mockAccountController = _MockAccountController();

      testAccount = Account(
        id: 'account-123',
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountPublicKey(
            id: 'key-1',
            publicKey: keypair.publicKey,
            icPrincipal: 'test-principal',
            addedAt: DateTime.now(),
            label: 'Test Key',
            isActive: true,
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => mockAccountController.refreshAccount(any()))
          .thenAnswer((_) async => testAccount);
    });

    Future<void> pumpAccountProfileScreen(WidgetTester tester) async {
      final profile = profileController.activeProfile!;

      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfileScreen(
            account: testAccount,
            accountController: mockAccountController,
            profile: profile,
            profileController: profileController,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Passkeys section has tooltip explaining what passkeys are',
        (WidgetTester tester) async {
      await pumpAccountProfileScreen(tester);

      final passkeysText = find.text('Passkeys');
      expect(passkeysText, findsOneWidget,
          reason: 'Passkeys section should be visible');

      final tooltip = tester.widget<Tooltip>(
        find
            .ancestor(
              of: passkeysText,
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(tooltip.message, TechTerm.passkey.fullExplanation,
          reason:
              'Passkeys title should have tooltip with full explanation of what passkeys are');
    });

    testWidgets('Passkeys section has info icon indicating tooltip',
        (WidgetTester tester) async {
      await pumpAccountProfileScreen(tester);

      final passkeysRow = find.ancestor(
        of: find.text('Passkeys'),
        matching: find.byType(Row),
      );

      expect(
          find.descendant(
              of: passkeysRow, matching: find.byIcon(Icons.info_outline)),
          findsOneWidget,
          reason:
              'Passkeys row should have an info icon indicating tooltip availability');
    });
  });
}
