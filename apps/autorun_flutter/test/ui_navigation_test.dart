import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/main.dart';

void main() {
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
    // Identities screen title is present
    expect(find.text('ICP Identity Manager'), findsOneWidget);

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
}
