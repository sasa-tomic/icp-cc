// ROUND-3 ADDENDUM UX probe — empirical verification of WU-2/3/4 under the
// committed mock Secret Service.
//
// Round 3 marked WU-4 (inline profile switch) and WU-2/3 (Run/Publish
// SnackBarActions) as "CANNOT VERIFY on this box" because no Secret Service
// meant no profile could be created. The mock Secret Service
// (`scripts/mock_secret_service.py` + `scripts/run-with-mock-keyring.sh`)
// resolves that root cause. This probe exercises the REAL production paths
// (real Ed25519 keypair gen via FFI, real FlutterSecureStorage / libsecret,
// real ProfileRepository, real ProfileMenuWidget) to back the addendum verdicts.
//
// Run UNDER the mock:
//   scripts/run-with-mock-keyring.sh flutter test \
//       integration_test/ux_probe/r3_addendum_test.dart
//
// Hard constraint honored: `git diff apps/autorun_flutter/lib` stays EMPTY.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';

import 'r3_addendum_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // -----------------------------------------------------------------------
  // FOUNDATION: real Ed25519 profile creation end-to-end under the mock.
  //
  // This is the decisive root-cause proof: createProfile = FFI keypair gen +
  // FlutterSecureStorage.write (private key + mnemonic) + profiles.json write.
  // ALL three now succeed under the mock. We create TWO distinct profiles so
  // the WU-4 (>1 profile) branch is exercisable next.
  // -----------------------------------------------------------------------
  testWidgets('Addendum-A: create TWO real profiles end-to-end under the mock',
      (tester) async {
    await clearAddendumProfileState();

    final repo = ProfileRepository();
    // Belt-and-suspenders: ensure a clean secret store for this run.
    await tester.runAsync(() => repo.deleteAllSecureData());
    await tester.pump();

    final controller = ProfileController(profileRepository: repo);

    // Create Alice (active) and Bob, exactly as the wizard / profile-menu do.
    final List<ProfileCreationLog> created = [];
    await tester.runAsync(() async {
      final alice = await controller.createProfile(
        profileName: 'Alice (probe)',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );
      final bob = await controller.createProfile(
        profileName: 'Bob (probe)',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: false,
      );
      created.add(ProfileCreationLog(alice));
      created.add(ProfileCreationLog(bob));
    });
    await tester.pump();

    // --- Decisive assertions: both profiles persisted with retrievable keys ---
    expect(controller.profiles.length, 2,
        reason: 'Two profiles must be created under the mock.');
    expect(created.length, 2);

    for (final c in created) {
      // ignore: avoid_print
      print('ADDENDUM_A: created profile id=${c.id} '
          'name="${c.name}" keypairs=${c.keypairCount} '
          'algorithm=${c.algorithm} principal=${c.principal ?? "<none>"}');
      expect(c.keypairCount, 1, reason: 'Each profile owns one Ed25519 keypair.');
      expect(c.algorithm, KeyAlgorithm.ed25519);
      expect(c.id, isNotEmpty);
    }

    // Private keys must round-trip through libsecret under the mock (the exact
    // data loss that NEW-2 guarded against).
    final aliceKeypairId = controller.profiles.first.keypairs.first.id;
    final bobKeypairId = controller.profiles.last.keypairs.first.id;
    String? alicePk;
    String? aliceMn;
    String? bobPk;
    await tester.runAsync(() async {
      alicePk = await repo.getPrivateKey(aliceKeypairId);
      aliceMn = await repo.getMnemonic(aliceKeypairId);
      bobPk = await repo.getPrivateKey(bobKeypairId);
    });
    // ignore: avoid_print
    print('ADDENDUM_A: alice pk=${alicePk == null ? "NULL(LOST)" : "present(${alicePk!.length})"} '
        'mnemonic=${aliceMn == null ? "NULL(LOST)" : "present(${aliceMn!.length})"} '
        'bob pk=${bobPk == null ? "NULL(LOST)" : "present(${bobPk!.length})"}');
    expect(alicePk, isNotNull, reason: 'Alice private key must persist under mock.');
    expect(aliceMn, isNotNull, reason: 'Alice mnemonic must persist under mock.');
    expect(bobPk, isNotNull, reason: 'Bob private key must persist under mock.');
    expect(alicePk, isNot(equals(bobPk)),
        reason: 'The two profiles must own DISTINCT keypairs.');

    // --- Persistence: a fresh controller must reload both profiles + keys ---
    final reloaded = ProfileController(profileRepository: ProfileRepository());
    await tester.runAsync(() => reloaded.ensureLoaded());
    await tester.pump();
    expect(reloaded.profiles.length, 2,
        reason: 'loadProfiles() must reload both profiles from disk + libsecret.');
    final reloadedPk = await tester.runAsync(
        () => repo.getPrivateKey(reloaded.profiles.first.keypairs.first.id));
    expect(reloadedPk, isNotNull,
        reason: 'Private keys must survive a reload (libsecret read path).');
    // ignore: avoid_print
    print('ADDENDUM_A: PASS — 2 profiles created, persisted, reloaded with keys.');
  });

  // -----------------------------------------------------------------------
  // WU-4: inline profile switch (3 taps -> 2 taps) with REAL profiles.
  //
  // Renders the production [ProfileMenuWidget] against a controller that holds
  // two REAL profiles (created through the real secure-storage path above).
  // With >1 profile the menu inlines the profile list (2-tap switch) instead of
  // a single "Switch Profile" tile that opens a second sheet (3-tap switch).
  // -----------------------------------------------------------------------
  testWidgets('Addendum-WU4: inline profile switcher with 2 real profiles',
      (tester) async {
    await clearAddendumProfileState();

    final repo = ProfileRepository();
    await tester.runAsync(() => repo.deleteAllSecureData());
    await tester.pump();

    final controller = ProfileController(profileRepository: repo);
    await tester.runAsync(() async {
      await controller.createProfile(
        profileName: 'Alice (probe)',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );
      await controller.createProfile(
        profileName: 'Bob (probe)',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: false,
      );
    });
    await tester.pump();
    expect(controller.profiles.length, 2);

    final accountController = AccountController();
    final firstId = controller.profiles.first.id;
    final second = controller.profiles[1];
    expect(controller.activeProfileId, firstId);

    // Pump a host that opens the production ProfileMenuWidget in a bottom sheet.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    useSafeArea: true,
                    isScrollControlled: true,
                    builder: (_) => ProfileMenuWidget(
                      profileController: controller,
                      accountController: accountController,
                    ),
                  );
                },
                child: const Text('Open Menu'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap 1: open the avatar menu.
    await tester.tap(find.text('Open Menu'));
    await tester.pumpAndSettle();
    await shotAddendum(binding, '08_wu4_inline_profile_switcher', tester);

    // --- WU-4 decisive assertions (production widget, real profiles) ---
    // The inline list inlines BOTH profiles directly (no second sheet needed).
    expect(find.text('Switch profile'), findsOneWidget,
        reason: 'WU-4: the inline section header "Switch profile" must show '
            'when >1 profile exists.');
    expect(find.text('Alice (probe)'), findsWidgets,
        reason: 'Alice appears in the header + the inline list.');
    expect(find.text('Bob (probe)'), findsOneWidget,
        reason: 'Bob (inactive) appears as a tappable inline row.');
    expect(find.byIcon(Icons.check_circle), findsOneWidget,
        reason: 'Only the active profile row shows a check marker.');
    expect(find.text('Manage Profiles'), findsOneWidget,
        reason: 'The full-sheet entry stays reachable for create/rename/delete.');
    // The legacy single "Switch Profile" tile (3-tap path) is GONE for >1 profile.
    expect(find.text('Switch Profile'), findsNothing,
        reason: 'WU-4: the 3-tap "Switch Profile" tile is replaced by the '
            'inline list when >1 profile exists.');

    // Tap 2: switch to Bob directly from the inline list (2-tap switch total).
    await tester.tap(find.text('Bob (probe)'));
    await tester.pumpAndSettle();

    expect(controller.activeProfileId, second.id,
        reason: 'WU-4: a single tap on an inline row switches the active '
            'profile via the same setActiveProfile path as the old 3-tap sheet '
            '(keypair/script scoping preserved).');
    // ignore: avoid_print
    print('ADDENDUM_WU4: PASS — inline switcher renders with 2 real profiles; '
        '2-tap switch routed through setActiveProfile.');
  });
}

/// Tiny Struct carrying the fields we assert on after createProfile.
class ProfileCreationLog {
  ProfileCreationLog(Profile p)
      : id = p.id,
        name = p.name,
        keypairCount = p.keypairs.length,
        algorithm = p.keypairs.isEmpty ? null : p.keypairs.first.algorithm,
        principal = p.keypairs.isEmpty ? null : p.keypairs.first.principal;

  final String id;
  final String name;
  final int keypairCount;
  final KeyAlgorithm? algorithm;
  final String? principal;
}
