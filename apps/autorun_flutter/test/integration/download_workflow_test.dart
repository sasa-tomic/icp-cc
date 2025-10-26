import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/download_history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Download Workflow Integration Tests', () {
    setUpAll(() async {
      // Mock SharedPreferences for tests
      SharedPreferences.setMockInitialValues({});
    });

    Widget createTestWidget({required Widget child}) {
      return MaterialApp(
        home: child,
      );
    }

    group('UI Integration Tests', () {
      testWidgets('should display download history screen', (WidgetTester tester) async {
        // Act - Navigate to download history
        await tester.pumpWidget(createTestWidget(
          child: DownloadHistoryScreen(),
        ));
        
        // Wait for the initial async operations to complete
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Assert - Verify download history screen loads
        expect(find.text('Download Library'), findsOneWidget);
        expect(find.text('No downloads yet'), findsOneWidget);
        expect(find.text('Scripts you download from the marketplace will appear here.'), findsOneWidget);
      });
    });
  });
}