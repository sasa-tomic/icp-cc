import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/screens/account_profile_screen.dart';

import 'account_profile_test_helpers.dart';
import '../../shared/test_keypair_factory.dart';

/// UX-7 — locally-owned keypairs must be visible and manageable on the Account
/// screen WITHOUT backend registration. A new user who created a profile (and
/// therefore already owns ≥1 local keypair) but has NOT registered a marketplace
/// account must still see their keypair(s) — label, public key, IC principal —
/// plus a clear path to register.
void main() {
  setUpAll(() {
    AccountProfileScreenTestHelper.registerFallbackValues();
  });

  group('AccountProfileScreen — local-only (UX-7)', () {
    late MockAccountController accountController;
    late MockProfileController profileController;

    setUp(() {
      accountController = MockAccountController();
      profileController = MockProfileController();
      // Local-only mode must NOT call refreshAccount (no backend). If it ever
      // did, mocktail would throw (missing stub) — so leaving this un-stubbed is
      // itself a fail-fast guard.
    });

    Future<void> pumpLocalOnly(WidgetTester tester, {required Profile profile}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfileScreen(
            account: null, // <-- no backend registration
            accountController: accountController,
            profile: profile,
            profileController: profileController,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets(
        'renders the local keypair (label + public-key row) with no registered '
        'account', (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'profile-local',
        name: 'Alice',
        keypairs: [keypair],
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now(),
      );

      await pumpLocalOnly(tester, profile: profile);

      // The keypair's own label is visible (proves local keys are surfaced).
      expect(find.text(keypair.label), findsOneWidget,
          reason: 'The local keypair label must be visible without registration.');
      // The public-key row label is present.
      expect(find.text('Public Key'), findsOneWidget);
      // Count badge reflects the LOCAL profile keypair count.
      expect(find.text('1/10'), findsOneWidget);
      // Signing-key badge: the single keypair is the active signing key.
      expect(find.text('SIGNING KEY'), findsOneWidget);
    });

    testWidgets('shows the IC principal of the local keypair', (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'profile-local',
        name: 'Alice',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await pumpLocalOnly(tester, profile: profile);

      // Principal is computed by the real FFI (TestKeypairFactory uses real
      // crypto) and surfaced on the local key card.
      expect(keypair.principal, isNotNull,
          reason: 'Test fixture should carry a real principal from the FFI.');
      expect(find.text('IC Principal'), findsOneWidget);
      expect(find.text(keypair.principal!), findsOneWidget);
    });

    testWidgets('shows an honest "not registered" badge and a register CTA',
        (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'profile-local',
        name: 'Alice',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await pumpLocalOnly(tester, profile: profile);

      expect(find.text('Local profile — not registered'), findsOneWidget);
      expect(find.text('Register an account'), findsWidgets);
      // The local profile name is shown (not an @username, which needs backend).
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows the Add Key FAB (local keypair generation affordance)',
        (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'profile-local',
        name: 'Alice',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await pumpLocalOnly(tester, profile: profile);

      expect(find.text('Add Key'), findsOneWidget);
    });

    testWidgets('local-only mode makes NO backend refresh call', (tester) async {
      // Fail-fast: if a future change reintroduces refreshAccount() in
      // local-only mode, this mock's strict stubbing throws.
      verifyNever(() => accountController.refreshAccount(any()));

      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'profile-local',
        name: 'Alice',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await pumpLocalOnly(tester, profile: profile);

      verifyNever(() => accountController.refreshAccount(any()));
    });
  });
}
