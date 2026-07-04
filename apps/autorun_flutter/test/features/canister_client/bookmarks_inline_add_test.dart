import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/screens/bookmarks_screen.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';

import '../../shared/fake_connectivity_service.dart';

/// UX-4 — the inline Add-Bookmark form on the Canisters (Bookmarks) screen.
///
/// These tests pump the REAL [BookmarksScreen] (the Canisters tab body) and
/// verify the collapsed→expand→validate UX wiring at the screen level. They
/// deliberately stay on the synchronous paths (no real file I/O) because the
/// screen embeds a [ModernEmptyState] whose perpetual animations make
/// `pumpAndSettle` impossible, and `tester.pump` does not progress real
/// `dart:io` writes. The save/Enter-to-save/error-surfacing behavior itself is
/// codified by [test/bookmark_composer_test.dart] against the same
/// [_BookmarkComposerState._handleSubmit] code path (the composer is agnostic
/// to whether [onSave] is the real [BookmarksService.add] or an injected
/// callback).
void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectivityScope(
            service: FakeConnectivityService(),
            child: const BookmarksScreen(bridge: RustBridgeLoader()),
          ),
        ),
      ),
    );
    // Let ConnectivityScope's async init + the bookmarks list load settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  group('UX-4 inline Add-Bookmark (BookmarksScreen)', () {
    testWidgets('the inline form is collapsed by default on the Canisters tab',
        (tester) async {
      await pumpScreen(tester);

      // The compact toggle is rendered in the "Your Bookmarks" section…
      expect(find.byKey(const Key('bookmarkComposerToggleButton')), findsOneWidget);
      // …and the heavier form is NOT on screen (de-cluttered — UX-4).
      expect(find.byKey(const Key('bookmarkComposerCanisterField')), findsNothing);
      expect(find.byKey(const Key('bookmarkComposerSubmitButton')), findsNothing);
    });

    testWidgets('tapping the toggle expands the inline form inline (no sheet)',
        (tester) async {
      await pumpScreen(tester);

      final toggle = find.byKey(const Key('bookmarkComposerToggleButton'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The form mounts IN PLACE — no modal sheet/dialog is opened.
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const Key('bookmarkComposerCanisterField')), findsOneWidget);
      expect(find.byKey(const Key('bookmarkComposerMethodField')), findsOneWidget);
      expect(find.byKey(const Key('bookmarkComposerLabelField')), findsOneWidget);
      expect(find.byKey(const Key('bookmarkComposerSubmitButton')), findsOneWidget);
    });

    testWidgets(
        'a malformed canister id keeps the Add button disabled and shows a clear inline error',
        (tester) async {
      await pumpScreen(tester);

      final toggle = find.byKey(const Key('bookmarkComposerToggleButton'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final cidField = find.byKey(const Key('bookmarkComposerCanisterField'));
      await tester.ensureVisible(cidField);
      await tester.enterText(cidField, '!!!not a canister!!!');
      final methodField = find.byKey(const Key('bookmarkComposerMethodField'));
      await tester.ensureVisible(methodField);
      await tester.enterText(methodField, 'icrc1_balance_of');
      await tester.pump();

      // Add button is disabled while the input is invalid (no silent save).
      final submit = find.byKey(const Key('bookmarkComposerSubmitButton'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      // Triggering submit via the method field's Enter surfaces the specific
      // error inline; the form stays open so the user can correct it.
      await tester.ensureVisible(submit);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.byKey(const Key('bookmarkComposerError')), findsOneWidget);
      expect(find.text('Enter a valid canister ID.'), findsOneWidget);
      expect(find.byKey(const Key('bookmarkComposerCanisterField')), findsOneWidget);
    });

    testWidgets('valid input enables the Add button (ready to save inline)',
        (tester) async {
      await pumpScreen(tester);

      final toggle = find.byKey(const Key('bookmarkComposerToggleButton'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final cidField = find.byKey(const Key('bookmarkComposerCanisterField'));
      await tester.ensureVisible(cidField);
      await tester.enterText(cidField, 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      final methodField = find.byKey(const Key('bookmarkComposerMethodField'));
      await tester.ensureVisible(methodField);
      await tester.enterText(methodField, 'account_balance_dfx');
      await tester.pump();

      final submit = find.byKey(const Key('bookmarkComposerSubmitButton'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull,
          reason: 'Add button must be enabled once canister id + method are valid.');
    });

    testWidgets('the collapse affordance hides the form without saving',
        (tester) async {
      await pumpScreen(tester);

      final toggle = find.byKey(const Key('bookmarkComposerToggleButton'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Type something, then collapse — the form disappears, toggle returns.
      await tester.enterText(
          find.byKey(const Key('bookmarkComposerCanisterField')), 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('bookmarkComposerCollapseButton')));
      await tester.tap(find.byKey(const Key('bookmarkComposerCollapseButton')));
      await tester.pump();

      expect(find.byKey(const Key('bookmarkComposerToggleButton')), findsOneWidget);
      expect(find.byKey(const Key('bookmarkComposerCanisterField')), findsNothing);
    });
  });
}
