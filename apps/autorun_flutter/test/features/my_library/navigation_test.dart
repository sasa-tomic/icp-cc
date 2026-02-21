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

import '../../test_helpers/fake_secure_keypair_repository.dart';
import '../../test_helpers/test_keypair_factory.dart';

class _MockPasskeyService extends Mock implements PasskeyService {}

class _MockAccountController extends Mock implements AccountController {}

class _FakeProfile extends Fake implements Profile {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeProfile());
  });

  group('My Library navigation from Profile Menu', () {
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

    Future<void> pumpProfileMenu(WidgetTester tester) async {
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);
      when(() => mockPasskeyService.listPasskeys(any()))
          .thenAnswer((_) async => []);

      await profileController.updateProfileUsername(
        profileId: profileController.profiles.first.id,
        username: 'testuser',
      );

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
          routes: {
            '/my-library': (context) =>
                const Scaffold(body: Text('My Library Screen')),
          },
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows My Library option in profile menu', (tester) async {
      await pumpProfileMenu(tester);

      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('My Library'), findsOneWidget);
    });

    testWidgets('My Library shows subtitle describing content', (tester) async {
      await pumpProfileMenu(tester);

      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      final libraryTile = find.ancestor(
        of: find.text('My Library'),
        matching: find.byType(ListTile),
      );
      expect(libraryTile, findsOneWidget);

      expect(find.text('Downloads, favorites, and scripts'), findsOneWidget);
    });

    testWidgets('My Library has library icon', (tester) async {
      await pumpProfileMenu(tester);

      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      final icon = find.byIcon(Icons.folder_special_outlined);
      expect(icon, findsOneWidget);
    });

    testWidgets('tapping My Library navigates to MyLibraryScreen',
        (tester) async {
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => testAccount);
      when(() => mockPasskeyService.listPasskeys(any()))
          .thenAnswer((_) async => []);

      await profileController.updateProfileUsername(
        profileId: profileController.profiles.first.id,
        username: 'testuser',
      );

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

      await tester.tap(find.text('My Library'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('My Library'), findsWidgets);
    });

    testWidgets('My Library is positioned after Manage Account',
        (tester) async {
      await pumpProfileMenu(tester);

      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      final menuItems =
          tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      final labels = menuItems
          .map((tile) => (tile.title as Text?)?.data)
          .where((label) => label != null)
          .toList();

      final manageAccountIndex = labels.indexOf('Manage Account');
      final myLibraryIndex = labels.indexOf('My Library');

      expect(manageAccountIndex, greaterThanOrEqualTo(0));
      expect(myLibraryIndex, greaterThanOrEqualTo(0));
      expect(myLibraryIndex, greaterThan(manageAccountIndex));
    });
  });
}
