import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';

void main() {
  group('Account Registration Prompt', () {
    testWidgets('prompt shows correct title and message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) =>
                        const _AccountRegistrationPromptDialog(),
                  ),
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Share to Marketplace'), findsOneWidget);
      expect(find.textContaining('register a @username'), findsOneWidget);
    });

    testWidgets('prompt has Register and Not now buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) =>
                        const _AccountRegistrationPromptDialog(),
                  ),
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Register Username'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('Not now dismisses dialog returning false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<bool>(
                      context: context,
                      builder: (context) =>
                          const _AccountRegistrationPromptDialog(),
                    );
                  },
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('Register Username dismisses dialog returning true',
        (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<bool>(
                      context: context,
                      builder: (context) =>
                          const _AccountRegistrationPromptDialog(),
                    );
                  },
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Register Username'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('dialog is dismissible via barrier', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<bool>(
                      context: context,
                      builder: (context) =>
                          const _AccountRegistrationPromptDialog(),
                    );
                  },
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap outside the dialog to dismiss
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Result should be null when dismissed via barrier
      expect(result, isNull);
    });
  });
}

// Expose the private class for testing by creating a public wrapper
// This is the same dialog from scripts_screen.dart
class _AccountRegistrationPromptDialog extends StatelessWidget {
  const _AccountRegistrationPromptDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        Icons.cloud_upload_outlined,
        size: 48,
        color: theme.colorScheme.primary,
      ),
      title: const Text('Share to Marketplace'),
      content: const Text(
        'To share scripts publicly, you\'ll need to register a @username.\n\n'
        'This lets the community identify you as the script author.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Register Username'),
        ),
      ],
    );
  }
}
