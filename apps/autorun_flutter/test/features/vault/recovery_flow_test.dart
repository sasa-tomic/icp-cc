// F1 fix — recovery-code flow is no longer a dead route.
//
// Before: VaultUnlockScreen._useRecoveryCode called
//   Navigator.pushNamed(context, '/recovery')
// which threw at runtime (no routes table in main.dart). RecoveryCodesScreen
// was fully orphaned.
//
// After: tapping "Use recovery code" opens a code-entry dialog → verifies the
// code → routes to VaultPasswordSetupScreen(isReset: true). These tests prove
// the dialog appears (no crash) and that reset mode renders the right UI.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/vault_password_setup_screen.dart';
import 'package:icp_autorun/screens/vault_unlock_screen.dart';

import '../../shared/test_keypair_factory.dart';

void main() {
  testWidgets('tap "Use recovery code" opens the entry dialog (no crash)',
      (tester) async {
    final keypair = await TestKeypairFactory.getEd25519Keypair();
    await tester.pumpWidget(MaterialApp(
      home: VaultUnlockScreen(accountId: 'acct-1', keypair: keypair),
    ));

    // The recovery link is present.
    final link = find.text('Forgot password? Use recovery code');
    expect(link, findsOneWidget);

    // Tapping it must NOT throw (the old pushNamed('/recovery') did).
    await tester.tap(link);
    await tester.pumpAndSettle();

    // The code-entry dialog is shown.
    expect(find.text('Use Recovery Code'), findsOneWidget);
    expect(find.text('Recovery code'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
  });

  testWidgets('cancel closes the recovery dialog', (tester) async {
    final keypair = await TestKeypairFactory.getEd25519Keypair();
    await tester.pumpWidget(MaterialApp(
      home: VaultUnlockScreen(accountId: 'acct-1', keypair: keypair),
    ));

    await tester.tap(find.text('Forgot password? Use recovery code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Use Recovery Code'), findsNothing);
  });

  testWidgets('VaultPasswordSetupScreen isReset renders reset title + button',
      (tester) async {
    final keypair = await TestKeypairFactory.getEd25519Keypair();
    await tester.pumpWidget(MaterialApp(
      home: VaultPasswordSetupScreen(
        accountId: 'acct-1',
        keypair: keypair,
        isReset: true,
      ),
    ));

    expect(find.text('Reset Vault Password'), findsOneWidget);
    // Button label stays "Reset Vault" (greyed out until valid input).
    expect(find.text('Reset Vault'), findsOneWidget);
  });

  testWidgets('VaultPasswordSetupScreen default mode renders create title',
      (tester) async {
    final keypair = await TestKeypairFactory.getEd25519Keypair();
    await tester.pumpWidget(MaterialApp(
      home: VaultPasswordSetupScreen(
        accountId: 'acct-1',
        keypair: keypair,
      ),
    ));

    expect(find.text('Set Vault Password'), findsOneWidget);
    expect(find.text('Create Vault'), findsOneWidget);
  });
}
