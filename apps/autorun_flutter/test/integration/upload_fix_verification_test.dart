import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/widgets/quick_upload_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/wrangler_manager.dart';

void main() {
  group('Upload Fix Verification Tests', () {
    setUpAll(() async {
      await WranglerManager.initialize();
      SharedPreferences.setMockInitialValues({});
    });

    tearDownAll(() async {
      await WranglerManager.cleanup();
    });

    Widget createTestApp({required Widget child}) {
      return MaterialApp(
        home: Scaffold(
          body: child,
        ),
      );
    }

    testWidgets('Upload dialog with valid form should succeed', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(
        child: QuickUploadDialog(),
      ));
      await tester.pumpAndSettle();

      // Fill form with valid data
      final testTitle = 'Fix Verification Test ${DateTime.now().millisecondsSinceEpoch}';
      
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title *'),
        testTitle,
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description *'),
        'Test script for upload fix verification',
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Author Name *'),
        'Fix Verification Test Runner',
      );
      await tester.pumpAndSettle();

      // Select a valid category (not 'Example')
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Category *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Development').last);
      await tester.pumpAndSettle();

      // Debug: Print all form field values
        print('Form values filled:');
        print('- Title: $testTitle');
        print('- Description: Test script for upload fix verification');
        print('- Author: Fix Verification Test Runner');
        print('- Category: Development');

      // Submit form
      final uploadButton = find.text('Upload to Marketplace').first;
      print('Upload button found: ${uploadButton.evaluate().isNotEmpty}');
      if (uploadButton.evaluate().isEmpty) {
        print('Upload button not found, might be in uploading state');
        // Look for any button with upload-related text
        final alternativeButton = find.textContaining('Upload').first;
        if (alternativeButton.evaluate().isNotEmpty) {
          print('Found alternative upload button');
          await tester.tap(alternativeButton);
        }
      } else {
        print('Upload button found and ready');
        await tester.tap(uploadButton);
      }
      await tester.pumpAndSettle();

      // Wait for upload to complete
      print('Waiting for upload to complete...');
      await tester.pumpAndSettle(Duration(seconds: 5));

      // Look for success message
      final successMessage = find.textContaining('successfully uploaded');
      print('Success message found: ${successMessage.evaluate().isNotEmpty}');
      
      // Look for any SnackBar (error messages)
      final errorMessages = find.byType(SnackBar);
      print('Total SnackBars found: ${errorMessages.evaluate().length}');
      
      // Check for error text in dialog
      final errorText = find.textContaining('Upload failed');
      print('Error text found: ${errorText.evaluate().isNotEmpty}');
      
      // Check if dialog closed (success path)
      final dialogClosed = find.byType(AlertDialog).evaluate().isEmpty;
      print('Dialog closed: $dialogClosed');
      
      // Should show success message in SnackBar OR dialog should be closed
      expect(successMessage.evaluate().isNotEmpty || dialogClosed, isTrue,
          reason: 'Either success message should appear or dialog should close on success');
      
      print('✅ Upload dialog form submission works!');
    });
  });
}