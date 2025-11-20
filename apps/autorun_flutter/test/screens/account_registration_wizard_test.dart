import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/screens/account_registration_wizard.dart';

import '../test_helpers/test_identity_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccountRegistrationWizard', () {
    group('Register button behavior', () {
      testWidgets('Register button is disabled when fields are empty', (WidgetTester tester) async {
        // Arrange
        final identity = await TestIdentityFactory.getEd25519Identity();
        final controller = AccountController();

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              identity: identity,
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

      testWidgets('Register button remains disabled until username validation passes', (WidgetTester tester) async {
        // Arrange
        final identity = await TestIdentityFactory.getEd25519Identity();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              identity: identity,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act - Enter username
        final usernameField = find.widgetWithText(TextFormField, 'Username').first;
        await tester.enterText(usernameField, 'testuser');
        await tester.pump();

        // Act - Enter display name
        final displayNameField = find.widgetWithText(TextFormField, 'Display Name *').first;
        await tester.enterText(displayNameField, 'Test User');
        await tester.pump();

        // Assert - Button remains disabled until validation completes
        final registerButton = find.widgetWithText(FilledButton, 'Register');
        expect(registerButton, findsOneWidget);

        final FilledButton button = tester.widget(registerButton);
        expect(button.onPressed, isNull); // Button is disabled until validation passes
      });

      testWidgets('Register button is disabled when only username is filled', (WidgetTester tester) async {
        // Arrange
        final identity = await TestIdentityFactory.getEd25519Identity();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              identity: identity,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act - Enter only username
        final usernameField = find.widgetWithText(TextFormField, 'Username').first;
        await tester.enterText(usernameField, 'testuser');
        await tester.pump();

        // Assert
        final registerButton = find.widgetWithText(FilledButton, 'Register');
        expect(registerButton, findsOneWidget);

        final FilledButton button = tester.widget(registerButton);
        expect(button.onPressed, isNull); // Button is disabled
      });

      testWidgets('Register button is disabled when only display name is filled', (WidgetTester tester) async {
        // Arrange
        final identity = await TestIdentityFactory.getEd25519Identity();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              identity: identity,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act - Enter only display name
        final displayNameField = find.widgetWithText(TextFormField, 'Display Name *').first;
        await tester.enterText(displayNameField, 'Test User');
        await tester.pump();

        // Assert
        final registerButton = find.widgetWithText(FilledButton, 'Register');
        expect(registerButton, findsOneWidget);

        final FilledButton button = tester.widget(registerButton);
        expect(button.onPressed, isNull); // Button is disabled
      });

      testWidgets('Register button is disabled when username is whitespace only', (WidgetTester tester) async {
        // Arrange
        final identity = await TestIdentityFactory.getEd25519Identity();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              identity: identity,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act - Enter whitespace username
        final usernameField = find.widgetWithText(TextFormField, 'Username').first;
        await tester.enterText(usernameField, '   ');
        await tester.pump();

        final displayNameField = find.widgetWithText(TextFormField, 'Display Name *').first;
        await tester.enterText(displayNameField, 'Test User');
        await tester.pump();

        // Assert
        final registerButton = find.widgetWithText(FilledButton, 'Register');
        expect(registerButton, findsOneWidget);

        final FilledButton button = tester.widget(registerButton);
        expect(button.onPressed, isNull); // Button is disabled
      });

      testWidgets('Register button is disabled when display name is whitespace only', (WidgetTester tester) async {
        // Arrange
        final identity = await TestIdentityFactory.getEd25519Identity();
        final controller = AccountController();

        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              identity: identity,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Act - Enter whitespace display name
        final usernameField = find.widgetWithText(TextFormField, 'Username').first;
        await tester.enterText(usernameField, 'testuser');
        await tester.pump();

        final displayNameField = find.widgetWithText(TextFormField, 'Display Name *').first;
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
      testWidgets('displays all required form fields', (WidgetTester tester) async {
        // Arrange
        final identity = await TestIdentityFactory.getEd25519Identity();
        final controller = AccountController();

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              identity: identity,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Username'), findsOneWidget);
        expect(find.text('Display Name *'), findsOneWidget);
        expect(find.text('Email (optional)'), findsOneWidget);
        expect(find.text('Telegram (optional)'), findsOneWidget);
        expect(find.text('Twitter/X (optional)'), findsOneWidget);
        expect(find.text('Discord (optional)'), findsOneWidget);
        expect(find.text('Website (optional)'), findsOneWidget);
        expect(find.text('Bio (optional)'), findsOneWidget);
      });

      testWidgets('displays username permanence warning', (WidgetTester tester) async {
        // Arrange
        final identity = await TestIdentityFactory.getEd25519Identity();
        final controller = AccountController();

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              identity: identity,
              accountController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Username cannot be changed later'), findsOneWidget);
      });

      testWidgets('displays username format rules', (WidgetTester tester) async {
        // Arrange
        final identity = await TestIdentityFactory.getEd25519Identity();
        final controller = AccountController();

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: AccountRegistrationWizard(
              identity: identity,
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
  });
}
