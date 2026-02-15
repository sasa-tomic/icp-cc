import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:autorun_flutter/screens/vault_password_setup_screen.dart';
import 'package:autorun_flutter/screens/recovery_codes_screen.dart';
import 'package:autorun_flutter/screens/vault_unlock_screen.dart';
import 'package:autorun_flutter/services/passkey_service.dart';

/// Widget tests for passkey-related screens
void main() {
  group('VaultPasswordSetupScreen', () {
    testWidgets('displays password requirements', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultPasswordSetupScreen(accountId: 'test-account'),
        ),
      );

      expect(find.text('At least 12 characters'), findsOneWidget);
      expect(find.text('One uppercase letter (A-Z)'), findsOneWidget);
      expect(find.text('One lowercase letter (a-z)'), findsOneWidget);
      expect(find.text('One number (0-9)'), findsOneWidget);
      expect(find.text('One special character (!@#\$%^&*)'), findsOneWidget);
    });

    testWidgets('shows error on weak password', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultPasswordSetupScreen(accountId: 'test-account'),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'weak',
      );
      await tester.tap(find.text('Create Vault'));
      await tester.pumpAndSettle();

      expect(find.text('Password must be at least 12 characters'), findsOneWidget);
    });

    testWidgets('shows error when passwords do not match', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultPasswordSetupScreen(accountId: 'test-account'),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'StrongP@ssw0rd!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        'DifferentP@ssw0rd!',
      );
      await tester.tap(find.text('Create Vault'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('disables button until form is valid', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultPasswordSetupScreen(accountId: 'test-account'),
        ),
      );

      final button = find.widgetWithText(ElevatedButton, 'Create Vault');
      expect(tester.widget<ElevatedButton>(button).enabled, isFalse);
    });
  });

  group('RecoveryCodesScreen', () {
    final testCodes = [
      'ABCD-EFGH-IJKL',
      'MNOP-QRST-UVWX',
      'YZ12-3456-7890',
      'ABCD-EFGH-IJKL',
      'MNOP-QRST-UVWX',
      'YZ12-3456-7890',
    ];

    testWidgets('displays all recovery codes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryCodesScreen(
            codes: testCodes,
            accountId: 'test-account',
          ),
        ),
      );

      for (final code in testCodes) {
        expect(find.text(code), findsOneWidget);
      }
    });

    testWidgets('disables continue button until confirmed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryCodesScreen(
            codes: testCodes,
            accountId: 'test-account',
          ),
        ),
      );

      final button = find.widgetWithText(ElevatedButton, 'Continue');
      expect(tester.widget<ElevatedButton>(button).enabled, isFalse);
    });

    testWidgets('enables continue button when confirmed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryCodesScreen(
            codes: testCodes,
            accountId: 'test-account',
          ),
        ),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      final button = find.widgetWithText(ElevatedButton, 'Continue');
      expect(tester.widget<ElevatedButton>(button).enabled, isTrue);
    });

    testWidgets('shows warning message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryCodesScreen(
            codes: testCodes,
            accountId: 'test-account',
          ),
        ),
      );

      expect(find.text('Save These Codes'), findsOneWidget);
      expect(
        find.textContaining('ONLY way to access your vault'),
        findsOneWidget,
      );
    });
  });

  group('VaultUnlockScreen', () {
    setUp(() {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'encrypted_data': 'ZW5jcnlwdGVk',
              'salt': 'c2FsdA==',
              'nonce': 'bm9uY2U=',
            },
          }),
          200,
        );
      });
      PasskeyService().overrideHttpClient(mockClient);
    });

    testWidgets('displays lock icon and password field', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(accountId: 'test-account'),
        ),
      );

      expect(find.byIcon(Icons.lock_outline), findsWidgets);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    });

    testWidgets('disables unlock button with empty password', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(accountId: 'test-account'),
        ),
      );

      final button = find.widgetWithText(ElevatedButton, 'Unlock');
      expect(tester.widget<ElevatedButton>(button).enabled, isFalse);
    });

    testWidgets('enables unlock button with password', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(accountId: 'test-account'),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'some-password',
      );
      await tester.pump();

      final button = find.widgetWithText(ElevatedButton, 'Unlock');
      expect(tester.widget<ElevatedButton>(button).enabled, isTrue);
    });

    testWidgets('shows recovery code link', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(accountId: 'test-account'),
        ),
      );

      expect(
        find.text('Forgot password? Use recovery code'),
        findsOneWidget,
      );
    });
  });
}
