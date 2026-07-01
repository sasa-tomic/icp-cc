import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';

import 'account_profile_test_helpers.dart';
import '../../shared/test_keypair_factory.dart';

void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    AccountProfileScreenTestHelper.registerFallbackValues();
  });

  group('AccountProfileScreen - Profile Editing', () {
    late MockAccountController accountController;
    late MockProfileController profileController;
    late Account account;
    late Profile profile;
    late ProfileKeypair keypair;

    setUp(() async {
      accountController = MockAccountController();
      profileController = MockProfileController();

      // Create test keypair
      keypair = await TestKeypairFactory.getEd25519Keypair();

      // Create test account
      account = AccountProfileScreenTestHelper.createTestAccount(
        username: 'testuser',
        displayName: 'Test User',
        publicKeys: [
          AccountProfileScreenTestHelper.createTestAccountPublicKey(
            id: 'key-1',
            publicKey: keypair.publicKey,
            icPrincipal: keypair.principal ?? 'test-principal',
            label: 'Primary Key',
          ),
        ],
        contactEmail: 'test@example.com',
        contactTelegram: '@testuser',
      );

      // Create test profile
      profile = Profile(
        id: 'profile-1',
        name: 'Test Profile',
        keypairs: [keypair],
        username: 'testuser',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        updatedAt: DateTime.now(),
      );

      // Setup default mock responses
      when(() => accountController.refreshAccount(any()))
          .thenAnswer((_) async => account);
      when(() => profileController.findById(any())).thenReturn(profile);
    });

    testWidgets('displays account header with username', (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Username appears in header as @testuser
      expect(find.textContaining('@testuser'), findsWidgets);
    });

    testWidgets('shows display name field in profile section', (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.text('Display Name *'), findsOneWidget);
    });

    testWidgets('shows primary fields (display name and bio) by default',
        (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Primary fields should be visible by default
      expect(find.text('Display Name *'), findsOneWidget);
      expect(find.text('Bio'), findsOneWidget);
    });

    testWidgets('contact info fields are hidden in collapsed section',
        (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Contact fields should NOT be visible when collapsed
      expect(find.text('Email'), findsNothing);
      expect(find.text('Telegram'), findsNothing);
      expect(find.text('Twitter/X'), findsNothing);
      expect(find.text('Discord'), findsNothing);
      expect(find.text('Website'), findsNothing);
    });

    testWidgets('contact info section is expandable', (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Find and tap the "Contact Info" expansion tile
      expect(find.text('Contact Info'), findsOneWidget);

      // Tap to expand
      await tester.tap(find.text('Contact Info'));
      await tester.pumpAndSettle();

      // Now contact fields should be visible
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Telegram'), findsOneWidget);
      expect(find.text('Twitter/X'), findsOneWidget);
      expect(find.text('Discord'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
    });

    testWidgets('contact fields show pre-filled values when expanded',
        (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Expand contact info section
      await tester.tap(find.text('Contact Info'));
      await tester.pumpAndSettle();

      // Find the email field and verify its value
      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      TextField? emailField;
      for (final tf in textFields) {
        if (tf.decoration?.labelText == 'Email') {
          emailField = tf;
          break;
        }
      }

      expect(emailField, isNotNull);
      expect(emailField!.controller?.text, equals('test@example.com'));
    });

    testWidgets('shows pre-filled display name from account', (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Verify display name field has correct initial value
      // Find the TextField with "Display Name *" label
      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      TextField? displayNameField;
      for (final tf in textFields) {
        final decoration = tf.decoration;
        if (decoration?.labelText == 'Display Name *') {
          displayNameField = tf;
          break;
        }
      }
      expect(displayNameField, isNotNull);
      expect(displayNameField!.controller?.text, equals('Test User'));
    });

    testWidgets('empty display name shows validation error', (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Find and clear the display name field
      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      TextField? displayNameField;
      for (final tf in textFields) {
        final decoration = tf.decoration;
        if (decoration?.labelText == 'Display Name *') {
          displayNameField = tf;
          break;
        }
      }

      // Enter empty text
      await tester.enterText(find.byWidget(displayNameField!), '');
      await tester.pump();

      // Scroll to Save Changes button and tap it
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Should show error snackbar
      expect(find.text('Display name is required'), findsOneWidget);
    });

    testWidgets('display name update with valid data succeeds', (tester) async {
      // Setup mock for successful update
      when(() => accountController.updateProfile(
            username: any(named: 'username'),
            signingKeypair: any(named: 'signingKeypair'),
            displayName: any(named: 'displayName'),
            contactEmail: any(named: 'contactEmail'),
            contactTelegram: any(named: 'contactTelegram'),
            contactTwitter: any(named: 'contactTwitter'),
            contactDiscord: any(named: 'contactDiscord'),
            websiteUrl: any(named: 'websiteUrl'),
            bio: any(named: 'bio'),
          )).thenAnswer((_) async => account.copyWith(
            displayName: 'Updated Name',
          ));

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Find display name field and update it
      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      TextField? displayNameField;
      for (final tf in textFields) {
        final decoration = tf.decoration;
        if (decoration?.labelText == 'Display Name *') {
          displayNameField = tf;
          break;
        }
      }

      await tester.enterText(find.byWidget(displayNameField!), 'Updated Name');
      await tester.pump();

      // Scroll to and tap save button
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Should show success snackbar
      expect(find.text('Profile updated successfully'), findsOneWidget);
    });

    testWidgets('network error handling on profile update', (tester) async {
      when(() => accountController.updateProfile(
            username: any(named: 'username'),
            signingKeypair: any(named: 'signingKeypair'),
            displayName: any(named: 'displayName'),
            contactEmail: any(named: 'contactEmail'),
            contactTelegram: any(named: 'contactTelegram'),
            contactTwitter: any(named: 'contactTwitter'),
            contactDiscord: any(named: 'contactDiscord'),
            websiteUrl: any(named: 'websiteUrl'),
            bio: any(named: 'bio'),
          )).thenThrow(Exception('Network error'));

      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Should show error snackbar
      expect(find.textContaining('Failed to update profile'), findsOneWidget);
    });

    testWidgets('shows creation date in header', (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      expect(find.textContaining('Created'), findsOneWidget);
    });

    testWidgets('bio field allows multi-line input', (tester) async {
      await AccountProfileScreenTestHelper.pumpAccountProfileScreen(
        tester,
        account: account,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      );

      // Find bio field - TextField with maxLines: 3
      final bioTextField =
          tester.widgetList<TextField>(find.byType(TextField)).firstWhere(
                (tf) => tf.maxLines == 3,
                orElse: () => throw StateError('Bio field not found'),
              );

      expect(bioTextField.maxLines, equals(3));
    });
  });
}
