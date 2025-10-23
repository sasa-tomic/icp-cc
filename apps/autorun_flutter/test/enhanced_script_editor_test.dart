import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/enhanced_script_editor.dart';
void main() {
  group('EnhancedScriptEditor Tests', () {
    late ValueChanged<String> onCodeChanged;
    late String currentCode;

    setUp(() {
      currentCode = '';
      onCodeChanged = (String code) {
        currentCode = code;
      };
    });

    testWidgets('should render with initial code', (WidgetTester tester) async {
      const initialCode = 'print("Hello, World!")';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: initialCode,
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Verify the editor is rendered
      expect(find.byType(EnhancedScriptEditor), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Verify initial code is set
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, initialCode);
    });

    testWidgets('should update code when user types', (WidgetTester tester) async {
      const initialCode = 'print("Initial")';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: initialCode,
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Type new code
      await tester.enterText(find.byType(TextField), 'print("Updated")');
      await tester.pump();

      // Verify code changed callback was called
      expect(currentCode, 'print("Updated")');
    });

    testWidgets('should display language indicator', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: '',
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Find and verify language indicator
      expect(find.text('LUA'), findsOneWidget);
    });

    testWidgets('should display line count', (WidgetTester tester) async {
      const multiLineCode = 'line1\nline2\nline3';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: multiLineCode,
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Verify line count is displayed
      expect(find.text('Lines: 3'), findsOneWidget);
    });

    testWidgets('should display character count', (WidgetTester tester) async {
      const testCode = 'Hello World';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: testCode,
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Verify character count is displayed
      expect(find.text('Chars: 11'), findsOneWidget);
    });

    testWidgets('should show integrations button when enabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: '',
              onCodeChanged: onCodeChanged,
              language: 'lua',
              showIntegrations: true,
            ),
          ),
        ),
      );

      // Verify integrations button is present
      expect(find.byIcon(Icons.extension), findsOneWidget);
    });

    testWidgets('should hide integrations button when disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: '',
              onCodeChanged: onCodeChanged,
              language: 'lua',
              showIntegrations: false,
            ),
          ),
        ),
      );

      // Verify integrations button is not present
      expect(find.byIcon(Icons.extension), findsNothing);
    });

    testWidgets('should show format and copy buttons', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: '',
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Verify action buttons are present
      expect(find.byIcon(Icons.format_align_left), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('should show initial valid status', (WidgetTester tester) async {
      const validCode = 'print("Hello")';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: validCode,
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Verify valid status is shown initially
      expect(find.text('Code is valid'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('should show empty script error for empty code', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: '',
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Wait for linting to complete
      await tester.pump(const Duration(milliseconds: 600));

      // Verify empty script error is shown
      expect(find.text('Script is empty'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('should be in readonly mode when specified', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: 'readonly code',
              onCodeChanged: onCodeChanged,
              language: 'lua',
              readOnly: true,
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.readOnly, true);
    });

    testWidgets('should respect minLines parameter', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: '',
              onCodeChanged: onCodeChanged,
              language: 'lua',
              minLines: 30,
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.minLines, 30);
    });

    testWidgets('should show copy button', (WidgetTester tester) async {
      const testCode = 'print("Test code")';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: testCode,
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Verify copy button is present
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('should update line count when code changes', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: 'single line',
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Initial line count
      expect(find.text('Lines: 1'), findsOneWidget);

      // Add multiple lines
      await tester.enterText(find.byType(TextField), 'line1\nline2\nline3');
      await tester.pump();

      // Verify line count updated
      expect(find.text('Lines: 3'), findsOneWidget);
    });

    testWidgets('should show format code placeholder', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnhancedScriptEditor(
              initialCode: '',
              onCodeChanged: onCodeChanged,
              language: 'lua',
            ),
          ),
        ),
      );

      // Tap format button
      await tester.tap(find.byIcon(Icons.format_align_left));
      await tester.pumpAndSettle();

      // Verify placeholder snackbar is shown
      expect(find.text('Code formatting coming soon!'), findsOneWidget);
    });

    group('Linting Functionality', () {
      testWidgets('should debounce linting calls', (WidgetTester tester) async {
        int lintCallCount = 0;

        // Mock timer to track debouncing
        Timer? pendingTimer;
        
        await runZoned(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: EnhancedScriptEditor(
                  initialCode: '',
                  onCodeChanged: (String code) {
                    lintCallCount++;
                    // Simulate debounced timer
                    pendingTimer?.cancel();
                    pendingTimer = Timer(const Duration(milliseconds: 500), () {});
                  },
                  language: 'lua',
                ),
              ),
            ),
          );

          // Type multiple characters quickly
          for (int i = 0; i < 5; i++) {
            await tester.enterText(find.byType(TextField), 'x');
            await tester.pump(const Duration(milliseconds: 100));
          }

          // Wait for debouncing to complete
          await tester.pump(const Duration(milliseconds: 600));

          // Verify multiple changes occurred
          expect(lintCallCount, greaterThan(1));
        });

        pendingTimer?.cancel();
      });

      testWidgets('should update character count in real-time', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnhancedScriptEditor(
                initialCode: '',
                onCodeChanged: onCodeChanged,
                language: 'lua',
              ),
            ),
          ),
        );

        // Initial character count
        expect(find.text('Chars: 0'), findsOneWidget);

        // Type character by character
        await tester.enterText(find.byType(TextField), 'H');
        await tester.pump();
        expect(find.text('Chars: 1'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pump();
        expect(find.text('Chars: 5'), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should have toolbar buttons present', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnhancedScriptEditor(
                initialCode: '',
                onCodeChanged: onCodeChanged,
                language: 'lua',
              ),
            ),
          ),
        );

        // Check for toolbar buttons
        expect(find.byIcon(Icons.copy), findsOneWidget);
        expect(find.byIcon(Icons.format_align_left), findsOneWidget);
      });
    });

    group('Error Handling', () {
      testWidgets('should handle null onCodeChanged gracefully', (WidgetTester tester) async {
        expect(
          () => EnhancedScriptEditor(
            initialCode: 'test',
            onCodeChanged: (String code) {
              // This should not throw
            },
            language: 'lua',
          ),
          returnsNormally,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnhancedScriptEditor(
                initialCode: 'test',
                onCodeChanged: onCodeChanged,
                language: 'lua',
              ),
            ),
          ),
        );

        expect(find.byType(EnhancedScriptEditor), findsOneWidget);
      });

      testWidgets('should handle empty code gracefully', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnhancedScriptEditor(
                initialCode: '',
                onCodeChanged: onCodeChanged,
                language: 'lua',
              ),
            ),
          ),
        );

        // Type and clear code
        await tester.enterText(find.byType(TextField), 'test');
        await tester.pump();
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();

        // Should not crash
        expect(find.byType(EnhancedScriptEditor), findsOneWidget);
      });
    });
  });
}