import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/script_upload_screen.dart';

void main() {
  group('ScriptUploadScreen', () {
    Widget createWidget({PreFilledUploadData? preFilledData}) {
      return MaterialApp(
        home: ScriptUploadScreen(
          preFilledData: preFilledData,
        ),
      );
    }

    group('basic UI', () {
      testWidgets('should display upload screen', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(ScriptUploadScreen), findsOneWidget);
        expect(find.text('Upload Script'), findsAtLeastNWidgets(1));
      });

      testWidgets('should show form fields', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(TextFormField), findsNWidgets(10));
        expect(find.text('Title'), findsOneWidget);
        expect(find.text('Description'), findsOneWidget);
        expect(find.text('Author Name'), findsOneWidget);
        expect(find.text('Category'), findsOneWidget);
        expect(find.text('Price (in ICP)'), findsOneWidget);
        expect(find.text('Version'), findsOneWidget);
      });
    });

    group('with pre-filled data', () {
      testWidgets('should pre-fill title and author', (WidgetTester tester) async {
        // Arrange
        final preFilledData = PreFilledUploadData(
          title: 'My Awesome Script',
          luaSource: 'print("Hello World")',
          authorName: 'John Doe',
        );

        // Act
        await tester.pumpWidget(createWidget(preFilledData: preFilledData));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('My Awesome Script'), findsOneWidget);
        expect(find.text('John Doe'), findsOneWidget);
        expect(find.text('print("Hello World")'), findsOneWidget);
      });

      testWidgets('should use default author when not provided', (WidgetTester tester) async {
        // Arrange
        final preFilledData = PreFilledUploadData(
          title: 'My Script',
          luaSource: 'print("test")',
          authorName: '',
        );

        // Act
        await tester.pumpWidget(createWidget(preFilledData: preFilledData));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('My Script'), findsOneWidget);
        expect(find.text('Anonymous Developer'), findsOneWidget);
      });
    });

    group('form sections', () {
      testWidgets('should display all form sections', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Basic Information'), findsOneWidget);
        expect(find.text('Category and Tags'), findsOneWidget);
        expect(find.text('ICP Integration (Optional)'), findsOneWidget);
        expect(find.text('Media (Optional)'), findsOneWidget);
        expect(find.text('Pricing'), findsOneWidget);
        expect(find.text('Script Code'), findsOneWidget);
      });
    });

    group('default values', () {
      testWidgets('should show default values', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('1.0.0'), findsOneWidget); // Default version
        expect(find.text('0.0'), findsOneWidget); // Default price
        expect(find.text('Utilities'), findsOneWidget); // Default category
      });
    });

    group('script editor', () {
      testWidgets('should show script editor', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Write your Lua script code below'), findsOneWidget);
      });

      testWidgets('should show validation info initially', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Click "Validate Script" to check your code for syntax errors'), findsOneWidget);
        expect(find.text('Validate Script'), findsOneWidget);
      });
    });

    group('category selection', () {
      testWidgets('should show category dropdown', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Category'), findsOneWidget);
        expect(find.text('Utilities'), findsOneWidget); // Default selection
      });
    });

    group('navigation', () {
      testWidgets('should have app bar', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(createWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(AppBar), findsOneWidget);
      });
    });

    group('error handling', () {
      testWidgets('should handle empty pre-filled data gracefully', (WidgetTester tester) async {
        // Arrange
        final preFilledData = PreFilledUploadData(
          title: '',
          luaSource: '',
          authorName: '',
        );

        // Act
        await tester.pumpWidget(createWidget(preFilledData: preFilledData));
        await tester.pumpAndSettle();

        // Assert - Should still show form without crashing
        expect(find.byType(ScriptUploadScreen), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(10));
      });
    });
  });
}