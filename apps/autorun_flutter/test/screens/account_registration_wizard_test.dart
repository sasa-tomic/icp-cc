import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/account_registration_wizard.dart';
import 'package:icp_autorun/screens/passkey_management_screen.dart';
import 'package:icp_autorun/screens/vault_password_setup_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../shared/test_keypair_factory.dart';

class _MockAccountController extends Mock implements AccountController {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccountRegistrationWizard', () {
    group('Register button behavior', () {
      testWidgets('Register button is disabled when fields are empty',
          (WidgetTester tester) async {
        // Arrange
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final controller = AccountController();

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Assert
        final registerButton = find.widgetWithText(FilledButton, 'Register');
        expect(registerButton, findsOneWidget);

        final FilledButton button = tester.widget(registerButton);
        expect(button.onPressed, isNull); // Button is disabled
      });

      testWidgets(
          'Register button remains disabled until username validation passes',
          (WidgetTester tester) async {
        // Arrange
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act - Enter username
        final usernameField =
            find.widgetWithText(TextFormField, 'Username').first;
        await tester.enterText(usernameField, 'testuser');
        await tester.pump();

        // Act - Enter display name
        final displayNameField =
            find.widgetWithText(TextFormField, 'Display Name *').first;
        await tester.enterText(displayNameField, 'Test User');
        await tester.pump();

        // Assert - Button remains disabled until validation completes
        final registerButton = find.widgetWithText(FilledButton, 'Register');
        expect(registerButton, findsOneWidget);

        final FilledButton button = tester.widget(registerButton);
        expect(button.onPressed,
            isNull); // Button is disabled until validation passes
      });

      testWidgets('Register button is disabled when only username is filled',
          (WidgetTester tester) async {
        // Arrange
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act - Enter only username
        final usernameField =
            find.widgetWithText(TextFormField, 'Username').first;
        await tester.enterText(usernameField, 'testuser');
        await tester.pump();

        // Assert
        final registerButton = find.widgetWithText(FilledButton, 'Register');
        expect(registerButton, findsOneWidget);

        final FilledButton button = tester.widget(registerButton);
        expect(button.onPressed, isNull); // Button is disabled
      });

      testWidgets(
          'Register button is disabled when only display name is filled',
          (WidgetTester tester) async {
        // Arrange
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act - Enter only display name
        final displayNameField =
            find.widgetWithText(TextFormField, 'Display Name *').first;
        await tester.enterText(displayNameField, 'Test User');
        await tester.pump();

        // Assert
        final registerButton = find.widgetWithText(FilledButton, 'Register');
        expect(registerButton, findsOneWidget);

        final FilledButton button = tester.widget(registerButton);
        expect(button.onPressed, isNull); // Button is disabled
      });

      testWidgets(
          'Register button is disabled when username is whitespace only',
          (WidgetTester tester) async {
        // Arrange
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act - Enter whitespace username
        final usernameField =
            find.widgetWithText(TextFormField, 'Username').first;
        await tester.enterText(usernameField, '   ');
        await tester.pump();

        final displayNameField =
            find.widgetWithText(TextFormField, 'Display Name *').first;
        await tester.enterText(displayNameField, 'Test User');
        await tester.pump();

        // Assert
        final registerButton = find.widgetWithText(FilledButton, 'Register');
        expect(registerButton, findsOneWidget);

        final FilledButton button = tester.widget(registerButton);
        expect(button.onPressed, isNull); // Button is disabled
      });

      testWidgets(
          'Register button is disabled when display name is whitespace only',
          (WidgetTester tester) async {
        // Arrange
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act - Enter whitespace display name
        final usernameField =
            find.widgetWithText(TextFormField, 'Username').first;
        await tester.enterText(usernameField, 'testuser');
        await tester.pump();

        final displayNameField =
            find.widgetWithText(TextFormField, 'Display Name *').first;
        await tester.enterText(displayNameField, '   ');
        await tester.pump();

        // Assert
        final registerButton = find.widgetWithText(FilledButton, 'Register');
        expect(registerButton, findsOneWidget);

        final FilledButton button = tester.widget(registerButton);
        expect(button.onPressed, isNull); // Button is disabled
      });
    });

