import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/main.dart';
import 'test_helpers/wrangler_manager.dart';

void main() {
  setUpAll(() async {
    // Set up test endpoint to avoid HTTP 400 errors
    await WranglerManager.initialize();
  });
  
  tearDownAll(() async {
    await WranglerManager.cleanup();
  });

  testWidgets('app runs without exceptions and handles navigation correctly', (WidgetTester tester) async {
    // This test ensures no exceptions are thrown during app lifecycle
    // and specifically tests that Hero tag conflicts are avoided
    
    await tester.pumpWidget(const IdentityApp());
    
    // Initial state - should not throw any exceptions
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // Give more time for initial load
    expect(find.text('New Script'), findsOneWidget);
    
    // Test that we can navigate between all screens without Hero conflicts
    // Scripts -> Bookmarks
    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Bookmarks'), findsWidgets);
    
    // Bookmarks -> Identities (this would trigger Hero conflict if tags weren't unique)
    await tester.tap(find.byIcon(Icons.verified_user_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('New Identity'), findsOneWidget);
    
    // Identities -> Scripts (back to original)
    await tester.tap(find.byIcon(Icons.code_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('New Script'), findsOneWidget);
    
    // Test that FABs can be tapped without issues
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    
    // Close any dialogs that might have opened
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await tester.tap(find.text('Cancel'));
      await tester.pump();
    }
  });

  testWidgets('shows Scripts as home and navigates to Bookmarks and Identities', (WidgetTester tester) async {
    await tester.pumpWidget(const IdentityApp());
    // App starts on Scripts screen (via MainHomePage)
    // Accept the initial state by checking the FAB label unique to Scripts
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('New Script'), findsOneWidget);

    // Switch to Bookmarks tab
    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Bookmarks title is present
    expect(find.text('Bookmarks'), findsWidgets);

    // Switch to Identities tab
    await tester.tap(find.byIcon(Icons.verified_user_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Identities screen FAB unique label is present
    expect(find.text('New Identity'), findsOneWidget);

    // Switch back to Bookmarks and open client
    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Can open Canister client sheet
    await tester.tap(find.byIcon(Icons.cloud_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ICP Canister Client'), findsOneWidget);
  });

  testWidgets('FloatingActionButtons have unique hero tags', (WidgetTester tester) async {
    // This test specifically verifies that FloatingActionButtons have unique hero tags
    // to prevent the "multiple heroes that share the same tag" error
    
    await tester.pumpWidget(const IdentityApp());
    await tester.pump(const Duration(milliseconds: 200));
    
    // Test Scripts screen FAB
    expect(find.text('New Script'), findsOneWidget);
    final scriptsFab = find.byType(FloatingActionButton);
    expect(scriptsFab, findsOneWidget);
    
    final scriptsFabWidget = tester.widget<FloatingActionButton>(scriptsFab);
    expect(scriptsFabWidget.heroTag, equals('scripts_fab'));
    
    // Navigate to Identities screen and test its FAB
    final identitiesIcon = find.byIcon(Icons.verified_user_outlined);
    expect(identitiesIcon, findsOneWidget);
    await tester.tap(identitiesIcon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('New Identity'), findsOneWidget);
    
    final identitiesFab = find.byType(FloatingActionButton);
    expect(identitiesFab, findsOneWidget);
    
    final identitiesFabWidget = tester.widget<FloatingActionButton>(identitiesFab);
    expect(identitiesFabWidget.heroTag, equals('identities_fab'));
    
    // Verify the tags are different
    expect(scriptsFabWidget.heroTag, isNot(equals(identitiesFabWidget.heroTag)));
    
    // Navigate back to Scripts screen to ensure no conflicts
    await tester.tap(find.byIcon(Icons.code_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('New Script'), findsOneWidget);
    
    // Verify we can still find the scripts FAB with correct tag
    final scriptsFabAgain = find.byType(FloatingActionButton);
    expect(scriptsFabAgain, findsOneWidget);
    final scriptsFabWidgetAgain = tester.widget<FloatingActionButton>(scriptsFabAgain);
    expect(scriptsFabWidgetAgain.heroTag, equals('scripts_fab'));
  });
}
