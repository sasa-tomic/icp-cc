import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/screens/import_keys_dialog.dart';
import 'package:icp_autorun/utils/profile_errors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/fake_secure_keypair_repository.dart';

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

  // TD-4: the dialog branches on TYPE, never on an English substring. Each
  // typed exception maps to a single, stable user-visible message.
  group('ImportKeysDialog typed-exception copy (TD-4)', () {
    testWidgets(
        'ProfileAlreadyExistsException shows the already-exists message',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      // Inject a ProfileAlreadyExistsException directly — this test validates
      // the dialog's TYPE -> message mapping (the TD-4 point), not the crypto
      // path (covered by the wrong-password / invalid-format widget tests).
      final controller = ProfileController(
        profileRepository: _TypedThrowingProfileRepository(
          ProfileAlreadyExistsException('profile_collision'),
        ),
      );
      await controller.ensureLoaded();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => ImportKeysDialog(
                      profileController: controller,
                    ),
                  ),
                  child: const Text('Show Import Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'any backup blob');
      await tester.enterText(textFields.at(1), 'testpassword123');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // UX-H5 Path 4: the message must NOT suggest destroying the existing
      // profile. The new copy is honest + non-destructive (points to the
      // Manage Keypairs UI instead).
      expect(
        find.textContaining('This profile is already on this device'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Manage Keypairs'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Delete it first'),
        findsNothing,
      );
    });

    testWidgets('an unknown cause shows the generic Import failed message',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      // A repository that injects an arbitrary (non-typed) failure — proves the
      // dialog's final catch arm surfaces the error honestly instead of
      // mis-routing it to a typed message.
      final controller = ProfileController(
        profileRepository: _TypedThrowingProfileRepository(
          Exception('unexpected storage failure'),
        ),
      );
      await controller.ensureLoaded();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => ImportKeysDialog(
                      profileController: controller,
                    ),
                  ),
                  child: const Text('Show Import Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Import Dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'any backup blob');
      await tester.enterText(textFields.at(1), 'testpassword123');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // Unknown-cause fallback — must NOT be the decryption/format/exists copy.
      expect(find.textContaining('Import failed:'), findsOneWidget);
      expect(
        find.text('Invalid password or corrupted backup'),
        findsNothing,
      );
    });
  });
}

/// Error-injection [FakeProfileRepository] that throws a fixed exception from
/// `importProfileBackup`, so the dialog's per-type catch arms can be exercised
/// directly (validating TYPE -> message mapping) without the slow crypto path.
/// This is a focused test stub (one overridden method), not a duplicate
/// repository implementation.
class _TypedThrowingProfileRepository extends FakeProfileRepository {
  _TypedThrowingProfileRepository(this.error) : super(const []);

  final Object error;

  @override
  Future<Profile> importProfileBackup(
    String encryptedJson,
    String password,
  ) async {
    throw error;
  }
}
