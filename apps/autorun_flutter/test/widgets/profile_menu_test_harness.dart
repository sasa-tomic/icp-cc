import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/fake_secure_keypair_repository.dart';

/// Shared test doubles for [ProfileMenuWidget] tests.
///
/// Every profile-menu widget test needs the same [PasskeyService] and
/// [AccountController] doubles, the same [Profile] mocktail fallback, and the
/// same bottom-sheet pump host. Centralising them here keeps the individual
/// test files focused on behaviour instead of boilerplate (see test/shared
/// AGENTS.md: never duplicate test helper code).

class MockPasskeyService extends Mock implements PasskeyService {}

class MockAccountController extends Mock implements AccountController {}

/// mocktail fallback for any stubbed [AccountController] method that takes a
/// [Profile] (e.g. `getAccountForProfile`).
class FakeProfile extends Fake implements Profile {}

/// Registers the [Profile] fallback required by [MockAccountController] stubs.
/// Call once per test file from `setUpAll`.
void registerProfileMenuFallbacks() {
  registerFallbackValue(FakeProfile());
}

/// Builds a [ProfileController] backed by an in-memory repository seeded with
/// [keypairs], with the first profile (if any) activated.
///
/// Mirrors the setUp that was copy-pasted across every profile_menu test.
Future<ProfileController> buildProfileController({
  List<ProfileKeypair> keypairs = const [],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final repository = FakeSecureKeypairRepository(keypairs);
  final controller =
      ProfileController(profileRepository: repository.profileRepository);
  await controller.ensureLoaded();
  if (controller.profiles.isNotEmpty) {
    await controller.setActiveProfile(controller.profiles.first.id);
  }
  return controller;
}

/// A deterministic account for stubbing [AccountController.getAccountForProfile].
Account buildTestAccount({String username = 'testuser'}) => Account(
      id: 'account-123',
      username: username,
      displayName: 'Test User',
      publicKeys: [],
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

/// Pumps a host that opens [ProfileMenuWidget] in a bottom sheet, then opens it
/// by tapping the 'Open Menu' button. Leaves the menu visible and settled.
///
/// Named `…Host` to avoid clashing with the local `pumpProfileMenu` wrappers
/// several tests define to add per-test stubbing before opening the menu.
Future<void> pumpProfileMenuHost(
  WidgetTester tester, {
  required ProfileController profileController,
  required AccountController accountController,
  required PasskeyService passkeyService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            return ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  isScrollControlled: true,
                  builder: (_) => ProfileMenuWidget(
                    profileController: profileController,
                    accountController: accountController,
                    passkeyService: passkeyService,
                  ),
                );
              },
              child: const Text('Open Menu'),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open Menu'));
  await tester.pumpAndSettle();
}
