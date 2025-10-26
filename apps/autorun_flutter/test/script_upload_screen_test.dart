import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/script_upload_screen.dart';

void main() {
  group('ScriptUploadScreen Tests', () {

    testWidgets('Script upload screen displays correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptUploadScreen(),
        ),
      );

      // Check that the screen title is displayed
      expect(find.text('Upload Script'), findsAtLeastNWidgets(1));

      // Check that basic form sections are present
      expect(find.text('Basic Information'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Author Name'), findsOneWidget);

       // Check that other sections are present
       expect(find.text('Category and Tags'), findsOneWidget);
       expect(find.text('ICP Integration (Optional)'), findsOneWidget);
       expect(find.text('Media (Optional)'), findsOneWidget);
       expect(find.text('Pricing'), findsOneWidget);
    });

    testWidgets('Title field is present and accepts input', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptUploadScreen(),
        ),
      );

      // Find title field
      final titleField = find.widgetWithText(TextFormField, 'Title');
      expect(titleField, findsOneWidget);

      // Enter text in title field
      await tester.enterText(titleField, 'Test Script Title');
      await tester.pump();

      // Verify text was entered
      expect(find.text('Test Script Title'), findsOneWidget);
    });

    testWidgets('Category dropdown is present', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptUploadScreen(),
        ),
      );

      // Find category dropdown
      final categoryDropdown = find.byType(DropdownButtonFormField<String>);
      expect(categoryDropdown, findsOneWidget);
    });

    testWidgets('Upload button is present', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptUploadScreen(),
        ),
      );

      // Check that upload button exists
      expect(find.text('Upload Script'), findsAtLeastNWidgets(1));
    });

    testWidgets('Form contains validation elements', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScriptUploadScreen(),
        ),
      );

      // Check that form exists
      expect(find.byType(Form), findsOneWidget);

      // Check that important fields exist
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Price (in ICP)'), findsOneWidget);
      expect(find.text('Version'), findsOneWidget);
    });
  });
}