    group('UI elements', () {
      testWidgets('displays all required form fields',
          (WidgetTester tester) async {
        // Arrange
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final controller = AccountController();

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Assert — primary fields are always visible.
        expect(find.text('Username'), findsOneWidget);
        expect(find.text('Display Name *'), findsOneWidget);

        // Optional contact fields are hidden behind a collapsed expander.
        final expanderTitle = find.text('Add contact details (optional)');
        expect(expanderTitle, findsOneWidget);
        expect(find.text('Email (optional)'), findsNothing,
            reason: 'contact fields start collapsed');

        // Expand the expander; the contact fields become visible.
        await tester.tap(expanderTitle);
        await tester.pumpAndSettle();

        expect(find.text('Email (optional)'), findsOneWidget);
        expect(find.text('Telegram (optional)'), findsOneWidget);
        expect(find.text('Twitter/X (optional)'), findsOneWidget);
        expect(find.text('Discord (optional)'), findsOneWidget);
        expect(find.text('Website (optional)'), findsOneWidget);
        expect(find.text('Bio (optional)'), findsOneWidget);
      });

      testWidgets('displays username permanence warning',
          (WidgetTester tester) async {
        // Arrange
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final controller = AccountController();

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Username cannot be changed later'), findsOneWidget);
      });

      testWidgets('displays username format rules',
          (WidgetTester tester) async {
        // Arrange
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final controller = AccountController();

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Username requirements:'), findsOneWidget);
        expect(find.text('3-32 characters'), findsOneWidget);
        expect(find.text('Lowercase letters and numbers'), findsOneWidget);
        expect(find.text('Can use _ or -'), findsOneWidget);
        expect(find.text('Cannot start or end with _ or -'), findsOneWidget);
      });
    });

    // Regression coverage for F-12: the wizard must resolve the caller's
    // `Navigator.push<Account>` with an Account (never a record) on every
    // platform, and the passkey-supported branch must not crash.
    group('Registration completion (return value)', () {
      late _MockAccountController mockController;
      late ProfileKeypair keypair;
      late Account testAccount;

      setUp(() async {
        keypair = await TestKeypairFactory.getEd25519Keypair();
        mockController = _MockAccountController();
        testAccount = Account(
          id: 'acc-1',
          username: 'alice',
          displayName: 'Alice',
          publicKeys: const <AccountPublicKey>[],
          createdAt: DateTime.utc(2024, 1, 1),
          updatedAt: DateTime.utc(2024, 1, 1),
        );

        registerFallbackValue('');
        registerFallbackValue(keypair);

        when(() => mockController.validateUsername(any()))
            .thenReturn(UsernameValidation.valid);
        // Synchronously-completed futures so the awaited controller calls
        // resolve on the immediate microtask queue that pumpAndSettle drains —
        // no `runAsync` clock-juggling required.
        when(() => mockController.isUsernameAvailable(any()))
            .thenAnswer((_) => Future<bool>.value(true));
        when(() => mockController.registerAccount(
              keypair: any(named: 'keypair'),
              username: any(named: 'username'),
              displayName: any(named: 'displayName'),
              contactEmail: any(named: 'contactEmail'),
              contactTelegram: any(named: 'contactTelegram'),
              contactTwitter: any(named: 'contactTwitter'),
              contactDiscord: any(named: 'contactDiscord'),
              websiteUrl: any(named: 'websiteUrl'),
              bio: any(named: 'bio'),
            )).thenAnswer((_) => Future<Account>.value(testAccount));
      });

      /// Pumps the wizard on top of a host route and returns a [Completer]
      /// that resolves with whatever the caller's `push<Account>` receives.
      Future<Completer<Object?>> pumpWizard(
        WidgetTester tester, {
        required bool Function() isPasskeySupported,
      }) async {
        final completer = Completer<Object?>();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await Navigator.of(context)
                          .push<Account>(MaterialPageRoute<Account>(
                        builder: (_) => AccountRegistrationWizard(
                          keypair: keypair,
                          accountController: mockController,
                          isPasskeySupported: isPasskeySupported,
                        ),
                      ));
                      if (!completer.isCompleted) completer.complete(result);
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        return completer;
      }

      Future<void> fillAndSubmitRegistration(WidgetTester tester) async {
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Username').first,
          'alice',
        );
        // Wait out the 500ms username-validation debounce.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Display Name *').first,
          'Alice',
        );
        await tester.pumpAndSettle();

        final registerFinder =
            find.widgetWithText(FilledButton, 'Register');
        final registerButton = tester.widget<FilledButton>(registerFinder);
        expect(registerButton.onPressed, isNotNull,
            reason: 'Register must be enabled once the form is valid');
        // The Register button can sit below the fold in the scrollable form.
        await tester.ensureVisible(registerFinder);
        await tester.tap(registerFinder, warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      testWidgets(
          'UX-H6: prompts via the shared security helper on platforms without '
          'passkey support; tapping Skip returns an Account to the caller',
          (WidgetTester tester) async {
        final completer = await pumpWizard(
          tester,
          isPasskeySupported: () => false,
        );

        await fillAndSubmitRegistration(tester);

        // UX-H6: the shared security prompt is now ALWAYS shown after
        // successful registration (vault is always available). On a platform
        // without passkey support, the passkey tile is disabled — but the
        // dialog still appears.
        expect(find.text('Secure your account'), findsOneWidget);
        expect(find.text('Set up vault password'), findsOneWidget);
        expect(find.text('Enroll a passkey'), findsOneWidget);

        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();

        final result = await completer.future;
        expect(result, isA<Account>(),
            reason: 'wizard must return an Account, never a record');
        expect((result as Account).username, 'alice');
      });

      testWidgets(
          'UX-H6: "Enroll a passkey" returns an Account and opens passkey '
          'management without crashing', (WidgetTester tester) async {
        final completer = await pumpWizard(
          tester,
          isPasskeySupported: () => true,
        );

        await fillAndSubmitRegistration(tester);

        // The shared prompt must be visible.
        expect(find.text('Secure your account'), findsOneWidget);

        await tester.tap(find.text('Enroll a passkey'));
        await tester.pumpAndSettle();

        final result = await completer.future;
        expect(result, isA<Account>(),
            reason: 'pushReplacement result must be the Account, not a record');
        expect((result as Account).username, 'alice');

        // Wizard was replaced by passkey management for the new account.
        expect(find.byType(PasskeyManagementScreen), findsOneWidget);
        expect(find.byType(AccountRegistrationWizard), findsNothing);
      });

      testWidgets(
          'UX-H6: "Set up vault password" returns an Account and opens the '
          'vault setup screen', (WidgetTester tester) async {
        final completer = await pumpWizard(
          tester,
          isPasskeySupported: () => true,
        );

        await fillAndSubmitRegistration(tester);

        expect(find.text('Secure your account'), findsOneWidget);

        await tester.tap(find.text('Set up vault password'));
        await tester.pumpAndSettle();

        final result = await completer.future;
        expect(result, isA<Account>(),
            reason: 'pushReplacement result must be the Account');
        expect((result as Account).username, 'alice');

        // Wizard was replaced by vault setup for the new account.
        expect(find.byType(VaultPasswordSetupScreen), findsOneWidget);
        expect(find.byType(AccountRegistrationWizard), findsNothing);
      });

      testWidgets('UX-H6: "Skip for now" returns an Account',
          (WidgetTester tester) async {
        final completer = await pumpWizard(
          tester,
          isPasskeySupported: () => true,
        );

        await fillAndSubmitRegistration(tester);

        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();

        final result = await completer.future;
        expect(result, isA<Account>());
        expect((result as Account).username, 'alice');
      });
    });

