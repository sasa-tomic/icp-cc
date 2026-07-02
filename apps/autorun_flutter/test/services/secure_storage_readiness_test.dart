// WU-S2 unit tests for SecureStorageReadiness.
//
// The readiness probe is a platform-AVAILABILITY check (not cryptography), so
// we inject a fake [SecureStorageProbe] / [ProcessRunner] / [EnvSetter] to
// simulate "keyring down" — no real keys are involved (legit seam per the
// AGENTS.md test rules).
//
// Written failing-first against the public contract of
// lib/services/secure_storage_readiness.dart.

import 'dart:io' show ProcessResult;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/secure_storage_readiness.dart';

/// A controllable probe for tests. Each behavior is a closure the test sets.
class _FakeProbe implements SecureStorageProbe {
  _FakeProbe({
    this.writeBehavior,
    this.readValue,
  });

  /// Throws or completes when `write` is called.
  Future<void> Function(String key, String value)? writeBehavior;

  /// Value returned by `read` (or a throwing behavior via [_readThrows]).
  String? Function(String key)? readValue;

  final List<String> deletedKeys = <String>[];

  @override
  Future<void> write({required String key, required String value}) async {
    final b = writeBehavior;
    if (b != null) {
      await b(key, value); // propagates throws; otherwise fall through + store
    }
    _written[key] = value;
  }

  @override
  Future<String?> read({required String key}) {
    final r = readValue;
    if (r == null) {
      return Future<String?>.value(_written[key]);
    }
    return Future<String?>.value(r(key));
  }

  @override
  Future<void> delete({required String key}) {
    deletedKeys.add(key);
    _written.remove(key);
    return Future<void>.value();
  }

  final Map<String, String> _written = <String, String>{};
}

ProcessResult _ok(String stdout, [String stderr = '']) =>
    ProcessResult(1, 0, stdout, stderr);
ProcessResult _fail(int code, String stderr) =>
    ProcessResult(1, code, '', stderr);

PlatformException _libsecretException() => PlatformException(
      code: 'Libsecret error',
      message: 'Failed to unlock the keyring',
      details: null,
    );

