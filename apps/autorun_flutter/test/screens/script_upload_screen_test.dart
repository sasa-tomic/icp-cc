import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/identity_controller.dart';
import 'package:icp_autorun/screens/script_upload_screen.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/identity_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/fake_secure_identity_repository.dart';
import '../test_helpers/test_identity_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<IdentityController> createControllerWithIdentity() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final identity = await TestIdentityFactory.getEd25519Identity();
    final controller = IdentityController(
      secureRepository: FakeSecureIdentityRepository([identity]),
      marketplaceService: MarketplaceOpenApiService(),
      preferences: await SharedPreferences.getInstance(),
    );
    await controller.ensureLoaded();
    await controller.setActiveIdentity(identity.id);
    return controller;
  }

  Future<Widget> createWidget({PreFilledUploadData? preFilledData}) async {
    final IdentityController controller = await createControllerWithIdentity();
    return IdentityScope(
      controller: controller,
      child: MaterialApp(
        home: ScriptUploadScreen(
          preFilledData: preFilledData,
        ),
      ),
    );
  }

  group('ScriptUploadScreen', () {
    group('basic UI', () {
      testWidgets('should display upload screen', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(await createWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(ScriptUploadScreen), findsOneWidget);
        expect(find.text('Upload Script'), findsAtLeastNWidgets(1));
      });

       testWidgets('should show form fields', (WidgetTester tester) async {
         // Act
         await tester.pumpWidget(await createWidget());
         await tester.pumpAndSettle();

          // Assert
          expect(find.byType(TextFormField), findsNWidgets(10));
          expect(find.text('Title'), findsOneWidget);
          expect(find.text('Description'), findsOneWidget);
          expect(find.text('Author Name'), findsOneWidget);
          expect(find.text('Category'), findsOneWidget);
          expect(find.text('Tags'), findsOneWidget);
          expect(find.text('Canister IDs'), findsOneWidget);
          expect(find.text('Compatibility Notes'), findsOneWidget);
          expect(find.text('Icon URL'), findsOneWidget);
          expect(find.text('Screenshots'), findsOneWidget);
        expect(find.text('Price (in ICP)'), findsOneWidget);
        expect(find.text('Version'), findsOneWidget);
        expect(find.text('Identity Context'), findsOneWidget);
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
         await tester.pumpWidget(await createWidget(preFilledData: preFilledData));
         await tester.pumpAndSettle();

         // Assert
         expect(find.text('My Awesome Script'), findsOneWidget);
         expect(find.text('John Doe'), findsOneWidget);
       });

      testWidgets('should use default author when not provided', (WidgetTester tester) async {
        // Arrange
        final preFilledData = PreFilledUploadData(
          title: 'My Script',
          luaSource: 'print("test")',
          authorName: '',
        );

        // Act
        await tester.pumpWidget(await createWidget(preFilledData: preFilledData));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('My Script'), findsOneWidget);
        expect(find.text('Anonymous Developer'), findsOneWidget);
      });
    });

    group('form sections', () {
       testWidgets('should display all form sections', (WidgetTester tester) async {
         // Act
         await tester.pumpWidget(await createWidget());
         await tester.pumpAndSettle();

         // Assert
         expect(find.text('Basic Information'), findsOneWidget);
         expect(find.text('Category and Tags'), findsOneWidget);
         expect(find.text('ICP Integration (Optional)'), findsOneWidget);
         expect(find.text('Media (Optional)'), findsOneWidget);
         expect(find.text('Pricing'), findsOneWidget);
       });
    });

    group('default values', () {
       testWidgets('should show default values', (WidgetTester tester) async {
         // Act
         await tester.pumpWidget(await createWidget());
         await tester.pumpAndSettle();

         // Assert
         expect(find.text('1.0.0'), findsOneWidget); // Default version
         expect(find.text('0.0'), findsOneWidget); // Default price
         expect(find.text('Example'), findsOneWidget); // Default category
       });
    });



    group('category selection', () {
      testWidgets('should show category dropdown', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(await createWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Category'), findsOneWidget);
        expect(find.text('Example'), findsOneWidget); // Default selection
      });
    });

    group('navigation', () {
      testWidgets('should have app bar', (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(await createWidget());
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
        await tester.pumpWidget(await createWidget(preFilledData: preFilledData));
        await tester.pumpAndSettle();

         // Assert - Should still show form without crashing
         expect(find.byType(ScriptUploadScreen), findsOneWidget);
         expect(find.text('Identity Context'), findsOneWidget);
      });
    });
  });
}
