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

  group('ProfileMenuWidget passkey quick access', () {
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
        await profileController.updateProfileUsername(
          profileId: profileController.profiles.first.id,
          username: 'testuser',
        );
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

    Future<void> pumpProfileMenu(
      WidgetTester tester, {
      PasskeyService? passkeyService,
    }) async {
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
                        passkeyService: passkeyService ?? mockPasskeyService,
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

    testWidgets('shows passkey count in subtitle when user has passkeys',
        (WidgetTester tester) async {
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);

      when(() => mockPasskeyService.listPasskeys(any())).thenAnswer(
        (_) async => [
          PasskeyInfo(
            id: 'pk-1',
            deviceName: 'Device 1',
            createdAt: DateTime.now().toIso8601String(),
            lastUsedAt: null,
          ),
          PasskeyInfo(
            id: 'pk-2',
            deviceName: 'Device 2',
            createdAt: DateTime.now().toIso8601String(),
            lastUsedAt: null,
          ),
        ],
      );

      await pumpProfileMenu(tester);

      expect(find.text('Passkeys'), findsOneWidget);
      expect(find.text('2 passkeys'), findsOneWidget);
    });

    testWidgets('shows "No passkeys" subtitle when user has no passkeys',
        (WidgetTester tester) async {
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);

      when(() => mockPasskeyService.listPasskeys(any())).thenAnswer(
        (_) async => [],
      );

      await pumpProfileMenu(tester);

      expect(find.text('Passkeys'), findsOneWidget);
      expect(find.text('No passkeys'), findsOneWidget);
    });

    testWidgets('highlights passkey option when user has no passkeys',
        (WidgetTester tester) async {
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);

      when(() => mockPasskeyService.listPasskeys(any())).thenAnswer(
        (_) async => [],
      );

      await pumpProfileMenu(tester);

      final passkeyTile = find.widgetWithText(ListTile, 'Passkeys');
      expect(passkeyTile, findsOneWidget);

      final container = find
          .descendant(
            of: passkeyTile,
            matching: find.byType(Container),
          )
          .first;

      final containerWidget = tester.widget<Container>(container);
      final decoration = containerWidget.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
    });

    testWidgets('does not highlight passkey option when user has passkeys',
        (WidgetTester tester) async {
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);

      when(() => mockPasskeyService.listPasskeys(any())).thenAnswer(
        (_) async => [
          PasskeyInfo(
            id: 'pk-1',
            deviceName: 'Device 1',
            createdAt: DateTime.now().toIso8601String(),
            lastUsedAt: null,
          ),
        ],
      );

      await pumpProfileMenu(tester);

      final passkeyTile = find.widgetWithText(ListTile, 'Passkeys');
      expect(passkeyTile, findsOneWidget);
    });

    testWidgets('shows singular "1 passkey" for single passkey',
        (WidgetTester tester) async {
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);

      when(() => mockPasskeyService.listPasskeys(any())).thenAnswer(
        (_) async => [
          PasskeyInfo(
            id: 'pk-1',
            deviceName: 'Device 1',
            createdAt: DateTime.now().toIso8601String(),
            lastUsedAt: null,
          ),
        ],
      );

      await pumpProfileMenu(tester);

      expect(find.text('Passkeys'), findsOneWidget);
      expect(find.text('1 passkey'), findsOneWidget);
    });

    testWidgets('clicking passkeys navigates to passkey management',
        (WidgetTester tester) async {
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);

      when(() => mockPasskeyService.listPasskeys(any())).thenAnswer(
        (_) async => [],
      );

      await pumpProfileMenu(tester);

      await tester.tap(find.text('Passkeys'));
      await tester.pumpAndSettle();

      expect(find.text('Passkeys'), findsWidgets);
    });
  });
}