    group('Keyboard completion (UX-9/UX-10)', () {
      testWidgets(
          'Enter on username moves focus to the display name field; Enter on '
          'display name submits the form when valid', (tester) async {
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final mockController = _MockAccountController();
        final testAccount = Account(
          id: 'acc-kbd',
          username: 'kbduser',
          displayName: 'Keyboard User',
          publicKeys: const <AccountPublicKey>[],
          createdAt: DateTime.utc(2024, 1, 1),
          updatedAt: DateTime.utc(2024, 1, 1),
        );

        registerFallbackValue('');
        registerFallbackValue(keypair);
        when(() => mockController.validateUsername(any()))
            .thenReturn(UsernameValidation.valid);
        when(() => mockController.isUsernameAvailable(any()))
            .thenAnswer((_) => Future<bool>.value(true));
        when(() => mockController.registerAccount(
              keypair: any(named: 'keypair'),
              username: any(named: 'username'),
              displayName: any(named: 'displayName'),
              contactEmail: any(named: 'contactEmail'),
              contactTelegram: any(named: 'contactTelegram'),
              contactTwitter: any(named: 'contactTwitter'),
              contactDiscord: any(named: 'contactDiscord'),
              websiteUrl: any(named: 'websiteUrl'),
              bio: any(named: 'bio'),
            )).thenAnswer((_) => Future<Account>.value(testAccount));

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: mockController,
              isPasskeySupported: () => false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Username').first,
          'kbduser',
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        // Enter on username → focus should move to display name.
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();

        final displayNameField = tester.widget<TextField>(
            find.widgetWithText(TextField, 'Display Name *').first);
        expect(displayNameField.focusNode?.hasFocus, isTrue,
            reason: 'Enter on username should focus the display name field.');

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Display Name *').first,
          'Keyboard User',
        );
        await tester.pumpAndSettle();

        // Enter on display name (the last field) submits the wizard.
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pumpAndSettle();

        verify(() => mockController.registerAccount(
              keypair: any(named: 'keypair'),
              username: any(named: 'username'),
              displayName: any(named: 'displayName'),
              contactEmail: any(named: 'contactEmail'),
              contactTelegram: any(named: 'contactTelegram'),
              contactTwitter: any(named: 'contactTwitter'),
              contactDiscord: any(named: 'contactDiscord'),
              websiteUrl: any(named: 'websiteUrl'),
              bio: any(named: 'bio'),
            )).called(1);
      });

      testWidgets(
          'Enter on display name does nothing when username is invalid',
          (tester) async {
        final keypair = await TestKeypairFactory.getEd25519Keypair();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              keypair: keypair,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Type a too-short username; validation fails.
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Username').first,
          'ab',
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Display Name *').first,
          'Some User',
        );
        await tester.pumpAndSettle();

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pumpAndSettle();

        // No navigation pop / no security prompt — the wizard stays put.
        expect(find.text('Secure your account'), findsNothing);
        expect(find.text('Register'), findsOneWidget);
      });
    });
  });
}
