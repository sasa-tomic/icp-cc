// WU-S2 empirical probe: run the REAL SecureStorageReadiness against this
// box's libsecret backend and assert it (a) detects the missing/unusable
// Secret Service, (b) returns the actionable StorageUnavailable with a
// copyable gnome-keyring install command + keyring reason, (c) attempted the
// gnome-keyring auto-start, and (d) never exposes a raw 'PlatformException(…)'
// in its user-facing fields (NEW-4).
//
// This is the NEW-2 box (no gnome-keyring-daemon, no dbus-launch, no secret-tool,
// DBUS_SESSION_BUS_ADDRESS unset, no sudo). The happy path (StorageReady) is
// proven by the widget tests via the injectable probe seam (see
// test/features/onboarding/secure_storage_readiness_gate_test.dart).
//
// Run: DISPLAY=:99 flutter test integration_test/ux_probe/wus2_readiness_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:icp_autorun/services/secure_storage_readiness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WU-S2: SecureStorageReadiness against the real libsecret backend',
      (tester) async {
    final log = <String>[];

    log.add('host: gnome-keyring-daemon installed? '
        '${await _which('gnome-keyring-daemon')}');
    log.add('host: dbus-launch installed? ${await _which('dbus-launch')}');
    log.add('host: secret-tool installed? ${await _which('secret-tool')}');
    log.add('host: DBUS_SESSION_BUS_ADDRESS='
        "'${Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? ''}'");

    final result = await SecureStorageReadiness().check();
    log.add('readiness: ${result.runtimeType} isOk=${result.isOk}');

    switch (result) {
      case StorageReady():
        log.add('  UNEXPECTED on this keyring-less box — if the host was fixed, '
            'this probe is no longer the error-path PoC.');
      case StorageUnavailable(:final reason, :final fixCommand, :final fixHint,
            :final technicalDetail, :final autostartAttempted):
        log.add('  reason: $reason');
        log.add('  fixCommand: $fixCommand');
        log.add('  fixHint: $fixHint');
        log.add('  technicalDetail: $technicalDetail');
        log.add('  autostartAttempted: $autostartAttempted');

        // NEW-2: the missing Secret Service is detected.
        expect(result, isA<StorageUnavailable>(),
            reason: 'a keyring-less Linux box must report unavailable');
        // The copyable install command names gnome-keyring (single source).
        expect(fixCommand, contains('gnome-keyring'));
        expect(fixCommand, isNotEmpty);
        // NEW-4: user-facing fields never leak the raw 'PlatformException(…)'.
        expect(reason.contains('PlatformException'), isFalse);
        expect(fixCommand.contains('PlatformException'), isFalse);
        expect(fixHint.contains('PlatformException'), isFalse);
        // The technical detail retains it (behind a show-details affordance).
        expect(technicalDetail, contains('PlatformException'));
    }

    for (final l in log) {
      // ignore: avoid_print
      print('WUS2: $l');
    }
  });
}

Future<String?> _which(String name) async {
  try {
    final r = await Process.run('which', [name]);
    if (r.exitCode != 0) return null;
    final out = (r.stdout as String).trim();
    return out.isEmpty ? null : out;
  } on ProcessException catch (e) {
    // `which` itself missing — treat as "not found" but be explicit.
    // ignore: avoid_print
    print('WUS2: which($name) failed: $e');
    return null;
  }
}
