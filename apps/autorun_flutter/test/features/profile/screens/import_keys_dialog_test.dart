import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/screens/import_keys_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_helpers/fake_secure_keypair_repository.dart';

void main() {
  group('ImportKeysDialog', () {
    late ProfileController profileController;
    late String exportedBackup;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      final fakeProfileRepository = FakeProfileRepository([]);
      await fakeProfileRepository.persistProfiles([
        await FakeProfileRepository.createTestProfile(name: 'Export Profile'),
      ]);

      final profiles = await fakeProfileRepository.loadProfiles();
      final profileId = profiles.first.id;

      exportedBackup = await fakeProfileRepository.exportProfileBackup(
        profileId,
        'testpassword123',
      );

      final emptyRepository = FakeProfileRepository([]);
      profileController = ProfileController(
        profileRepository: emptyRepository,
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
                    builder: (context) => ImportKeysDialog(
                      profileController: profileController,
                    ),
                  );
                },
                child: const Text('Show Import Dialog'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('displays encrypted backup field', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Import Keys'), findsOneWidget);
      expect(find.text('Encrypted Backup'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('displays cancel and import buttons', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Import Keys'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Import Keys'), findsNothing);
    });

    testWidgets('validates empty encrypted backup', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(find.text('Please paste the encrypted backup'), findsOneWidget);
    });

    testWidgets('validates empty password', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'some encrypted text');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter the password'), findsOneWidget);
    });

    testWidgets('shows error for wrong password', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), exportedBackup);
      await tester.enterText(textFields.at(1), 'wrongpassword');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid password or corrupted backup'), findsOneWidget);
    });

    testWidgets('shows error for invalid backup format', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'not valid json');
      await tester.enterText(textFields.at(1), 'testpassword123');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid backup format'), findsOneWidget);
    });

    testWidgets('successful import shows success dialog', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), exportedBackup);
      await tester.enterText(textFields.at(1), 'testpassword123');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(find.text('Import Complete'), findsOneWidget);
      expect(find.textContaining('Successfully imported'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('done button closes success dialog', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), exportedBackup);
      await tester.enterText(textFields.at(1), 'testpassword123');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(find.text('Import Complete'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Import Complete'), findsNothing);
    });
  });
}
