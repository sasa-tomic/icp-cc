// ignore_for_file: lines_longer_than_80_chars

/// Per-flow mock-keyring-identity e2e tests — ONE `testWidgets` per flow.
///
/// Each flow gets its own app boot so
/// `flutter test --plain-name <flow-id>` runs exactly ONE flow in isolation.
/// For full-surface coverage, use the shared-boot monolith
/// (`suite_mock_keyring_identity_test.dart` via `just e2e-desktop` PASS 2c).
///
/// Run a single flow:
///   `just e2e-one account.register_from_publish mock-keyring-identity`
///   `just e2e-one scripts.publish mock-keyring-identity`
///
/// Or directly:
///   `flutter test -d linux integration_test/e2e/flows_mock_keyring_identity_test.dart \
///     --plain-name account.register_from_publish`
///
/// **Must run under the mock Secret Service** (profiles need a keyring):
///   `scripts/run-with-mock-keyring.sh --display :99 -- flutter test ...`
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/controllers/account_controller.dart';

import 'e2e_driver.dart';
import 'flow_catalog.dart';
import 'mock_keyring_identity_flows.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final registry = buildMockKeyringIdentityRegistry();
  final tagsById = <String, Set<String>>{
    for (final s in FlowCatalog.all) s.id: s.tags,
  };

  // ── account.register_from_publish: needs a LOCAL-ONLY profile (no account)
  // so the publish gate fires the registration prompt. Setup = create local
  // profile via controller (fast, no wizard UI), then remount.
  testWidgets('account.register_from_publish', (tester) async {
    final driver = E2EDriver(surface: E2ESurface.desktop);
    await resetAppState(tester: tester);
    await driver.boot(tester);

    // Create a local-only profile via controller (skips wizard UI).
    final controller =
        ProfileController(profileRepository: ProfileRepository());
    await tester.runAsync(() => controller.createProfile(
          profileName: kIdentityProfileName,
          algorithm: KeyAlgorithm.ed25519,
          setAsActive: true,
        ));
    await driver.remount(tester);
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));

    await registry.runFor('account.register_from_publish')!(tester, driver);
  }, timeout: const Timeout(Duration(seconds: 120)),
      tags: tagsById['account.register_from_publish']?.toList());

  // ── scripts.publish: needs a REGISTERED account. Setup = create profile +
  // register account via controllers (fast, no wizard UI), then remount.
  testWidgets('scripts.publish', (tester) async {
    final driver = E2EDriver(surface: E2ESurface.desktop);
    await resetAppState(tester: tester);
    await driver.boot(tester);

    final profileController =
        ProfileController(profileRepository: ProfileRepository());
    await tester.runAsync(() => profileController.createProfile(
          profileName: kIdentityProfileName,
          algorithm: KeyAlgorithm.ed25519,
          setAsActive: true,
        ));
    final profile = profileController.activeProfile!;
    final keypair = profile.primaryKeypair;
    final username = 'pub_${DateTime.now().millisecondsSinceEpoch}';
    final accountController =
        AccountController(profileController: profileController);
    await tester.runAsync(() async {
      await accountController.registerAccount(
        keypair: keypair,
        username: username,
        displayName: kIdentityProfileName,
      );
      await profileController.updateProfileUsername(
        profileId: profile.id,
        username: username,
      );
    });
    accountController.dispose();
    await driver.remount(tester);
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));

    await registry.runFor('scripts.publish')!(tester, driver);
  }, timeout: const Timeout(Duration(seconds: 120)),
      tags: tagsById['scripts.publish']?.toList());

  // ── profile.create_via_menu_dialog: needs a LOCAL-ONLY profile (so the
  // profile menu opens with the active profile). Same setup as
  // account.register_from_publish.
  testWidgets('profile.create_via_menu_dialog', (tester) async {
    final driver = E2EDriver(surface: E2ESurface.desktop);
    await resetAppState(tester: tester);
    await driver.boot(tester);

    final controller =
        ProfileController(profileRepository: ProfileRepository());
    await tester.runAsync(() => controller.createProfile(
          profileName: kIdentityProfileName,
          algorithm: KeyAlgorithm.ed25519,
          setAsActive: true,
        ));
    await driver.remount(tester);
    await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));

    await registry.runFor('profile.create_via_menu_dialog')!(tester, driver);
  }, timeout: const Timeout(Duration(seconds: 150)),
      tags: tagsById['profile.create_via_menu_dialog']?.toList());
}
