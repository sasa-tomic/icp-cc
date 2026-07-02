import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/fake_secure_keypair_repository.dart';
import '../shared/test_keypair_factory.dart';

class _MockPasskeyService extends Mock implements PasskeyService {}

class _MockAccountController extends Mock implements AccountController {}

class _FakeProfile extends Fake implements Profile {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeProfile());
  });

  group('WU-4 inline profile switch (>1 profile)', () {
    late ProfileController profileController;
    late _MockPasskeyService mockPasskeyService;
    late _MockAccountController mockAccountController;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final keypair1 = await TestKeypairFactory.fromSeed(1);
      final keypair2 = await TestKeypairFactory.fromSeed(2);
      final repository =
          FakeSecureKeypairRepository(<ProfileKeypair>[keypair1, keypair2]);
      profileController =
          ProfileController(profileRepository: repository.profileRepository);
      await profileController.ensureLoaded();
      await profileController
          .setActiveProfile(profileController.profiles.first.id);

      mockPasskeyService = _MockPasskeyService();
      mockAccountController = _MockAccountController();
      when(() => mockPasskeyService.listPasskeys(any()))
          .thenAnswer((_) async => []);
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => null);
    });

    Future<void> pumpMenu(WidgetTester tester) async {
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

    testWidgets(
        'inlines the profile list instead of a single "Switch Profile" tile',
        (tester) async {
      await pumpMenu(tester);

      // Each profile is rendered directly in the menu.
      expect(find.text(profileController.profiles[0].name), findsWidgets);
      expect(find.text(profileController.profiles[1].name), findsOneWidget);

      // The legacy single "Switch Profile" tile is replaced by the list ...
      expect(find.text('Switch Profile'), findsNothing,
          reason: 'inline list replaces the Switch Profile tile for >1 profile');
      // ... while the full-sheet entry stays reachable for create/rename/delete.
      expect(find.text('Manage Profiles'), findsOneWidget);
    });

    testWidgets('marks the active profile with a check indicator',
        (tester) async {
      await pumpMenu(tester);

      expect(find.byIcon(Icons.check_circle), findsOneWidget,
          reason: 'only the active profile row shows a check');
    });

    testWidgets('switches in 2 taps via the controller and closes the menu',
        (tester) async {
      final firstId = profileController.profiles.first.id;
      final second = profileController.profiles[1];
      expect(profileController.activeProfileId, equals(firstId));

      await pumpMenu(tester);

      // Tap 1 opened the menu in pumpMenu; tap 2 is the inline row.
      await tester.tap(find.text(second.name));
      await tester.pumpAndSettle();

      // Menu dismissed: inline entry gone, opener visible again.
      expect(find.text('Manage Profiles'), findsNothing);
      expect(find.text('Open Menu'), findsOneWidget);

      // Switch routed through setActiveProfile (same path as the manage sheet),
      // so keypair/script scoping follows the newly active profile.
      expect(profileController.activeProfileId, equals(second.id));
      expect(profileController.activeProfile?.name, equals(second.name));
    });
  });

  group('WU-4 many profiles (menu scrolls)', () {
    testWidgets('an off-screen profile stays reachable via scroll', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final keypairs = <ProfileKeypair>[
        for (var seed = 1; seed <= 4; seed++)
          await TestKeypairFactory.fromSeed(seed),
      ];
      final repository = FakeSecureKeypairRepository(keypairs);
      final profileController =
          ProfileController(profileRepository: repository.profileRepository);
      await profileController.ensureLoaded();
      await profileController.setActiveProfile(profileController.profiles.first.id);

      final mockPasskeyService = _MockPasskeyService();
      final mockAccountController = _MockAccountController();
      when(() => mockPasskeyService.listPasskeys(any()))
          .thenAnswer((_) async => []);
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => null);

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

      // The last profile and Settings are rendered even when the menu is tall.
      final last = profileController.profiles.last;
      expect(find.text(last.name), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      // Bring the last row into view and switch to it via the inline list.
      await tester.scrollUntilVisible(
        find.text(last.name),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(last.name));
      await tester.pumpAndSettle();

      expect(profileController.activeProfileId, equals(last.id));
    });
  });

  group('WU-4 single profile (no clutter)', () {
    late ProfileController profileController;
    late _MockPasskeyService mockPasskeyService;
    late _MockAccountController mockAccountController;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final repository = FakeSecureKeypairRepository(<ProfileKeypair>[keypair]);
      profileController =
          ProfileController(profileRepository: repository.profileRepository);
      await profileController.ensureLoaded();
      await profileController
          .setActiveProfile(profileController.profiles.first.id);

      mockPasskeyService = _MockPasskeyService();
      mockAccountController = _MockAccountController();
      when(() => mockPasskeyService.listPasskeys(any()))
          .thenAnswer((_) async => []);
      when(() => mockAccountController.getAccountForProfile(any()))
          .thenAnswer((_) async => null);
    });

    Future<void> pumpMenu(WidgetTester tester) async {
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

    testWidgets('keeps the compact Switch Profile entry, no inline list',
        (tester) async {
      await pumpMenu(tester);

      expect(find.text('Switch Profile'), findsOneWidget);
      expect(find.text('Manage Profiles'), findsNothing,
          reason: 'no inline switcher section for a single profile');
      expect(find.text('Switch profile'), findsNothing);
    });
  });
}
