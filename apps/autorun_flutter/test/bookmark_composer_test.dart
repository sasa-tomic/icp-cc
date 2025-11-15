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

  Future<void> pumpUntilFound(WidgetTester tester, Finder finder, {int maxTicks = 20}) async {
    for (var i = 0; i < maxTicks; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) return;
    }
  }

  group('BookmarkComposer', () {
    testWidgets('saves valid input and clears the form', (tester) async {
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
      expect(find.text('ryjl3-tyaaa-aaaaa-aaaba-cai'), findsNothing);
      expect(find.text('account_balance_dfx'), findsNothing);
    });

    testWidgets('surfaces failures returned by the save callback', (tester) async {
      await pumpComposer(
        tester,
        onSave: ({required String canisterId, required String method, String? label}) async {
          throw Exception('disk error');
        },
      );

      await tester.enterText(find.byKey(const Key('bookmarkComposerCanisterField')), 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      await tester.enterText(find.byKey(const Key('bookmarkComposerMethodField')), 'account_balance_dfx');
      await tester.pump(); // allow the form to rebuild after controller listeners fire

      final submitButton = find.byKey(const Key('bookmarkComposerSubmitButton'));
      await tester.ensureVisible(submitButton);
      expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);
      await tester.tap(submitButton);
      await tester.pump(); // process tap + immediate rebuild
      await tester.pump(const Duration(milliseconds: 50));
      final errorTextFinder = find.textContaining('Failed to save bookmark');
      await pumpUntilFound(tester, errorTextFinder);
      expect(errorTextFinder, findsAtLeastNWidgets(1));
    });
  });
}
