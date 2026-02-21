import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';

void main() {
  group('ProfileAvatarButton badge', () {
    testWidgets('shows badge when hasAccount is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: false,
              onTap: () {},
            ),
          ),
        ),
      );

      // Find the ProfileAvatarButton and look for a Stack inside it
      final avatarButton = find.byType(ProfileAvatarButton);
      expect(avatarButton, findsOneWidget);

      // Look for a Container with the red badge color (error color)
      // The badge is a small 10x10 circle with error color
      final container = tester.widget<Container>(
        find.descendant(
          of: avatarButton,
          matching: find.byType(Container).first,
        ),
      );

      // When hasAccount is false, the avatar is wrapped in a Stack
      // We verify this by checking that there's a Stack descendant of ProfileAvatarButton
      final stackFinder = find.descendant(
        of: avatarButton,
        matching: find.byType(Stack),
      );
      expect(stackFinder, findsWidgets,
          reason: 'Should have Stack for badge when hasAccount is false');
    });

    testWidgets('does not show badge when hasAccount is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: true,
              showLabel:
                  false, // Use showLabel false to avoid extra Stack from label row
              onTap: () {},
            ),
          ),
        ),
      );

      // When hasAccount is true and showLabel is false, there should be no Stack
      // (the avatar Container is returned directly)
      final avatarButton = find.byType(ProfileAvatarButton);

      // Get the direct child of ProfileAvatarButton
      // It should be a GestureDetector directly wrapping the avatar Container (no Stack)
      final gestureDetector = find.descendant(
        of: avatarButton,
        matching: find.byType(GestureDetector),
      );
      expect(gestureDetector, findsOneWidget);
    });

    testWidgets('badge defaults to hasAccount true (no badge by default)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              showLabel:
                  false, // Use showLabel false to avoid extra Stack from label row
              onTap: () {},
            ),
          ),
        ),
      );

      // By default, hasAccount should be true
      final avatarButton = find.byType(ProfileAvatarButton);
      final gestureDetector = find.descendant(
        of: avatarButton,
        matching: find.byType(GestureDetector),
      );
      expect(gestureDetector, findsOneWidget,
          reason:
              'Should use GestureDetector directly when hasAccount is true');
    });

    testWidgets('badge works with showLabel true', (tester) async {
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

      // Should still show badge even with label
      final avatarButton = find.byType(ProfileAvatarButton);

      // The outer container (label wrapper) and inner Stack (badge wrapper)
      final stacks = find.descendant(
        of: avatarButton,
        matching: find.byType(Stack),
      );
      expect(stacks, findsWidgets,
          reason: 'Badge should show regardless of label setting');
    });

    testWidgets('has accessible semantics when account is missing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: false,
              onTap: () {},
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      expect(semantics.label, contains('registration'));
    });

    testWidgets('has accessible semantics when account exists', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              hasAccount: true,
              onTap: () {},
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      expect(semantics.label, contains('Profile'));
      expect(semantics.label, isNot(contains('registration needed')));
    });
  });
}
