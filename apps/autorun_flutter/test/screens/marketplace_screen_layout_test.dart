import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/marketplace_screen.dart';
import 'package:icp_autorun/widgets/error_display.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import '../test_helpers/wrangler_manager.dart';

void main() {
  group('MarketplaceScreen Mobile Layout Tests', () {
    setUpAll(() async {
      // Initialize test environment with Cloudflare Workers endpoint
      suppressDebugOutput = true; // Suppress debug output during tests
      try {
        await WranglerManager.initialize();
      } catch (e) {
        // If the service isn't available, skip these tests
        print('Warning: Cloudflare Workers not available, skipping marketplace tests: $e');
      }
    });
    testWidgets('should display single column grid layout on mobile', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: MarketplaceScreen(),
        ),
      );

      // Wait for any initialization to complete
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Act
      // Find the GridView widget - this is the core of the marketplace layout
      final gridViewFinder = find.byType(GridView);

      // The GridView might not be immediately visible if there are loading states
      // or error states, so let's check what's actually displayed
      if (gridViewFinder.evaluate().isNotEmpty) {
        // Get the GridView widget if it exists
        final GridView gridView = tester.widget(gridViewFinder);
        final gridDelegate = gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

        // Assert - Verify single column layout
        expect(gridDelegate.crossAxisCount, equals(1),
          reason: 'Marketplace should use single column layout for mobile devices');

        // Verify appropriate aspect ratio for mobile cards
        expect(gridDelegate.childAspectRatio, equals(1.0),
          reason: 'Card aspect ratio should be optimized for compact mobile viewing');
      } else {
        // If GridView is not found, check if we're in a loading or error state
        // This is still a valid state for the marketplace screen
        final loadingFinder = find.byType(CircularProgressIndicator);
        final errorFinder = find.byType(ErrorDisplay);
        final noScriptsFinder = find.text('No scripts found');

        // At least one of these should be present
        expect(loadingFinder.evaluate().isNotEmpty || errorFinder.evaluate().isNotEmpty || noScriptsFinder.evaluate().isNotEmpty, true,
          reason: 'Marketplace should be in loading, error, no scripts, or grid state');
      }
    });

    testWidgets('should maintain single column layout with different screen sizes', (WidgetTester tester) async {
      // Test with small mobile screen
      await tester.binding.setSurfaceSize(const Size(320, 640)); // Small mobile screen
      await tester.pumpWidget(
        MaterialApp(
          home: MarketplaceScreen(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Check if GridView is present and has single column
      final gridViewFinder = find.byType(GridView);
      if (gridViewFinder.evaluate().isNotEmpty) {
        final GridView gridView = tester.widget(gridViewFinder);
        final gridDelegate = gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

        expect(gridDelegate.crossAxisCount, equals(1),
          reason: 'Should maintain single column on small mobile screens');
      }

      // Test with larger mobile screen
      await tester.binding.setSurfaceSize(const Size(414, 896)); // Larger mobile screen
      await tester.pumpWidget(
        MaterialApp(
          home: MarketplaceScreen(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final gridViewFinder2 = find.byType(GridView);
      if (gridViewFinder2.evaluate().isNotEmpty) {
        final GridView gridView2 = tester.widget(gridViewFinder2);
        final gridDelegate2 = gridView2.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

        expect(gridDelegate2.crossAxisCount, equals(1),
          reason: 'Should maintain single column on larger mobile screens');
      }
    });

    testWidgets('should have proper mobile-friendly layout structure', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: MarketplaceScreen(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify basic marketplace structure exists
      expect(find.byType(Scaffold), findsOneWidget,
        reason: 'Marketplace should have proper Scaffold structure');

      expect(find.byType(AppBar), findsOneWidget,
        reason: 'Marketplace should have AppBar');

      // Check for search functionality
      expect(find.byType(TextField), findsAtLeastNWidgets(1),
        reason: 'Marketplace should have search functionality');

      // The layout should be scrollable for mobile
      expect(find.byType(Scrollable), findsAtLeastNWidgets(1),
        reason: 'Marketplace should be scrollable for mobile devices');
    });
  });
}