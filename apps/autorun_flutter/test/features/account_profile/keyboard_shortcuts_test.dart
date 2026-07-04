// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/screens/account_profile_screen.dart';

import 'account_profile_test_helpers.dart';

/// UX-9 keyboard-shortcut coverage for the Account profile screen:
/// - `Ctrl/Cmd+S` saves profile edits (registered mode only).
/// - `Esc` pops back to the previous route.
///
/// `defaultTargetPlatform` is `android` inside `flutter_test`, which would
/// leave `ScreenShortcuts` as a no-op pass-through. Each test forces a
/// desktop platform and restores it before the binding's invariant checks
/// run (mirrors the `desktopTest` helper in
/// `test/widgets/keyboard_shortcuts_test.dart`).
void main() {
  setUpAll(AccountProfileScreenTestHelper.registerFallbackValues);

  LogicalKeyboardKey modKey() => defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;

  group('AccountProfileScreen keyboard shortcuts (UX-9)', () {
    late MockAccountController accountController;
    late MockProfileController profileController;
    late Account account;
    late Profile profile;

    setUp(() async {
      accountController = MockAccountController();
      profileController = MockProfileController();

      final setup =
          await AccountProfileScreenTestHelper.createMatchingAccountAndProfile(
        username: 'testuser',
        displayName: 'Test User',
      );
      account = setup.account;
      profile = setup.profile;

      // The runner calls refreshAccount in initState; stub it so the screen
      // settles without throwing.
      when(() => accountController.refreshAccount(any()))
          .thenAnswer((_) async => account);
      when(() => profileController.findById(any())).thenReturn(profile);
    });

    testWidgets('Save Changes button surfaces the Ctrl/Cmd+S tooltip hint',
        (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
          tester,
          account: account,
          accountController: accountController,
          profile: profile,
          profileController: profileController,
        );

        // The shortcut hint shows in the tooltip so the binding is discoverable.
        expect(find.byTooltip('Save Changes (Ctrl+S)'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('Ctrl/Cmd+S saves profile edits', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        when(() => accountController.updateProfile(
              username: any(named: 'username'),
              signingKeypair: any(named: 'signingKeypair'),
              displayName: any(named: 'displayName'),
              contactEmail: any(named: 'contactEmail'),
              contactTelegram: any(named: 'contactTelegram'),
              contactTwitter: any(named: 'contactTwitter'),
              contactDiscord: any(named: 'contactDiscord'),
              websiteUrl: any(named: 'websiteUrl'),
              bio: any(named: 'bio'),
            )).thenAnswer((_) async => account);

        await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
          tester,
          account: account,
          accountController: accountController,
          profile: profile,
          profileController: profileController,
        );

        // Drive save via the keyboard shortcut — no button tap.
        await tester.sendKeyDownEvent(modKey());
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(modKey());
        await tester.pumpAndSettle();

        verify(() => accountController.updateProfile(
              username: any(named: 'username'),
              signingKeypair: any(named: 'signingKeypair'),
              displayName: any(named: 'displayName'),
              contactEmail: any(named: 'contactEmail'),
              contactTelegram: any(named: 'contactTelegram'),
              contactTwitter: any(named: 'contactTwitter'),
              contactDiscord: any(named: 'contactDiscord'),
              websiteUrl: any(named: 'websiteUrl'),
              bio: any(named: 'bio'),
            )).called(1);
        expect(find.text('Profile updated successfully'), findsOneWidget,
            reason: 'Ctrl/Cmd+S must run the same Save Changes flow as the button');
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets(
        'Ctrl/Cmd+S fires EVEN while editing a text field (modifier shortcut)',
        (tester) async {
      // Edit-then-save is the desktop idiom: the user types into the display
      // name field and immediately hits Ctrl/Cmd+S. The platform modifier
      // means this never conflicts with typing an `s`, so it must fire from
      // inside the focused TextField.
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        when(() => accountController.updateProfile(
              username: any(named: 'username'),
              signingKeypair: any(named: 'signingKeypair'),
              displayName: any(named: 'displayName'),
              contactEmail: any(named: 'contactEmail'),
              contactTelegram: any(named: 'contactTelegram'),
              contactTwitter: any(named: 'contactTwitter'),
              contactDiscord: any(named: 'contactDiscord'),
              websiteUrl: any(named: 'websiteUrl'),
              bio: any(named: 'bio'),
            )).thenAnswer((_) async => account);

        await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
          tester,
          account: account,
          accountController: accountController,
          profile: profile,
          profileController: profileController,
        );

        // Focus the display-name field and type into it.
        final displayField = tester.widgetList<TextField>(find.byType(TextField)).firstWhere(
          (tf) => tf.decoration?.labelText == 'Display Name *',
        );
        await tester.enterText(find.byWidget(displayField), 'Edited Name');
        await tester.pump();

        // Now hit Ctrl/Cmd+S from inside the focused field.
        await tester.sendKeyDownEvent(modKey());
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(modKey());
        await tester.pumpAndSettle();

        verify(() => accountController.updateProfile(
              username: any(named: 'username'),
              signingKeypair: any(named: 'signingKeypair'),
              displayName: any(named: 'displayName'),
              contactEmail: any(named: 'contactEmail'),
              contactTelegram: any(named: 'contactTelegram'),
              contactTwitter: any(named: 'contactTwitter'),
              contactDiscord: any(named: 'contactDiscord'),
              websiteUrl: any(named: 'websiteUrl'),
              bio: any(named: 'bio'),
            )).called(1);
        expect(find.text('Profile updated successfully'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('Esc pops the account profile back to the previous route',
        (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        // Pump a ROOT route that pushes AccountProfileScreen on tap so
        // Navigator.pop has somewhere to pop back to.
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AccountProfileScreen(
                          account: account,
                          accountController: accountController,
                          profile: profile,
                          profileController: profileController,
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountProfileScreen), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byType(AccountProfileScreen), findsNothing,
            reason: 'Esc must pop the account screen back to the caller');
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('local-only mode has no Save Changes binding (Ctrl/Cmd+S inert)',
        (tester) async {
      // In local-only mode (account == null), there is no backend save flow.
      // ScreenShortcuts is constructed with onSave: null, so Ctrl/Cmd+S must
      // NOT fire — it should pass through (here, do nothing observable).
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: AccountProfileScreen(
              account: null,
              accountController: accountController,
              profile: profile,
              profileController: profileController,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Local-only mode never renders the Save Changes button.
        expect(find.text('Save Changes'), findsNothing);

        await tester.sendKeyDownEvent(modKey());
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(modKey());
        await tester.pumpAndSettle();

        verifyNever(() => accountController.updateProfile(
              username: any(named: 'username'),
              signingKeypair: any(named: 'signingKeypair'),
              displayName: any(named: 'displayName'),
              contactEmail: any(named: 'contactEmail'),
              contactTelegram: any(named: 'contactTelegram'),
              contactTwitter: any(named: 'contactTwitter'),
              contactDiscord: any(named: 'contactDiscord'),
              websiteUrl: any(named: 'websiteUrl'),
              bio: any(named: 'bio'),
            ));
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });
  });
}
