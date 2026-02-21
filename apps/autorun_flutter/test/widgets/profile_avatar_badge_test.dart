import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';

void main() {
  group('ProfileAvatarButton - subtle text indicator (no red badge)', () {
    testWidgets(
        'shows "No account" text when hasAccount is false with showLabel',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: false,
              showLabel: true,
              onTap: () {},
            ),
          ),
        ),
      );

      // Find the ProfileAvatarButton
      final avatarButton = find.byType(ProfileAvatarButton);
      expect(avatarButton, findsOneWidget);

      // Should show subtle "No account" text instead of red badge
      expect(find.text('No account'), findsOneWidget,
          reason: 'Should show "No account" text when hasAccount is false');
    });

    testWidgets(
        'does NOT show red badge (error color) when hasAccount is false',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: false,
              showLabel: false, // No label to isolate avatar
              onTap: () {},
            ),
          ),
        ),
      );

      // The avatar should NOT have a Stack with red badge
      // Instead, it should be a simple GestureDetector wrapping the avatar
      final avatarButton = find.byType(ProfileAvatarButton);
      final gestureDetector = find.descendant(
        of: avatarButton,
        matching: find.byType(GestureDetector),
      );
      expect(gestureDetector, findsOneWidget,
          reason: 'Should use GestureDetector when no red badge');
    });

    testWidgets('does NOT show "No account" text when hasAccount is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: true,
              showLabel: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('No account'), findsNothing,
          reason: 'Should not show "No account" when account exists');
    });

    testWidgets('defaults to hasAccount true (no indicator by default)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              showLabel: true,
              onTap: () {},
            ),
          ),
        ),
      );

      // By default, hasAccount should be true
      expect(find.text('No account'), findsNothing,
          reason: 'Should not show indicator when hasAccount defaults to true');
    });

    testWidgets('has accessible semantics when account is missing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: false,
              showLabel: true,
              onTap: () {},
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      // Should mention "no account" but not "registration needed" (too alarming)
      expect(semantics.label, contains('no account'));
    });

    testWidgets('has accessible semantics when account exists', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: true,
              showLabel: true,
              onTap: () {},
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      expect(semantics.label, contains('Profile'));
      expect(semantics.label, isNot(contains('no account')));
    });
  });
}
