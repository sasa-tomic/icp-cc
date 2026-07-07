import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/screens/account_profile_screen.dart';

import 'account_profile_test_helpers.dart';
import '../../shared/test_keypair_factory.dart';

/// Key-label editing (HIGH-priority product gap #2).
///
/// The keypair label is a profile-scoped LOCAL attribute
/// (`ProfileKeypair.label`, persisted in secure storage). The backend
/// `account_public_keys` table has NO label column, so renaming is a purely
/// client-side operation routed through `ProfileController.updateKeypairLabel`.
/// These tests prove the UI round-trips the rename end-to-end (positive), that
/// an empty label is rejected (negative), and that cancelling is a no-op.
void main() {
  setUpAll(() {
    AccountProfileScreenTestHelper.registerFallbackValues();
  });

  group('AccountProfileScreen — key label editing (local-only)', () {
    late MockAccountController accountController;
    late MockProfileController profileController;

    setUp(() {
      accountController = MockAccountController();
      profileController = MockProfileController();
      // Local-only mode must not call refreshAccount — left un-stubbed as a
      // fail-fast guard (mocktail throws on any unexpected call).
    });

    Future<void> pumpLocalOnly(WidgetTester tester,
        {required Profile profile}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfileScreen(
            account: null, // local-only
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
        'tapping the label opens a rename dialog and persists the new label '
        'via ProfileController.updateKeypairLabel', (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'profile-local',
        name: 'Alice',
        keypairs: [keypair],
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now(),
      );
      // After the rename, the controller surfaces a profile whose keypair
      // carries the new label.
      final renamedProfile = profile.copyWith(
        keypairs: [keypair.copyWith(label: 'Laptop')],
      );

      when(() => profileController.updateKeypairLabel(
            profileId: any(named: 'profileId'),
            keypairId: any(named: 'keypairId'),
            label: any(named: 'label'),
          )).thenAnswer((_) async {});
      when(() => profileController.findById(any())).thenReturn(renamedProfile);

      await pumpLocalOnly(tester, profile: profile);

      // The original label is shown.
      expect(find.text(keypair.label), findsOneWidget);

      // Tap the inline edit affordance on the label (scroll it into view first
      // — the key card sits below the fold in the default test viewport).
      await tester.ensureVisible(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Edit Key Label'), findsOneWidget);

      // Enter a new label.
      await tester.enterText(find.byType(TextField), 'Laptop');
      await tester.pump();

      // Save (the FilledButton labelled exactly 'Save').
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // The controller received the rename with the exact arguments.
      verify(() => profileController.updateKeypairLabel(
            profileId: 'profile-local',
            keypairId: keypair.id,
            label: 'Laptop',
          )).called(1);
      // The new label renders immediately; the old one is gone.
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text(keypair.label), findsNothing);
      expect(find.text('Label updated'), findsOneWidget);
    });

    testWidgets('an empty label is rejected (Save disabled)', (tester) async {
      final keypair = await TestKeypairFactory.getEd25519Keypair();
      final profile = Profile(
        id: 'profile-local',
        name: 'Alice',
        keypairs: [keypair],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await pumpLocalOnly(tester, profile: profile);

      await tester.ensureVisible(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Clear the field entirely.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      // The Save button must be disabled for an empty label.
      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull,
          reason: 'Save must be disabled when the label is empty.');

      // And no rename must have been issued.
      verifyNever(() => profileController.updateKeypairLabel(
            profileId: any(named: 'profileId'),
            keypairId: any(named: 'keypairId'),
            label: any(named: 'label'),
          ));
    });

    testWidgets('cancelling the rename is a no-op (no controller call)',
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

      await tester.ensureVisible(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Whatever');
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog dismissed, original label unchanged, no controller call.
      expect(find.text('Edit Key Label'), findsNothing);
      expect(find.text(keypair.label), findsOneWidget);
      verifyNever(() => profileController.updateKeypairLabel(
            profileId: any(named: 'profileId'),
            keypairId: any(named: 'keypairId'),
            label: any(named: 'label'),
          ));
    });
  });

  group('AccountProfileScreen — key label editing (registered)', () {
    late MockAccountController accountController;
    late MockProfileController profileController;

    setUp(() {
      accountController = MockAccountController();
      profileController = MockProfileController();
      when(() => accountController.refreshAccount(any()))
          .thenAnswer((_) async => null);
    });

    testWidgets(
        'a registered key with a matching local keypair shows the LOCAL label '
        '(not the truncated public key) and is editable', (tester) async {
      final setup =
          await AccountProfileScreenTestHelper.createMatchingAccountAndProfile(
        username: 'alice',
        displayName: 'Alice',
        keyCount: 1,
      );
      final account = setup.account;
      final profile = setup.profile;
      final keypair = profile.keypairs.single;

      final renamedProfile = profile.copyWith(
        keypairs: [keypair.copyWith(label: 'Cold backup')],
      );

      when(() => profileController.updateKeypairLabel(
            profileId: any(named: 'profileId'),
            keypairId: any(named: 'keypairId'),
            label: any(named: 'label'),
          )).thenAnswer((_) async {});
      when(() => profileController.findById(any())).thenReturn(renamedProfile);

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Expand the Public Keys section to reveal the key card.
      final publicKeyTile = find.ancestor(
        of: find.text('Public Keys'),
        matching: find.byType(ExpansionTile),
      );
      await tester.ensureVisible(publicKeyTile);
      await tester.pumpAndSettle();
      await tester.tap(publicKeyTile);
      await tester.pumpAndSettle();

      // The local label (not the truncated public key) is rendered for a
      // registered key we own locally.
      await tester.ensureVisible(find.text(keypair.label));
      await tester.pumpAndSettle();
      expect(find.text(keypair.label), findsOneWidget);

      // Edit the label.
      await tester.ensureVisible(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Scope to the dialog's TextField — the registered screen has many edit
      // fields behind the dialog.
      final dialogTextField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogTextField, 'Cold backup');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      verify(() => profileController.updateKeypairLabel(
            profileId: profile.id,
            keypairId: keypair.id,
            label: 'Cold backup',
          )).called(1);
      expect(find.text('Cold backup'), findsOneWidget);
      expect(find.text(keypair.label), findsNothing);
    });
  });
}
