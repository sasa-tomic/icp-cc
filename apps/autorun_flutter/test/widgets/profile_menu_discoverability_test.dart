import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';

void main() {
  group('ProfileAvatarButton discoverability', () {
    testWidgets('shows Profile label next to avatar',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('label is tappable along with avatar',
        (WidgetTester tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Profile'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('maintains avatar visibility with label',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Profile'), findsOneWidget);

      expect(find.byType(Row), findsOneWidget);

      final sizedBox = find.byType(SizedBox);
      expect(sizedBox, findsWidgets);
    });

    testWidgets('shows correct accessibility label',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              onTap: () {},
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(ProfileAvatarButton));
      expect(semantics.label, contains('Profile'));
    });

    testWidgets('renders in a row with proper spacing',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test User',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(Row), findsOneWidget);
    });
  });
}
