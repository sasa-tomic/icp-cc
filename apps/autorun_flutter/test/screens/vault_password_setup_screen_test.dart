import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/vault_password_setup_screen.dart';
import 'package:icp_autorun/services/vault_crypto_service.dart';

import '../shared/test_keypair_factory.dart';

class _NoOpVaultCrypto extends VaultCryptoService {
  const _NoOpVaultCrypto() : super();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VaultPasswordSetupScreen keyboard completion (UX-9/UX-10)', () {
    testWidgets(
        'Enter on password moves focus to the confirm field; Enter on confirm '
        'with matching valid passwords triggers Create Vault',
        (tester) async {
      final keypair =
          await TestKeypairFactory.getEd25519Keypair();

      await tester.pumpWidget(MaterialApp(
        home: VaultPasswordSetupScreen(
          accountId: 'acct-1',
          keypair: keypair,
          vaultCrypto: const _NoOpVaultCrypto(),
        ),
      ));
      await tester.pumpAndSettle();

      const password = 'Aa1! Aa1! Aa1!';

      await tester.enterText(find.byType(TextFormField).at(0), password);
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      final confirmField =
          tester.widget<TextField>(find.byType(TextField).at(1));
      expect(confirmField.focusNode?.hasFocus, isTrue,
          reason: 'Enter on password should focus the confirm field.');

      await tester.enterText(find.byType(TextFormField).at(1), password);
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'Submit fired — Create Vault entered its in-flight state.');
    });

    testWidgets(
        'Enter on confirm does nothing when passwords do not match',
        (tester) async {
      final keypair =
          await TestKeypairFactory.getEd25519Keypair();

      await tester.pumpWidget(MaterialApp(
        home: VaultPasswordSetupScreen(
          accountId: 'acct-1',
          keypair: keypair,
          vaultCrypto: const _NoOpVaultCrypto(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField).at(0), 'Aa1! Aa1! Aa1!');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      await tester.enterText(
          find.byType(TextFormField).at(1), 'Bb2@ Bb2@ Bb2@');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'Mismatched passwords must not submit.');
    });
  });
}
