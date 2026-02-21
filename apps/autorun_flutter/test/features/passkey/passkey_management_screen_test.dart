import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/passkey_management_screen.dart';
import 'package:icp_autorun/utils/passkey_platform.dart';

/// Widget tests for PasskeyManagementScreen
void main() {
  group('PasskeyManagementScreen', () {
    testWidgets('shows title in app bar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PasskeyManagementScreen(
            accountId: 'test-account',
            username: 'testuser',
          ),
        ),
      );

      expect(find.text('Passkeys'), findsOneWidget);
    });

    testWidgets('shows add passkey button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PasskeyManagementScreen(
            accountId: 'test-account',
            username: 'testuser',
          ),
        ),
      );

      expect(find.text('Add Passkey'), findsOneWidget);
    });

    testWidgets('on Linux desktop shows unsupported platform error',
        (tester) async {
      // This test only runs on Linux desktop
      if (!PasskeyPlatform.isLinuxDesktop) {
        markTestSkipped('This test only runs on Linux desktop');
        return;
      }

      await tester.pumpWidget(
        const MaterialApp(
          home: PasskeyManagementScreen(
            accountId: 'test-account',
            username: 'testuser',
          ),
        ),
      );

      // Wait for async state update
      await tester.pumpAndSettle();

      // Should show the terminal icon
      expect(find.byIcon(Icons.terminal), findsOneWidget);

      // Should show the helpful error message
      expect(
        find.text('Passkeys require a browser on Linux'),
        findsOneWidget,
      );

      // Should show the flutter run command
      expect(find.text('flutter run -d chrome'), findsOneWidget);

      // Should mention supported authenticators
      expect(find.textContaining('KeePassXC'), findsOneWidget);
      expect(find.textContaining('YubiKey'), findsOneWidget);
      expect(find.textContaining('Titan'), findsOneWidget);
    });

    testWidgets('on supported platforms does not show Linux error message',
        (tester) async {
      // This test only runs on non-Linux platforms
      if (PasskeyPlatform.isLinuxDesktop) {
        markTestSkipped('This test is for supported platforms');
        return;
      }

      await tester.pumpWidget(
        const MaterialApp(
          home: PasskeyManagementScreen(
            accountId: 'test-account',
            username: 'testuser',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should NOT show the Linux-specific error
      expect(
        find.text('Passkeys require a browser on Linux'),
        findsNothing,
      );
    });

    testWidgets('Linux error message includes terminal icon', (tester) async {
      if (!PasskeyPlatform.isLinuxDesktop) {
        markTestSkipped('This test only runs on Linux desktop');
        return;
      }

      await tester.pumpWidget(
        const MaterialApp(
          home: PasskeyManagementScreen(
            accountId: 'test-account',
            username: 'testuser',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show terminal icon instead of error icon
      expect(find.byIcon(Icons.terminal), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('Linux error displays command in styled container',
        (tester) async {
      if (!PasskeyPlatform.isLinuxDesktop) {
        markTestSkipped('This test only runs on Linux desktop');
        return;
      }

      await tester.pumpWidget(
        const MaterialApp(
          home: PasskeyManagementScreen(
            accountId: 'test-account',
            username: 'testuser',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should find the command text
      final commandText = find.text('flutter run -d chrome');
      expect(commandText, findsOneWidget);

      // Verify the text widget has monospace font
      final textWidget = tester.widget<Text>(commandText);
      expect(textWidget.style?.fontFamily, equals('monospace'));
    });
  });
}
