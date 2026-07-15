import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';

/// W7-19 (Fix 7): the profile chip's a11y label is a clean sentence (with the
/// display name) and the avatar initials are no longer spliced mid-sentence
/// into the spoken label.
void main() {
  group('ProfileAvatarButton a11y label (W7-19)', () {
    testWidgets('uses a clean sentence with the display name', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProfileAvatarButton(
            displayName: 'Wave Seven',
            hasAccount: true,
            showLabel: true,
            onTap: () {},
          ),
        ),
      ));

      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      expect(semantics.label, 'Profile: Wave Seven. Tap to open.');
    });

    testWidgets('does NOT splice the avatar initials into the label',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProfileAvatarButton(
            displayName: 'Wave Seven',
            hasAccount: true,
            showLabel: true,
            onTap: () {},
          ),
        ),
      ));

      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      // The initials for "Wave Seven" are "WS"; they must not be read aloud
      // as part of the button label.
      expect(semantics.label, isNot(contains('WS')));
      // The visible "Profile" text must not be appended a second time either.
      expect(semantics.label, 'Profile: Wave Seven. Tap to open.');
    });

    testWidgets('no-account chip announces a clean, honest sentence',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProfileAvatarButton(
            displayName: 'Wave Seven',
            hasAccount: false,
            showLabel: true,
            onTap: () {},
          ),
        ),
      ));

      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      expect(semantics.label, 'Profile menu, no account registered. Tap to open.');
      // Initials excluded even in the no-account state.
      expect(semantics.label, isNot(contains('WS')));
    });

    testWidgets('avatar-only (no label) still excludes initials from a11y',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProfileAvatarButton(
            displayName: 'Wave Seven',
            hasAccount: true,
            showLabel: false,
            onTap: () {},
          ),
        ),
      ));

      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      expect(semantics.label, 'Profile: Wave Seven. Tap to open.');
      expect(semantics.label, isNot(contains('WS')));
    });
  });
}
