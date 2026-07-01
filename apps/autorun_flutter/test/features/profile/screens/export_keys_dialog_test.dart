import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/screens/export_keys_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/fake_secure_keypair_repository.dart';
import '../../../shared/test_keypair_factory.dart';

void main() {
  group('ExportKeysDialog', () {
    late ProfileController profileController;
    late String profileId;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await TestKeypairFactory.getEd25519Keypair();

      final fakeProfileRepository = FakeProfileRepository([]);
      await fakeProfileRepository.persistProfiles([
        await FakeProfileRepository.createTestProfile(name: 'Test Profile'),
      ]);

      final profiles = await fakeProfileRepository.loadProfiles();
      profileId = profiles.first.id;

      profileController = ProfileController(
        profileRepository: fakeProfileRepository,
      );
      await profileController.ensureLoaded();
    });

    Widget createTestApp() {
      return MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => ExportKeysDialog(
                      profileId: profileId,
                      profileController: profileController,
                    ),
                  );
                },
                child: const Text('Show Export Dialog'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('displays password fields', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Export Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Export Keys'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
    });

    testWidgets('displays cancel and export buttons', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Export Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Export Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Export Keys'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Export Keys'), findsNothing);
    });

    testWidgets('validates empty password', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Export Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a password'), findsOneWidget);
    });

    testWidgets('validates password length', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Export Dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'short');
      await tester.enterText(textFields.at(1), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(
          find.text('Password must be at least 8 characters'), findsOneWidget);
    });

    testWidgets('validates password match', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Export Dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'password1');
      await tester.enterText(textFields.at(1), 'password2');
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('successful export shows success dialog', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Export Dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'testpassword123');
      await tester.enterText(textFields.at(1), 'testpassword123');
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.text('Export Complete'), findsOneWidget);
      expect(find.text('Copy to Clipboard'), findsOneWidget);
    });
  });
}
