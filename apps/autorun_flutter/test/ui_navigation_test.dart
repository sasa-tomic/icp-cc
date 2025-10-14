import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/main.dart';

void main() {
  testWidgets('shows Favorites as home and navigates to Identities', (WidgetTester tester) async {
    await tester.pumpWidget(const IdentityApp());

    // App starts on Favorites screen (via MainHomePage)
    expect(find.text('Favorites'), findsWidgets);

    // Switch to Identities tab
    await tester.tap(find.byIcon(Icons.verified_user));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Identities screen title is present
    expect(find.text('ICP Identity Manager'), findsOneWidget);

    // Switch back to Favorites
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
