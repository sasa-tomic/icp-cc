// ignore_for_file: lines_longer_than_80_chars

/// Per-flow mock-keyring e2e tests — ONE `testWidgets` per flow.
///
/// Each flow gets its own app boot so
/// `flutter test --plain-name <flow-id>` runs exactly ONE flow in isolation.
/// For full-surface coverage, use the shared-boot monolith
/// (`suite_mock_keyring_test.dart` via `just e2e-desktop` PASS 2).
///
/// Run a single flow:
///   `just e2e-one keypair.export mock-keyring`
///   `just e2e-one vault.setup mock-keyring`
///
/// Or directly:
///   `flutter test -d linux integration_test/e2e/flows_mock_keyring_test.dart \
///     --plain-name keypair.export`
///
/// **Must run under the mock Secret Service** (profiles need a keyring):
///   `scripts/run-with-mock-keyring.sh --display :99 -- flutter test ...`
@TestOn('linux')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/account_profile_screen.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/screens/vault_password_setup_screen.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';

import 'e2e_driver.dart';
import 'flow_catalog.dart';
import 'mock_keyring_flows.dart';
import 'suite_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // FlowSpec tags by id — inject into testWidgets so `flutter test --tags smoke`
  // / `--exclude-tags desktop-only` work natively.
  final tagsById = <String, Set<String>>{
    for (final s in FlowCatalog.all) s.id: s.tags,
  };

  /// testWidgets wrapper that auto-injects FlowSpec tags by flow id.
  void ftw(String flowId, Future<void> Function(WidgetTester) body,
      {int timeoutSeconds = 120}) {
    testWidgets(
      flowId,
      body,
      timeout: Timeout(Duration(seconds: timeoutSeconds)),
      tags: tagsById[flowId]?.toList(),
    );  }

  // ── Setup helpers ────────────────────────────────────────────────────

  /// resetAppState → boot → create profile via controller → remount →
  /// ScriptsScreen.
  ///
  /// This is the "we have a local profile and we're on the Scripts tab" state
  /// that most flows start from.
  Future<void> bootToScripts(WidgetTester tester, E2EDriver d) async {
    await resetAppState(tester: tester);
    await d.boot(tester);
    final c = ProfileController(profileRepository: ProfileRepository());
    await tester.runAsync(() => c.createProfile(
          profileName: kMockKeyringProfileName,
          algorithm: KeyAlgorithm.ed25519,
          setAsActive: true,
        ));
    await d.remount(tester);
    await d.waitUntil(
        tester, () => d.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
  }

  /// From ScriptsScreen, tap the ProfileAvatarButton to open the profile
  /// dropdown menu.
  Future<void> openProfileMenu(WidgetTester tester, E2EDriver d) async {
    await tester.tap(find.byType(ProfileAvatarButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// bootToScripts → openProfileMenu → tap "My Account" → wait for
  /// AccountProfileScreen.
  Future<void> toAccountProfile(WidgetTester tester, E2EDriver d) async {
    await bootToScripts(tester, d);
    await openProfileMenu(tester, d);
    await tester.tap(find.text('My Account'));
    await d.waitUntil(
        tester, () => d.present(find.byType(AccountProfileScreen), tester),
        timeout: const Duration(seconds: 5));
  }

  /// bootToScripts then register an account directly via the app's
  /// ProfileScope controller. Ends at ScriptsScreen with a registered account.
  Future<void> toRegisteredScripts(WidgetTester tester, E2EDriver d) async {
    await bootToScripts(tester, d);
    final controller = ProfileScope.of(
      tester.element(find.byType(ProfileScope)),
      listen: false,
    );
    final profile = controller.activeProfile!;
    final keypair = profile.primaryKeypair;
    final username = 'e2e_${DateTime.now().millisecondsSinceEpoch}';
    final ac = AccountController(profileController: controller);
    await tester.runAsync(() async {
      await ac.registerAccount(
        keypair: keypair,
        username: username,
        displayName: kMockKeyringProfileName,
      );
      await controller.updateProfileUsername(
        profileId: profile.id,
        username: username,
      );
    });
    ac.dispose();
    await d.remount(tester);
    await d.waitUntil(
        tester, () => d.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
  }

  /// toRegisteredScripts → openProfileMenu → vault.route_from_menu →
  /// VaultPasswordSetupScreen on stage.
  Future<void> toVaultSetup(WidgetTester tester, E2EDriver d) async {
    await toRegisteredScripts(tester, d);
    await openProfileMenu(tester, d);
    await tester.tap(find.text('Vault'));
    await d.waitUntil(
        tester,
        () => d.present(find.byType(VaultPasswordSetupScreen), tester),
        timeout: const Duration(seconds: 15));
  }

  /// toRegisteredScripts → vault.setup (full setup via UI). Ends with vault
  /// encrypted + recovery code captured. Caller must pass the state object.
  Future<void> toVaultReady(
      WidgetTester tester, E2EDriver d, MockKeyringSuiteState state) async {
    await toVaultSetup(tester, d);
    final registry = buildMockKeyringRegistry(state);
    await registry.runFor('vault.setup')!(tester, d);
  }

  // ── SPECIAL: first_run.create_profile (self-booting) ─────────────────
  // This flow boots the app itself, creates a profile via the controller,
  // then remounts. We verify the wizard suppresses after profile creation.
  ftw('first_run.create_profile', (tester) async {
    final driver = E2EDriver(surface: E2ESurface.desktop);
    await resetAppState(tester: tester);
    await driver.boot(tester);

    // Wizard must show on clean store.
    final wizardVisible = await driver.waitUntil(
        tester, () => driver.present(find.byType(UnifiedSetupWizard), tester),
        timeout: const Duration(seconds: 20));
    expect(wizardVisible, isTrue,
        reason: 'Clean store must show the setup wizard.');

    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await registry.runFor('first_run.create_profile')!(tester, driver);

    // After remount, wizard must be suppressed.
    final scriptsShown = await driver.waitUntil(
        tester, () => driver.present(find.byType(ScriptsScreen), tester),
        timeout: const Duration(seconds: 15));
    expect(scriptsShown, isTrue,
        reason: 'After profile creation + remount, ScriptsScreen must render.');
  });

  // ── Group: ScriptsScreen entry ───────────────────────────────────────

  ftw('profile.switch_inline', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await bootToScripts(tester, d);
    await registry.runFor('profile.switch_inline')!(tester, d);
  }, timeoutSeconds: 90);

  ftw('profile.open_menu', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await bootToScripts(tester, d);
    await registry.runFor('profile.open_menu')!(tester, d);
  }, timeoutSeconds: 90);

  ftw('scripts.create', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await bootToScripts(tester, d);
    await registry.runFor('scripts.create')!(tester, d);
  }, timeoutSeconds: 90);

  // ── Group: profile menu open entry ───────────────────────────────────

  ftw('profile.switch_via_manage_sheet', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await bootToScripts(tester, d);
    await registry.runFor('profile.open_menu')!(tester, d);
    await registry.runFor('profile.switch_via_manage_sheet')!(tester, d);
  }, timeoutSeconds: 90);

  ftw('profile.open_account_profile', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await bootToScripts(tester, d);
    await registry.runFor('profile.open_menu')!(tester, d);
    await registry.runFor('profile.open_account_profile')!(tester, d);
  }, timeoutSeconds: 90);

  // ── Group: ScriptsScreen with script entry ───────────────────────────

  Future<void> runWithCreatedScript(
      WidgetTester tester, String flowId) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await bootToScripts(tester, d);
    await registry.runFor('scripts.create')!(tester, d);
    await registry.runFor(flowId)!(tester, d);
  }

  ftw('scripts.duplicate', (tester) async {
    await runWithCreatedScript(tester, 'scripts.duplicate');
  });

  ftw('scripts.edit', (tester) async {
    await runWithCreatedScript(tester, 'scripts.edit');
  });

  ftw('scripts.copy_source', (tester) async {
    await runWithCreatedScript(tester, 'scripts.copy_source');
  });

  // ── Group: AccountProfileScreen (local) entry ────────────────────────

  Future<void> runAtAccountProfile(WidgetTester tester, String flowId) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toAccountProfile(tester, d);
    await registry.runFor(flowId)!(tester, d);
  }

  ftw('keypair.generate_local', (tester) async {
    await runAtAccountProfile(tester, 'keypair.generate_local');
  });

  ftw('keypair.set_signing', (tester) async {
    // Needs ≥2 keys: generate_local runs first.
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toAccountProfile(tester, d);
    await registry.runFor('keypair.generate_local')!(tester, d);
    await registry.runFor('keypair.set_signing')!(tester, d);
  });

  ftw('keypair.edit_label', (tester) async {
    await runAtAccountProfile(tester, 'keypair.edit_label');
  });

  ftw('keypair.export', (tester) async {
    await runAtAccountProfile(tester, 'keypair.export');
  });

  ftw('keypair.import', (tester) async {
    await runAtAccountProfile(tester, 'keypair.import');
  });

  ftw('passkey.unsupported_linux', (tester) async {
    await runAtAccountProfile(tester, 'passkey.unsupported_linux');
  });

  ftw('account.register_from_local', (tester) async {
    await runAtAccountProfile(tester, 'account.register_from_local');
  });

  // ── Group: registered account entry ──────────────────────────────────

  ftw('account.refresh', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toAccountProfile(tester, d);
    await registry.runFor('account.register_from_local')!(tester, d);
    // account.refresh checks for refresh icon on AccountProfileScreen.
    await registry.runFor('account.refresh')!(tester, d);
  });

  ftw('account.edit_profile', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toRegisteredScripts(tester, d);
    // account.edit_profile opens ProfileAvatarButton → My Account itself.
    await registry.runFor('account.edit_profile')!(tester, d);
  });

  ftw('keypair.generate_registered', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toRegisteredScripts(tester, d);
    // keypair.generate_registered opens menu → My Account itself.
    await registry.runFor('keypair.generate_registered')!(tester, d);
  });

  ftw('keypair.delete_registered', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toRegisteredScripts(tester, d);
    // Needs ≥2 active keys: generate_registered runs first.
    await registry.runFor('keypair.generate_registered')!(tester, d);
    await registry.runFor('keypair.delete_registered')!(tester, d);
  }, timeoutSeconds: 150);

  // ── Group: vault flows ───────────────────────────────────────────────

  ftw('vault.route_from_menu', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toRegisteredScripts(tester, d);
    await openProfileMenu(tester, d);
    await registry.runFor('vault.route_from_menu')!(tester, d);
  });

  ftw('vault.setup', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toVaultSetup(tester, d);
    await registry.runFor('vault.setup')!(tester, d);
  }, timeoutSeconds: 150);

  ftw('vault.unlock', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toVaultReady(tester, d, state);
    await registry.runFor('vault.unlock')!(tester, d);
  }, timeoutSeconds: 150);

  ftw('vault.unlock_wrong_password', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toVaultReady(tester, d, state);
    await registry.runFor('vault.unlock_wrong_password')!(tester, d);
  }, timeoutSeconds: 150);

  ftw('vault.use_recovery_code', (tester) async {
    final d = E2EDriver(surface: E2ESurface.desktop);
    final state = MockKeyringSuiteState();
    final registry = buildMockKeyringRegistry(state);
    await toVaultReady(tester, d, state);
    await registry.runFor('vault.use_recovery_code')!(tester, d);
  }, timeoutSeconds: 150);
}
