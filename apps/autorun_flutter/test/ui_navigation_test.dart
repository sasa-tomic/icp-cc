import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/main.dart';

void main() {
  testWidgets('app runs without exceptions and handles navigation correctly', (WidgetTester tester) async {
    // This test ensures no exceptions are thrown during app lifecycle
    // and specifically tests that Hero tag conflicts are avoided
    
    await tester.pumpWidget(const IdentityApp());
    
    // Initial state - should not throw any exceptions
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('New script'), findsOneWidget);
    
    // Test that we can navigate between all screens without Hero conflicts
    // Scripts -> Favorites
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Favorites'), findsWidgets);
    
    // Favorites -> Identities (this would trigger Hero conflict if tags weren't unique)
    await tester.tap(find.byIcon(Icons.verified_user));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('New identity'), findsOneWidget);
    
    // Identities -> Scripts (back to original)
    await tester.tap(find.byIcon(Icons.code));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('New script'), findsOneWidget);
    
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

  testWidgets('shows Scripts as home and navigates to Favorites and Identities', (WidgetTester tester) async {
    await tester.pumpWidget(const IdentityApp());
    // App starts on Scripts screen (via MainHomePage)
    // Accept the initial state by checking the FAB label unique to Scripts
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('New script'), findsOneWidget);

    // Switch to Favorites tab
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Favorites title is present
    expect(find.text('Favorites'), findsWidgets);

    // Switch to Identities tab
    await tester.tap(find.byIcon(Icons.verified_user));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Identities screen FAB unique label is present
    expect(find.text('New identity'), findsOneWidget);

    // Switch back to Favorites and open client
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Can open Canister client sheet
    await tester.tap(find.byIcon(Icons.cloud));
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
    expect(find.text('New script'), findsOneWidget);
    final scriptsFab = find.byType(FloatingActionButton);
    expect(scriptsFab, findsOneWidget);
    
    final scriptsFabWidget = tester.widget<FloatingActionButton>(scriptsFab);
    expect(scriptsFabWidget.heroTag, equals('scripts_fab'));
    
    // Navigate to Identities screen and test its FAB
    await tester.tap(find.byIcon(Icons.verified_user));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('New identity'), findsOneWidget);
    
    final identitiesFab = find.byType(FloatingActionButton);
    expect(identitiesFab, findsOneWidget);
    
    final identitiesFabWidget = tester.widget<FloatingActionButton>(identitiesFab);
    expect(identitiesFabWidget.heroTag, equals('identities_fab'));
    
    // Verify the tags are different
    expect(scriptsFabWidget.heroTag, isNot(equals(identitiesFabWidget.heroTag)));
    
    // Navigate back to Scripts screen to ensure no conflicts
    await tester.tap(find.byIcon(Icons.code));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('New script'), findsOneWidget);
    
    // Verify we can still find the scripts FAB with correct tag
    final scriptsFabAgain = find.byType(FloatingActionButton);
    expect(scriptsFabAgain, findsOneWidget);
    final scriptsFabWidgetAgain = tester.widget<FloatingActionButton>(scriptsFabAgain);
    expect(scriptsFabWidgetAgain.heroTag, equals('scripts_fab'));
  });
}
