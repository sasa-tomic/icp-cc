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

      // Should show the helpful, accurate unsupported-platform message
      expect(
        find.text("Passkeys aren't available on Linux desktop"),
        findsOneWidget,
      );

      // Must NOT advertise the unbuildable web command (R-1).
      expect(find.text('flutter run -d chrome'), findsNothing);

      // Should mention the supported platforms and authenticators.
      expect(find.textContaining('macOS'), findsOneWidget);
      expect(find.textContaining('Windows'), findsOneWidget);
      expect(find.textContaining('Android'), findsOneWidget);
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

      // Should NOT show the Linux-specific unsupported-platform error
      expect(
        find.text("Passkeys aren't available on Linux desktop"),
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

    testWidgets('Linux error does not advertise the unbuildable web command',
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

      // The unbuildable `flutter run -d chrome` command (blocked by R-1's
      // unconditional dart:ffi import) must never be shown to the user.
      expect(find.text('flutter run -d chrome'), findsNothing);
      // No monospace command block is rendered anymore.
      expect(find.byIcon(Icons.copy), findsNothing);
    });
  });
}
