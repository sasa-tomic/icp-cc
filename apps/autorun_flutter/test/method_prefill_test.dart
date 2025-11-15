import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/main.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'test_helpers/wrangler_manager.dart';

void main() {
  setUpAll(() async {
    // Initialize test environment with Cloudflare Workers endpoint
    suppressDebugOutput = true; // Suppress debug output during tests
    try {
      await WranglerManager.initialize();
    } catch (e) {
      // If the service isn't available, skip these tests
      debugPrint('Warning: Cloudflare Workers not available, skipping method prefill tests: $e');
    }
  });
  testWidgets('prefills method when selecting a well-known canister', (tester) async {
    await tester.pumpWidget(const IdentityApp());
    // Navigate to Bookmarks screen first
    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // Give more time for content to load

    // Tap a well-known canister entry (NNS Registry) on the Bookmarks screen
    expect(find.text('Popular Canisters'), findsWidgets);
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
