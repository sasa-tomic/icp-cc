import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/widgets/key_parameters_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeyParametersDialog', () {
    Future<void> pumpDialog(WidgetTester tester, {String? title}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<KeyParameters>(
                        context: context,
                        builder: (_) => KeyParametersDialog(
                          title: title ?? 'Test Dialog',
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    /// Pumps the dialog and opens it, returning a [KeyParametersResult] whose
    /// [value] is populated when the dialog is later dismissed (Cancel /
    /// Generate). Each behavioural test stays focused on the inputs it drives
    /// + the result it asserts — not the 20-line MaterialApp→Builder→showDialog
    /// pump host that every result-returning case used to rebuild by hand.
    Future<KeyParametersResult> pumpDialogReturning(
      WidgetTester tester, {
      String title = 'Test Dialog',
    }) async {
      final result = KeyParametersResult();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result.value = await showDialog<KeyParameters>(
                        context: context,
                        builder: (_) =>
                            KeyParametersDialog(title: title),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('displays dialog with title', (WidgetTester tester) async {
      await pumpDialog(tester, title: 'Create New Keypair');

      expect(find.text('Create New Keypair'), findsOneWidget);
    });

    testWidgets('shows both algorithm options', (WidgetTester tester) async {
      await pumpDialog(tester);

      expect(find.text('Ed25519'), findsOneWidget);
      expect(find.text('Fast and secure (recommended)'), findsOneWidget);
      expect(find.text('Secp256k1'), findsOneWidget);
      expect(find.text('Bitcoin/Ethereum compatible'), findsOneWidget);
    });

    testWidgets('Ed25519 is selected by default', (WidgetTester tester) async {
      await pumpDialog(tester);

      // Ed25519 should have the checked radio button
      final ed25519Container = find.ancestor(
        of: find.text('Ed25519'),
        matching: find.byType(InkWell),
      );
      expect(ed25519Container, findsOneWidget);
    });

    testWidgets('can switch algorithm selection', (WidgetTester tester) async {
      await pumpDialog(tester);

      // Tap on Secp256k1
      await tester.tap(find.text('Secp256k1'));
      await tester.pumpAndSettle();

      // Both options should still be visible
      expect(find.text('Ed25519'), findsOneWidget);
      expect(find.text('Secp256k1'), findsOneWidget);
    });

    testWidgets('seed input is hidden by default', (WidgetTester tester) async {
      await pumpDialog(tester);

      expect(find.text('Use custom seed phrase'), findsOneWidget);
      expect(find.text('Enter seed phrase (mnemonic)'), findsNothing);
    });

    testWidgets('shows seed input when checkbox is checked',
        (WidgetTester tester) async {
      await pumpDialog(tester);

      // Find and tap the checkbox
      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);

      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      // Seed input should now be visible
      expect(find.text('Enter seed phrase (mnemonic)'), findsOneWidget);
    });

    testWidgets('hides seed input when checkbox is unchecked',
        (WidgetTester tester) async {
      await pumpDialog(tester);

      // Check the checkbox
      final checkbox = find.byType(Checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      expect(find.text('Enter seed phrase (mnemonic)'), findsOneWidget);

      // Uncheck the checkbox
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      // Seed input should be hidden again
      expect(find.text('Enter seed phrase (mnemonic)'), findsNothing);
    });

    testWidgets('returns null when Cancel is pressed',
        (WidgetTester tester) async {
      final result = await pumpDialogReturning(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result.value, isNull);
    });

    testWidgets(
        'returns parameters with ed25519 and no seed when Generate is pressed',
        (WidgetTester tester) async {
      final result = await pumpDialogReturning(tester);

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(result.value, isNotNull);
      expect(result.value!.algorithm, KeyAlgorithm.ed25519);
      expect(result.value!.seed, isNull);
      expect(result.value!.label, isNull);
    });

    testWidgets('returns parameters with secp256k1 when selected',
        (WidgetTester tester) async {
      final result = await pumpDialogReturning(tester);

      // Select secp256k1
      await tester.tap(find.text('Secp256k1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(result.value, isNotNull);
      expect(result.value!.algorithm, KeyAlgorithm.secp256k1);
    });

    testWidgets('returns parameters with custom seed when provided',
        (WidgetTester tester) async {
      final result = await pumpDialogReturning(tester);

      // Enable seed input
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // Enter seed
      await tester.enterText(
        find.widgetWithText(TextField, 'Enter seed phrase (mnemonic)'),
        'test seed phrase',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(result.value, isNotNull);
      expect(result.value!.seed, 'test seed phrase');
    });

    testWidgets('returns parameters with label when provided',
        (WidgetTester tester) async {
      final result = await pumpDialogReturning(tester);

      // Enter label
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g., Laptop Key, Mobile Key'),
        'My Test Key',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(result.value, isNotNull);
      expect(result.value!.label, 'My Test Key');
    });

    testWidgets('trims whitespace from seed and label',
        (WidgetTester tester) async {
      final result = await pumpDialogReturning(tester);

      // Enable seed input
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // Enter seed with whitespace
      await tester.enterText(
        find.widgetWithText(TextField, 'Enter seed phrase (mnemonic)'),
        '  test seed  ',
      );

      // Enter label with whitespace
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g., Laptop Key, Mobile Key'),
        '  My Key  ',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(result.value, isNotNull);
      expect(result.value!.seed, 'test seed');
      expect(result.value!.label, 'My Key');
    });

    testWidgets('returns null for empty seed and label',
        (WidgetTester tester) async {
      final result = await pumpDialogReturning(tester);

      // Enable seed input
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // Enter empty/whitespace values
      await tester.enterText(
        find.widgetWithText(TextField, 'Enter seed phrase (mnemonic)'),
        '   ',
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'e.g., Laptop Key, Mobile Key'),
        '   ',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(result.value, isNotNull);
      expect(result.value!.seed, isNull);
      expect(result.value!.label, isNull);
    });
  });
}

/// Mutable holder so [pumpDialogReturning] can surface the dialog's eventual
/// [KeyParameters] result to a test AFTER the test drives the dismiss tap —
/// the closure captures this holder by reference and writes `.value` when the
/// dialog resolves; the test reads `.value` once its tap + settle completes.
class KeyParametersResult {
  KeyParameters? value;
}
