import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:mocktail/mocktail.dart';

import '../shared/test_keypair_factory.dart';
import 'profile_menu_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerProfileMenuFallbacks);

  group('Profile menu first-run (UX-B1)', () {
    late MockAccountController mockAccountController;
    late MockPasskeyService mockPasskeyService;

    setUp(() async {
      mockAccountController = MockAccountController();
      mockPasskeyService = MockPasskeyService();
      when(() => mockPasskeyService.listPasskeys(any()))
          .thenAnswer((_) async => []);
    });

    Future<ProfileController> buildEmptyController() =>
        buildProfileController(keypairs: const []);

    Future<ProfileController> buildControllerWithProfile() async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      return buildProfileController(keypairs: [keypair]);
    }

    Future<void> pumpMenu(
      WidgetTester tester,
      ProfileController profileController,
    ) async {
      await pumpProfileMenuHost(
        tester,
        profileController: profileController,
        accountController: mockAccountController,
        passkeyService: mockPasskeyService,
      );
    }

    testWidgets(
        'first-run: the My Account tile is rendered and routes to profile '
        'creation instead of being a silent no-op', (tester) async {
      final profileController = await buildEmptyController();
      expect(profileController.profiles, isEmpty);
      expect(profileController.activeProfile, isNull);

      await pumpMenu(tester, profileController);

      // The tile is present even with no active profile ...
      expect(find.text('My Account'), findsOneWidget);
      expect(find.text('Create a profile to get started'), findsOneWidget);

      // ... and tapping it opens the creation surface (no longer a no-op).
      await tester.tap(find.text('My Account'));
      // Bounded pumps (NOT pumpAndSettle) — UnifiedSetupWizard has continuous
      // focus/transition animations that prevent pumpAndSettle from returning.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));

      // The wizard's primary CTA is "Get Started" (UnifiedSetupWizard uses
      // this consistently across its 3 mount points).
      expect(find.text('Get Started'), findsOneWidget,
          reason: 'first-run My Account tap must open the setup wizard '
              '(CTA: "Get Started").');
    });

    testWidgets(
        'with an active profile the first-run CTA is not shown '
        '(first-run path is correctly scoped)', (tester) async {
      final profileController = await buildControllerWithProfile();
      expect(profileController.profiles, isNotEmpty);
      expect(profileController.activeProfile, isNotNull);

      await pumpMenu(tester, profileController);

      // With an active profile present, the first-run CTA is not shown.
      expect(find.text('Create a profile to get started'), findsNothing);
      expect(find.text('My Account'), findsOneWidget);
    });
  });
}
