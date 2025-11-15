import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/main.dart';

void main() {
  testWidgets('prefills method when selecting a well-known canister', (tester) async {
    await tester.pumpWidget(const IdentityApp());
    // Navigate to Favorites screen first
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Tap a well-known canister entry (NNS Registry) on the Favorites screen
    expect(find.text('Well-known canisters'), findsWidgets);
    await tester.tap(find.text('NNS Registry').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Bottom sheet should open
    expect(find.text('ICP Canister Client'), findsOneWidget);

    // Method field should be prefilled from the well-known entry
    final methodField = find.byKey(const Key('methodField'));
    expect(methodField, findsOneWidget);
    final TextField field = tester.widget(methodField);
    expect(field.controller!.text, 'get_value');
  });
}
