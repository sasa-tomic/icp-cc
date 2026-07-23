// ignore_for_file: lines_longer_than_80_chars

/// Fast identity e2e suite — profile/keypair/script-CRUD/account flows on the
/// Dart VM in seconds.
///
/// These flows need a **profile** to exist (created via `ProfileController`
/// just like the integration-test `bootToScripts` helper). The substrate
/// fakes (MockClient for HTTP, in-memory FlutterSecureStorage, in-memory
/// JsonDocumentStore) provide everything the flows need — no backend, no
/// keyring, no Xvfb.
///
/// Run:
///   `just e2e-widget test/e2e_fast/fast_identity_suite_test.dart`
///   `flutter test test/e2e_fast/fast_identity_suite_test.dart --name scripts.create`
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/services/profile_repository.dart';

import '../../integration_test/e2e/mock_keyring_flows.dart';
import 'fast_harness.dart';

void main() {
  final harness = FastHarness();
  final state = MockKeyringSuiteState();
  final registry = buildMockKeyringRegistry(state);

  setUpAll(() async {
    await harness.setUp();
  });

  tearDownAll(() async {
    await harness.tearDown();
  });

  /// Reset → boot (wizard) → create profile via controller → re-boot
  /// (ScriptsScreen, wizard suppressed). This mirrors the integration-test
  /// `bootToScripts` helper but using FastHarness's substrate-aware boot.
  Future<void> bootWithProfile(WidgetTester tester) async {
    harness.resetState();
    await harness.boot(tester);

    final c = ProfileController(profileRepository: ProfileRepository());
    await tester.runAsync(() => c.createProfile(
          profileName: kMockKeyringProfileName,
          algorithm: KeyAlgorithm.ed25519,
          setAsActive: true,
        ));
    c.dispose();

    await harness.boot(tester);

    await harness.driver.waitUntil(
        tester,
        () => harness.driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
  }

  // ── Prerequisite chains ──────────────────────────────────────────────
  const prereqs = <String, List<String>>{
    'first_run.create_profile': <String>[],
    'profile.open_menu': <String>[],
    'profile.switch_via_manage_sheet': <String>['profile.open_menu'],
    'scripts.create': <String>[],
    'scripts.duplicate': <String>['scripts.create'],
    'scripts.edit': <String>['scripts.create'],
    'scripts.copy_source': <String>['scripts.create'],
    'profile.open_account_profile': <String>['profile.open_menu'],
    'keypair.generate_local': <String>[
      'profile.open_menu', 'profile.open_account_profile',
    ],
    'keypair.set_signing': <String>[
      'profile.open_menu', 'profile.open_account_profile',
      'keypair.generate_local',
    ],
    'keypair.edit_label': <String>[
      'profile.open_menu', 'profile.open_account_profile',
      'keypair.generate_local',
    ],
    'keypair.export': <String>[
      'profile.open_menu', 'profile.open_account_profile',
    ],
    'keypair.import': <String>[
      'profile.open_menu', 'profile.open_account_profile',
    ],
    'passkey.unsupported_linux': <String>[
      'profile.open_menu', 'profile.open_account_profile',
    ],
    'account.register_from_local': <String>[
      'profile.open_menu', 'profile.open_account_profile',
    ],
  };

  // ── first_run.create_profile (self-contained) ────────────────────────
  testWidgets('first_run.create_profile', (tester) async {
    harness.resetState();
    await harness.boot(tester);

    await registry.runFor('first_run.create_profile')!(tester, harness.driver);

    final scriptsShown = await harness.driver.waitUntil(
        tester,
        () => harness.driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
    expect(scriptsShown, isTrue,
        reason: 'After profile creation + remount, ScriptsScreen must render.');

    await tester.pump(const Duration(seconds: 11));
  }, timeout: const Timeout(Duration(seconds: 60)));

  // ── Standard flows ───────────────────────────────────────────────────
  for (final entry in prereqs.entries) {
    if (entry.key == 'first_run.create_profile') continue;
    final flowId = entry.key;
    final prereqIds = entry.value;

    testWidgets(flowId, (tester) async {
      await bootWithProfile(tester);

      for (final prereqId in prereqIds) {
        await registry.runFor(prereqId)!(tester, harness.driver);
        await tester.pump(const Duration(milliseconds: 500));
      }

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      await registry.runFor(flowId)!(tester, harness.driver);

      await tester.pump(const Duration(seconds: 11));
    }, timeout: const Timeout(Duration(seconds: 90)));
  }
}
