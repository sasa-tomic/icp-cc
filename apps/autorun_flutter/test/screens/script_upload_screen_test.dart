import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/screens/script_upload_screen.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/fake_secure_keypair_repository.dart';
import '../test_helpers/test_keypair_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProfileController> createControllerWithProfile() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final identity = await TestKeypairFactory.getEd25519Keypair();
    final repository = FakeSecureKeypairRepository([identity]);
    final controller = ProfileController(
      profileRepository: repository.profileRepository,
      preferences: await SharedPreferences.getInstance(),
    );
    await controller.ensureLoaded();
    // Set the first profile as active
    if (controller.profiles.isNotEmpty) {
      await controller.setActiveProfile(controller.profiles.first.id);
    }
    return controller;
  }

  Future<Widget> createWidget({PreFilledUploadData? preFilledData}) async {
    final ProfileController controller = await createControllerWithProfile();
    return ProfileScope(
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
        expect(find.byType(TextFormField), findsNWidgets(9));
        expect(find.text('Title'), findsOneWidget);
        expect(find.text('Description'), findsOneWidget);
        expect(find.text('Category'), findsOneWidget);
        expect(find.text('Tags'), findsOneWidget);
        expect(find.text('Canister IDs'), findsOneWidget);
        expect(find.text('Compatibility Notes'), findsOneWidget);
        expect(find.text('Icon URL'), findsOneWidget);
        expect(find.text('Screenshots'), findsOneWidget);
        expect(find.text('Price (in ICP)'), findsOneWidget);
        expect(find.text('Version'), findsOneWidget);
        expect(find.text('Keypair Context'), findsOneWidget);
      });
    });

    group('with pre-filled data', () {
      testWidgets('should pre-fill title', (WidgetTester tester) async {
        // Arrange
        final preFilledData = PreFilledUploadData(
          title: 'My Awesome Script',
          luaSource: 'print("Hello World")',
        );

        // Act
        await tester
            .pumpWidget(await createWidget(preFilledData: preFilledData));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('My Awesome Script'), findsOneWidget);
      });
    });

    group('form sections', () {
      testWidgets('should display all form sections',
          (WidgetTester tester) async {
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
      testWidgets('should handle empty pre-filled data gracefully',
          (WidgetTester tester) async {
        // Arrange
        final preFilledData = PreFilledUploadData(
          title: '',
          luaSource: '',
        );

        // Act
        await tester
            .pumpWidget(await createWidget(preFilledData: preFilledData));
        await tester.pumpAndSettle();

        // Assert - Should still show form without crashing
        expect(find.byType(ScriptUploadScreen), findsOneWidget);
        expect(find.text('Keypair Context'), findsOneWidget);
      });
    });
  });
}