void main() {
  group('SecureStorageReadiness.check', () {
    test('returns StorageReady when the probe round-trips cleanly', () async {
      final probe = _FakeProbe();
      final readiness = SecureStorageReadiness(probe: probe);

      final result = await readiness.check();

      expect(result, isA<StorageReady>());
      expect(result.isOk, isTrue);
    });

    test('returns StorageUnavailable when write throws PlatformException',
        () async {
      // Simulate the exact NEW-2 failure: every write throws the libsecret
      // PlatformException seen on a keyring-less Linux box.
      final probe = _FakeProbe(
        writeBehavior: (_, __) =>
            Future<void>.error(_libsecretException()),
      );
      // Force the orchestrator down the Linux path so we exercise the
      // PlatformException mapping (which is Linux-agnostic in _probeOnce, but
      // we also want to assert autostart isn't triggered here).
      final readiness = SecureStorageReadiness(
        probe: probe,
        autostart: _NoopAutostart(),
      );

      final result = await readiness.check();

      expect(result, isA<StorageUnavailable>());
      final u = result as StorageUnavailable;
      expect(u.isOk, isFalse);
      expect(u.reason, "Couldn't access the system keyring");
      expect(u.fixCommand, isNotEmpty);
      expect(u.fixCommand, contains('gnome-keyring'));
      expect(u.technicalDetail, contains('Libsecret error'));
    });

    test(
        'a raw PlatformException string never reaches the user-facing fields',
        () async {
      final probe = _FakeProbe(
        writeBehavior: (_, __) =>
            Future<void>.error(_libsecretException()),
      );
      final readiness = SecureStorageReadiness(
        probe: probe,
        autostart: _NoopAutostart(),
      );

      final u = (await readiness.check()) as StorageUnavailable;

      // NEW-4: the user must never see "PlatformException(…)" verbatim.
      expect(u.reason.contains('PlatformException'), isFalse);
      expect(u.explanation.contains('PlatformException'), isFalse);
      expect(u.fixCommand.contains('PlatformException'), isFalse);
      expect(u.fixHint.contains('PlatformException'), isFalse);
      // Technical detail retains it, but only behind a "show details" affordance.
      expect(u.technicalDetail, contains('PlatformException'));
    });

    test('detects silent data loss (write ok, read null) and refuses', () async {
      // write succeeds but read returns null → private key would be lost.
      final probe = _FakeProbe(
        readValue: (_) => null,
      );
      final readiness = SecureStorageReadiness(
        probe: probe,
        autostart: _NoopAutostart(),
      );

      final u = (await readiness.check()) as StorageUnavailable;

      expect(u.reason, 'Secure storage is not retaining data');
      expect(u.isOk, isFalse);
    });
  });

  group('SecureStorageReadiness.check — Linux autostart', () {
    test(
        'returns StorageReady when the first probe fails but autostart recovers',
        () async {
      var callCount = 0;
      final probe = _FakeProbe(
        writeBehavior: (_, __) {
          callCount += 1;
          if (callCount == 1) {
            // First probe (before autostart) throws.
            return Future<void>.error(_libsecretException());
          }
          // After autostart, the probe succeeds.
          return Future<void>.value();
        },
      );

      final readiness = SecureStorageReadiness(
        probe: probe,
        // Real autostart with a fully faked process/env surface: pretend
        // gnome-keyring + dbus-launch are installed and start cleanly.
        autostart: LinuxSecretServiceAutostart(
          runner: (executable, arguments, {bool runInShell = false}) async {
            if (executable == 'which') {
              final name = arguments.first;
              if (name == 'gnome-keyring-daemon') {
                return _ok('/usr/bin/gnome-keyring-daemon');
              }
              if (name == 'dbus-launch') {
                return _ok('/usr/bin/dbus-launch');
              }
              return _fail(1, 'not found');
            }
            if (executable == '/usr/bin/dbus-launch') {
              return _ok(
                "DBUS_SESSION_BUS_ADDRESS='unix:abstract=/tmp/dbus-FAKE,guid=deadbeef';\n"
                "export DBUS_SESSION_BUS_ADDRESS;\n",
              );
            }
            if (executable == '/usr/bin/gnome-keyring-daemon') {
              return _ok('OK');
            }
            return _fail(1, 'unexpected $executable');
          },
          // Pretend setenv succeeds.
          envSetter: (_, __) => true,
        ),
      );

      final result = await readiness.check();

      expect(result, isA<StorageReady>(),
          reason: 'autostart should make the retry probe succeed');
      expect(callCount, 2, reason: 'probe runs once before + once after autostart');
    });

    test(
        'returns StorageUnavailable when gnome-keyring-daemon is not installed',
        () async {
      final probe = _FakeProbe(
        writeBehavior: (_, __) =>
            Future<void>.error(_libsecretException()),
      );
      final readiness = SecureStorageReadiness(
        probe: probe,
        autostart: LinuxSecretServiceAutostart(
          runner: (executable, arguments, {bool runInShell = false}) async {
            // `which gnome-keyring-daemon` → not found.
            return _fail(1, 'no $executable in PATH');
          },
          envSetter: (_, __) => true,
        ),
      );

      final u = (await readiness.check()) as StorageUnavailable;

      expect(u.autostartAttempted, isFalse);
      expect(u.fixCommand, contains('gnome-keyring'));
      expect(u.technicalDetail, contains('not installed'));
    });

    test('parses DBUS_SESSION_BUS_ADDRESS from dbus-launch --sh-syntax output',
        () async {
      // Real-world dbus-launch --sh-syntax output shape. We assert the parsed
      // address reaches setenv and the autostart reports success.
      const output = '''
DCONF_USER_CONFIG_DIR=/tmp/dconf-XXXX
GNOME_KEYRING_CONTROL=/run/user/1000/keyring
DBUS_SESSION_BUS_ADDRESS='unix:abstract=/tmp/dbus-AAA,guid=abc';
export DBUS_SESSION_BUS_ADDRESS;
DBUS_SESSION_BUS_PID=4242;
''';
      String? capturedBus;
      bool? capturedOk;
      final autostart = LinuxSecretServiceAutostart(
        runner: (executable, arguments, {bool runInShell = false}) async {
          if (executable == 'which') {
            return _ok('/usr/bin/${arguments.first}');
          }
          if (executable == '/usr/bin/dbus-launch') {
            return _ok(output);
          }
          if (executable == '/usr/bin/gnome-keyring-daemon') {
            return _ok('GNOME_KEYRING_CONTROL=/run/user/1000/keyring');
          }
          return _fail(1, 'unexpected $executable');
        },
        envSetter: (name, value) {
          if (name == 'DBUS_SESSION_BUS_ADDRESS') capturedBus = value;
          return true;
        },
      );

      final result = await autostart.attempt(retryProbe: () async {
        capturedOk = true;
        return true;
      });

      expect(capturedBus, 'unix:abstract=/tmp/dbus-AAA,guid=abc');
      expect(capturedOk, isTrue, reason: 'retry probe must run after start');
      expect(result.succeeded, isTrue);
    });
  });

  group('humanizeSecureStorageError', () {
    test('maps a libsecret PlatformException to a friendly message', () {
      final msg = humanizeSecureStorageError(_libsecretException());
      expect(msg.contains('PlatformException'), isFalse);
      expect(msg.toLowerCase(), contains('keyring'));
    });

    test('maps a non-keyring error without leaking the raw PlatformException',
        () {
      final msg = humanizeSecureStorageError(
        PlatformException(code: 'SomethingElse', message: 'boom'),
      );
      expect(msg.contains('PlatformException'), isFalse);
      expect(msg, contains('SomethingElse'));
    });

    test('maps a plain Exception to a friendly message', () {
      final msg = humanizeSecureStorageError(Exception('disk full'));
      expect(msg.contains('Exception'), isFalse);
      expect(msg, contains('disk full'));
    });
  });
}

/// An autostart that does nothing (used to isolate the PlatformException path
/// from real Process.run on the test host).
class _NoopAutostart implements SecretServiceAutostart {
  @override
  Future<AutostartResult> attempt({
    required Future<bool> Function() retryProbe,
  }) async {
    return const AutostartResult(
      attempted: false,
      succeeded: false,
      detail: 'noop (test)',
    );
  }
}
