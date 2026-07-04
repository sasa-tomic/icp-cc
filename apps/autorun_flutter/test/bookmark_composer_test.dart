import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/widgets/bookmark_composer.dart';

void main() {
  Future<void> pumpComposer(
    WidgetTester tester, {
    required BookmarkSaveCallback onSave,
    void Function(String canisterId, String method, String? label)? onSaved,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: BookmarkComposer(onSave: onSave, onSaved: onSaved),
          ),
        ),
      ),
    );
  }

  Future<void> pumpUntilFound(WidgetTester tester, Finder finder,
      {int maxTicks = 20}) async {
    for (var i = 0; i < maxTicks; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) return;
    }
  }

  /// UX-4: the composer is collapsed by default. This helper expands it the way
  /// a user would — by tapping the "+ Add Bookmark" button — and waits for the
  /// inline form to mount.
  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('bookmarkComposerToggleButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('BookmarkComposer (UX-4 collapsed-by-default)', () {
    testWidgets('is collapsed by default and hides the form fields', (tester) async {
      await pumpComposer(
        tester,
        onSave: ({required String canisterId, required String method, String? label}) async {},
      );

      // The compact toggle is visible…
      expect(find.byKey(const Key('bookmarkComposerToggleButton')), findsOneWidget);
      expect(find.text('Add Bookmark'), findsOneWidget);
      // …and the form is NOT mounted.
      expect(find.byKey(const Key('bookmarkComposerCanisterField')), findsNothing);
      expect(find.byKey(const Key('bookmarkComposerSubmitButton')), findsNothing);
    });

    testWidgets('expanding mounts the inline form and focuses the canister field', (tester) async {
      await pumpComposer(
        tester,
        onSave: ({required String canisterId, required String method, String? label}) async {},
      );
      await expand(tester);

      expect(find.byKey(const Key('bookmarkComposerCanisterField')), findsOneWidget);
      expect(find.byKey(const Key('bookmarkComposerMethodField')), findsOneWidget);
      expect(find.byKey(const Key('bookmarkComposerLabelField')), findsOneWidget);
      expect(find.byKey(const Key('bookmarkComposerSubmitButton')), findsOneWidget);
      // Keyboard-first: the first field is auto-focused.
      final canisterField = tester.widget<TextField>(
        find.byKey(const Key('bookmarkComposerCanisterField')),
      );
      expect(canisterField.focusNode!.hasFocus, isTrue);
    });

    testWidgets('saves valid input, clears the form and collapses back', (tester) async {
      Map<String, String?>? captured;
      await pumpComposer(
        tester,
        onSave: ({required String canisterId, required String method, String? label}) async {
          captured = {
            'cid': canisterId,
            'method': method,
            'label': label,
          };
        },
      );
      await expand(tester);

      await tester.enterText(find.byKey(const Key('bookmarkComposerCanisterField')), 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      await tester.enterText(find.byKey(const Key('bookmarkComposerMethodField')), 'account_balance_dfx');
      await tester.pump();
      await tester.enterText(find.byKey(const Key('bookmarkComposerLabelField')), 'Ledger');

      final submitButton = find.byKey(const Key('bookmarkComposerSubmitButton'));
      expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);

      await tester.tap(submitButton);
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!['cid'], 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      expect(captured!['method'], 'account_balance_dfx');
      expect(captured!['label'], 'Ledger');
      // UX-4: a successful save collapses the form back to the toggle so the
      // bookmarks list is uncluttered again.
      expect(find.byKey(const Key('bookmarkComposerToggleButton')), findsOneWidget);
      expect(find.byKey(const Key('bookmarkComposerCanisterField')), findsNothing);
    });

    testWidgets('surfaces failures returned by the save callback', (tester) async {
      await pumpComposer(
        tester,
        onSave: ({required String canisterId, required String method, String? label}) async {
          throw Exception('disk error');
        },
      );
      await expand(tester);

      await tester.enterText(find.byKey(const Key('bookmarkComposerCanisterField')), 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      await tester.enterText(find.byKey(const Key('bookmarkComposerMethodField')), 'account_balance_dfx');
      await tester.pump();

      final submitButton = find.byKey(const Key('bookmarkComposerSubmitButton'));
      await tester.ensureVisible(submitButton);
      expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);
      await tester.tap(submitButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final errorTextFinder = find.textContaining('Failed to save bookmark');
      await pumpUntilFound(tester, errorTextFinder);
      expect(errorTextFinder, findsAtLeastNWidgets(1));
      // The form stays open on failure so the user can retry.
      expect(find.byKey(const Key('bookmarkComposerCanisterField')), findsOneWidget);
    });

    // ---------- UX-4 new behavior: keyboard-first + inline validation ----------

    testWidgets('Enter on the method field saves the bookmark (no Add-button tap needed)', (tester) async {
      Map<String, String?>? captured;
      await pumpComposer(
        tester,
        onSave: ({required String canisterId, required String method, String? label}) async {
          captured = {'cid': canisterId, 'method': method, 'label': label};
        },
      );
      await expand(tester);

      await tester.enterText(find.byKey(const Key('bookmarkComposerCanisterField')), 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      await tester.enterText(find.byKey(const Key('bookmarkComposerMethodField')), 'account_balance_dfx');
      await tester.pump();

      // Press Enter on the method field — the common 2-field path saves
      // without touching the optional label or the Add button.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!['cid'], 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      expect(captured!['method'], 'account_balance_dfx');
      expect(captured!['label'], isNull);
      expect(find.byKey(const Key('bookmarkComposerToggleButton')), findsOneWidget);
    });

    testWidgets('rejects a malformed canister id with a clear inline error and saves nothing', (tester) async {
      bool saved = false;
      await pumpComposer(
        tester,
        onSave: ({required String canisterId, required String method, String? label}) async {
          saved = true;
        },
      );
      await expand(tester);

      await tester.enterText(find.byKey(const Key('bookmarkComposerCanisterField')), '!!!bad id!!!');
      await tester.enterText(find.byKey(const Key('bookmarkComposerMethodField')), 'icrc1_balance_of');
      await tester.pump();

      // The Add button is disabled while input is invalid.
      final submitButton = find.byKey(const Key('bookmarkComposerSubmitButton'));
      expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);

      // Even hitting Enter does not save — the validator blocks it and shows a
      // clear, specific error. No silent failure.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(saved, isFalse);
      expect(find.byKey(const Key('bookmarkComposerError')), findsOneWidget);
      expect(find.text('Enter a valid canister ID.'), findsOneWidget);
      // The form stays open so the user can correct the input.
      expect(find.byKey(const Key('bookmarkComposerCanisterField')), findsOneWidget);
    });

    testWidgets('collapse button hides the form without saving', (tester) async {
      bool saved = false;
      await pumpComposer(
        tester,
        onSave: ({required String canisterId, required String method, String? label}) async {
          saved = true;
        },
      );
      await expand(tester);

      await tester.enterText(find.byKey(const Key('bookmarkComposerCanisterField')), 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      await tester.enterText(find.byKey(const Key('bookmarkComposerMethodField')), 'account_balance_dfx');
      await tester.pump();

      await tester.tap(find.byKey(const Key('bookmarkComposerCollapseButton')));
      await tester.pump();

      expect(saved, isFalse);
      expect(find.byKey(const Key('bookmarkComposerToggleButton')), findsOneWidget);
      expect(find.byKey(const Key('bookmarkComposerCanisterField')), findsNothing);
    });
  });
}
