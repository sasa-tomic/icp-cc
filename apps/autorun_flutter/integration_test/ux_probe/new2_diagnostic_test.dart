// NEW-2 diagnostic: decisively determine whether profile creation /
// FlutterSecureStorage write succeeds, throws, or silently loses data on a
// minimal Linux desktop with NO secret service (no gnome-keyring, no D-Bus).
//
// This drives the EXACT code path the wizard uses (ProfileController.
// createProfile -> ProfileRepository.persistProfiles -> FlutterSecureStorage.
// write) and inspects the on-disk result, so the verdict is unambiguous.
//
// Run: DISPLAY=:99 flutter test integration_test/ux_probe/new2_diagnostic_test.dart

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Method channel overrides so path_provider is irrelevant: we use the
  // repository's directory-override to point at a clean temp dir we control.

  testWidgets('NEW-2: FlutterSecureStorage.write on bare Linux (no keyring)', (tester) async {
    final results = <String>[];
    const storage = FlutterSecureStorage();

    // 1) Can we even WRITE a value?
    try {
      await storage.write(key: 'ux_probe_test', value: 'hello-new2');
      results.add('secureStorage.write: OK (no exception)');
    } on PlatformException catch (e) {
      results.add('secureStorage.write: PlatformException code=${e.code} '
          'message=${e.message} details=${e.details}');
    } catch (e, st) {
      results.add('secureStorage.write: THREW ${e.runtimeType}: $e\n$st');
    }

    // 2) Can we READ it back? If write silently no-op'd, read returns null.
    try {
      final readBack = await storage.read(key: 'ux_probe_test');
      results.add('secureStorage.read: value=$readBack');
      if (readBack == null) {
        results.add('  !! write() did not throw but read() is null => '
            'SILENT DATA LOSS (private keys would be unrecoverable)');
      }
    } catch (e) {
      results.add('secureStorage.read: THREW ${e.runtimeType}: $e');
    }

    // Print everything so it lands in the test log.
    for (final r in results) {
      // ignore: avoid_print
      print('NEW2_SECURE_STORAGE: $r');
    }

    // We don't hard-fail here; the printed verdict is the artifact. But we do
    // assert *something* happened so the test is non-degenerate.
    expect(results, isNotEmpty);
  });

  testWidgets('NEW-2: ProfileController.createProfile end-to-end', (tester) async {
    final tmpDir = await Directory.systemTemp.createTemp('ux_probe_new2_');
    final repo = ProfileRepository(overrideDirectory: tmpDir);
    final controller = ProfileController(
      marketplaceService: MarketplaceOpenApiService(),
      profileRepository: repo,
    );

    final log = <String>[];
    Profile? created;
    try {
      created = await controller.createProfile(
        profileName: 'Probe User',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );
      log.add('createProfile: RETURNED profile id=${created.id} '
          'keypairs=${created.keypairs.length}');
    } catch (e, st) {
      log.add('createProfile: THREW ${e.runtimeType}: $e');
      log.add('stack: $st');
    }

    // Inspect on-disk state.
    final file = File('${tmpDir.path}/profiles.json');
    if (await file.exists()) {
      final content = await file.readAsString();
      final hasProfile = content.contains('"id"');
      log.add('profiles.json EXISTS, length=${content.length}, '
          'hasProfile=$hasProfile');
      log.add('profiles.json head: ${content.length > 300 ? content.substring(0, 300) : content}');
      // CRITICAL: does profiles.json leak the PRIVATE key (secure-storage
      // silently fell back to plaintext) or correctly omit it?
      final leaksPrivate = content.contains('privateKey') ||
          content.contains('private_key') ||
          content.contains('"mnemonic"');
      log.add('profiles.json leaks private/mnemonic data: $leaksPrivate');
    } else {
      log.add('profiles.json DOES NOT EXIST (persist skipped/rolled back)');
    }

    // Try to read the private key back from secure storage the same way the
    // app would at load time.
    if (created != null) {
      final keypairId = created.keypairs.first.id;
      try {
        final pk = await repo.getPrivateKey(keypairId);
        log.add('getPrivateKey($keypairId): '
            '${pk == null ? "NULL (private key LOST — unrecoverable)" : "present (${pk.length} chars)"}');
      } catch (e) {
        log.add('getPrivateKey THREW ${e.runtimeType}: $e');
      }
    }

    for (final l in log) {
      // ignore: avoid_print
      print('NEW2_CREATE_PROFILE: $l');
    }
    expect(log, isNotEmpty);
    await tmpDir.delete(recursive: true);
  });
}
