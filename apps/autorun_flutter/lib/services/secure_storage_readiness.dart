/// Secure-storage readiness probe + (Linux) gnome-keyring auto-start.
///
/// WU-S2 (UI_EXCELLENCE_PLAN.md) / NEW-2 + NEW-4 (UX_REVIEW_ROUND2.md).
///
/// On a minimal Linux desktop with no Secret Service (no `gnome-keyring-daemon`,
/// `DBUS_SESSION_BUS_ADDRESS` unset), `flutter_secure_storage` (→ libsecret)
/// THROWS `PlatformException(Libsecret error, Failed to unlock the keyring)` on
/// every write. The first-run wizard hits this inside `createProfile`, so no
/// profile can ever be created and every identity-dependent flow is blocked.
///
/// This service answers one question — *can secrets actually be persisted on
/// this platform right now?* — and, on Linux, tries to fix the environment
/// automatically (bring up a D-Bus session + start the keyring) before reporting
/// a clear, actionable, copyable failure.
///
/// Design notes:
/// - The probe is a **platform-availability** check, NOT cryptography. We expose
///   [SecureStorageProbe] as a thin interface over the platform call so tests
///   can simulate "keyring down" by throwing [PlatformException] WITHOUT
///   touching real keys (legit seam — no crypto is mocked).
/// - All error mapping happens here: a raw `PlatformException(…)` string never
///   reaches the UI (NEW-4). Callers render the friendly [StorageUnavailable]
///   fields.
/// - No insecure plaintext fallback is ever offered (the zero-knowledge
///   secure-storage model is preserved). The honest fix is "install a Secret
///   Service"; the single source for that guidance is [LinuxSecretServiceHelp].
library;

import 'dart:ffi' as ffi;
import 'dart:io' show File, Platform, Process, ProcessResult;

import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException, PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single source of truth for "how do I get a Secret Service on Linux".
///
/// The install command varies by distro; [commandForCurrentDistro] detects the
/// distro from `/etc/os-release` and returns the right one (defaulting to the
/// Debian/Ubuntu command, which is the primary dev target — see UX_REVIEW_ROUND2
/// §Setup: "Debian 13").
class LinuxSecretServiceHelp {
  const LinuxSecretServiceHelp._();

  /// Short, human explanation shown in the actionable panel.
  static const String explanation =
      'Linux desktop encrypts your private keys with a system Secret Service '
      '(gnome-keyring or KWallet). None is running, so the app cannot safely '
      'store a keypair. Install one and ensure it is running.';

  /// Debian/Ubuntu (the primary dev target).
  static const String debianCommand =
      'sudo apt-get install -y gnome-keyring libsecret-tools';

  /// Fedora/RHEL.
  static const String fedoraCommand =
      'sudo dnf install -y gnome-keyring libsecret';

  /// Arch / Manjaro.
  static const String archCommand =
      'sudo pacman -S --noconfirm gnome-keyring libsecret';

  /// openSUSE.
  static const String suseCommand =
      'sudo zypper install -y gnome-keyring libsecret';

  /// Detect the distro id from `/etc/os-release` (`ID=…`) and return the
  /// matching install command. Falls back to [debianCommand]. Returns `null`
  /// off-Linux (no Secret Service needed there).
  static String commandForCurrentDistro() {
    if (!Platform.isLinux) {
      // Non-Linux platforms use Keychain/Keystore; no install command applies.
      return '';
    }
    final String id = _readDistroId();
    switch (id) {
      case 'fedora':
      case 'rhel':
      case 'centos':
      case 'rocky':
      case 'alma':
        return fedoraCommand;
      case 'arch':
      case 'manjaro':
      case 'endeavouros':
        return archCommand;
      case 'opensuse-leap':
      case 'opensuse-tumbleweed':
      case 'opensuse':
        return suseCommand;
      default:
        // Debian, Ubuntu, Linux Mint, Pop!_OS, and unknowns → apt.
        return debianCommand;
    }
  }

  /// Parse the lower-cased `ID=` (and first `ID_LIKE=`) value from
  /// `/etc/os-release`. Returns '' if unreadable.
  static String _readDistroId() {
    try {
      final file = File('/etc/os-release');
      if (!file.existsSync()) return '';
      final lines = file.readAsLinesSync();
      String id = '';
      String idLike = '';
      for (final line in lines) {
        if (line.startsWith('ID=')) {
          id = _stripQuotes(line.substring(3).trim().toLowerCase());
        } else if (line.startsWith('ID_LIKE=')) {
          idLike = _stripQuotes(line.substring(8).trim().toLowerCase());
        }
      }
      // Prefer an exact family match from ID_LIKE if present (e.g. Ubuntu →
      // ID_LIKE=debian).
      if (idLike.isNotEmpty) {
        for (final part in idLike.split(' ')) {
          if (part == 'debian' || part == 'ubuntu') return 'debian';
          if (part == 'rhel' || part == 'fedora') return 'fedora';
          if (part == 'arch') return 'arch';
          if (part == 'suse') return 'opensuse';
        }
      }
      return id;
    } catch (e) {
      debugPrint('LinuxSecretServiceHelp: failed to read /etc/os-release: $e');
      return '';
    }
  }

  static String _stripQuotes(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }
}

/// The result of a readiness probe. Sealed so callers must handle both states.
sealed class StorageReadiness {
  const StorageReadiness();

  /// `true` only when secrets can be persisted right now.
  bool get isOk;
}

/// Secrets round-trip cleanly — proceed with profile creation.
final class StorageReady extends StorageReadiness {
  const StorageReady();
  @override
  bool get isOk => true;
}

/// Secrets cannot be persisted. Render the actionable panel (NEW-4 friendly).
///
/// [reason]/[explanation]/[fixCommand]/[fixHint] are user-facing.
/// [technicalDetail] is for an optional "show details" affordance — it must
/// never be rendered as the primary message.
final class StorageUnavailable extends StorageReadiness {
  const StorageUnavailable({
    required this.reason,
    required this.explanation,
    required this.fixCommand,
    required this.fixHint,
    required this.technicalDetail,
    this.autostartAttempted = false,
  });

  factory StorageUnavailable.platformException(PlatformException e) {
    final code = e.code.toLowerCase();
    final message = (e.message ?? '').toLowerCase();
    final looksLikeKeyring = code.contains('libsecret') ||
        code.contains('keyring') ||
        message.contains('libsecret') ||
        message.contains('keyring') ||
        message.contains('unlock');
    if (looksLikeKeyring) {
      return StorageUnavailable(
        reason: "Couldn't access the system keyring",
        explanation: LinuxSecretServiceHelp.explanation,
        fixCommand: LinuxSecretServiceHelp.commandForCurrentDistro(),
        fixHint: _distroHint(),
        technicalDetail: 'PlatformException(code=${e.code}, message=${e.message})',
      );
    }
    return StorageUnavailable(
      reason: 'Secure storage is unavailable',
      explanation: "The platform key store rejected the app's request. "
          'On Linux, ensure gnome-keyring (or KWallet) is installed and running.',
      fixCommand: LinuxSecretServiceHelp.commandForCurrentDistro(),
      fixHint: _distroHint(),
      technicalDetail: 'PlatformException(code=${e.code}, message=${e.message})',
    );
  }

  factory StorageUnavailable.missingPlugin() {
    return StorageUnavailable(
      reason: 'Secure storage backend is missing',
      explanation: LinuxSecretServiceHelp.explanation,
      fixCommand: LinuxSecretServiceHelp.commandForCurrentDistro(),
      fixHint: _distroHint(),
      technicalDetail:
          'MissingPluginException: no flutter_secure_storage backend registered '
          '(typical of a headless / plugin-less test environment).',
    );
  }

  /// `write()` returned but `read()` could not fetch the value back — silent
  /// data loss. Private keys would be unrecoverable. Treated as unavailable
  /// (NEVER swallowed) — the user must be told.
  factory StorageUnavailable.silentDataLoss() {
    return StorageUnavailable(
      reason: 'Secure storage is not retaining data',
      explanation: 'The platform key store accepted the write but lost it on '
          'read-back. Storing a keypair now would permanently lose the private '
          'key. Fix the Secret Service before continuing.',
      fixCommand: LinuxSecretServiceHelp.commandForCurrentDistro(),
      fixHint: _distroHint(),
      technicalDetail:
          'Round-trip probe: read-back value did not match the written sentinel.',
    );
  }

  /// Return a copy annotated with what the gnome-keyring auto-start tried, so
  /// the user keeps the precise underlying reason + the right install command
  /// and additionally sees whether a start was attempted. Used by
  /// [SecureStorageReadiness.check] when auto-start did not recover the store.
  StorageUnavailable withAutostartNote(AutostartResult auto) {
    final note = auto.detail == null ? '' : ' ${auto.detail}';
    return StorageUnavailable(
      reason: reason,
      explanation: explanation,
      fixCommand: fixCommand,
      fixHint: fixHint,
      technicalDetail: '$technicalDetail$note',
      autostartAttempted: auto.attempted,
    );
  }

  final String reason;
  final String explanation;
  final String fixCommand;
  final String fixHint;
  final String technicalDetail;
  final bool autostartAttempted;

  @override
  bool get isOk => false;

  static String _distroHint() {
    if (!Platform.isLinux) {
      return 'No Secret Service install command applies on this platform.';
    }
    return 'Install the package for your distro, then re-run the app. '
        'On a headless/SSH box, start a D-Bus session and unlock an empty '
        'keyring (see AGENTS.md "Secure storage on Linux desktop").';
  }
}

/// Thin interface over the platform secure-storage call.
///
/// This is the LEGIT TEST SEAM: readiness is platform availability, not
/// cryptography. Tests inject a fake that either round-trips (→ [StorageReady])
/// or throws [PlatformException] (→ [StorageUnavailable]) — no keys involved.
abstract interface class SecureStorageProbe {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
}

/// Production probe backed by `flutter_secure_storage`.
class FlutterSecureStorageProbe implements SecureStorageProbe {
  const FlutterSecureStorageProbe([this._storage]);

  final FlutterSecureStorage? _storage;

  FlutterSecureStorage get _resolved =>
      _storage ?? const FlutterSecureStorage();

  @override
  Future<void> write({required String key, required String value}) =>
      _resolved.write(key: key, value: value);

  @override
  Future<String?> read({required String key}) => _resolved.read(key: key);

  @override
  Future<void> delete({required String key}) => _resolved.delete(key: key);
}

/// Signature of a `Process.run`-like helper, injectable for tests.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

/// Default [ProcessRunner] — delegates to [Process.run].
ProcessRunner _defaultProcessRunner = (
  String executable,
  List<String> arguments, {
  bool runInShell = false,
}) =>
    Process.run(executable, arguments, runInShell: runInShell);

/// Signature of an in-process environment setter (Linux: libc `setenv`),
/// injectable for tests.
typedef EnvSetter = bool Function(String name, String value);

/// Linux default [EnvSetter]: calls libc `setenv` via FFI so the *current*
/// process (where libsecret lives) picks up the new `DBUS_SESSION_BUS_ADDRESS`.
/// Returns `true` on success. Off-Linux or on lookup failure, returns `false`.
EnvSetter _defaultEnvSetter = (String name, String value) {
  if (!Platform.isLinux) return false;
  try {
    final lib = ffi.DynamicLibrary.process();
    final setenv = lib.lookupFunction<
        ffi.Int32 Function(
            ffi.Pointer<pkg_ffi.Utf8>, ffi.Pointer<pkg_ffi.Utf8>, ffi.Int32),
        int Function(
            ffi.Pointer<pkg_ffi.Utf8>, ffi.Pointer<pkg_ffi.Utf8>, int)>('setenv');
    final namePtr = name.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    try {
      final rc = setenv(namePtr, valuePtr, 1);
      return rc == 0;
    } finally {
      pkg_ffi.calloc.free(namePtr);
      pkg_ffi.calloc.free(valuePtr);
    }
  } catch (e) {
    debugPrint('SecureStorageReadiness: libc setenv failed for $name: $e');
    return false;
  }
};

/// Strategy interface for attempting to bring up a Secret Service. Injected so
/// tests can stub the auto-start without spawning real processes.
abstract interface class SecretServiceAutostart {
  /// Attempt to bring up a usable Secret Service.
  ///
  /// [retryProbe] should re-run the readiness round-trip and return `true` when
  /// it now succeeds. Returns an [AutostartResult] describing what happened so
  /// the caller can surface a precise message.
  Future<AutostartResult> attempt({
    required Future<bool> Function() retryProbe,
  });
}

/// Best-effort gnome-keyring auto-start for the "installed but not running"
/// case. Pure logic; every side-effecting collaborator ([ProcessRunner],
/// [EnvSetter]) is injectable so the strategy is fully unit-testable.
class LinuxSecretServiceAutostart implements SecretServiceAutostart {
  LinuxSecretServiceAutostart({
    ProcessRunner? runner,
    EnvSetter? envSetter,
  })  : _runner = runner ?? _defaultProcessRunner,
        _envSetter = envSetter ?? _defaultEnvSetter;

  final ProcessRunner _runner;
  final EnvSetter _envSetter;

  @override
  Future<AutostartResult> attempt({
    required Future<bool> Function() retryProbe,
  }) async {
    // 1) gnome-keyring-daemon must be installed.
    final daemonPath = await _which('gnome-keyring-daemon');
    if (daemonPath == null) {
      return const AutostartResult(
        attempted: false,
        succeeded: false,
        detail: 'gnome-keyring-daemon is not installed.',
      );
    }

    // 2) Ensure a D-Bus session bus address is exported in this process.
    String? busAddr = Platform.environment['DBUS_SESSION_BUS_ADDRESS'];
    if (busAddr == null || busAddr.isEmpty) {
      final dbusLaunch = await _which('dbus-launch');
      if (dbusLaunch == null) {
        return const AutostartResult(
          attempted: false,
          succeeded: false,
          detail: 'dbus-launch is not installed; cannot start a D-Bus session.',
        );
      }
      final res = await _runner(dbusLaunch, ['--sh-syntax']);
      if (res.exitCode != 0) {
        return AutostartResult(
          attempted: true,
          succeeded: false,
          detail: 'dbus-launch exited ${res.exitCode}: ${res.stderr}.',
        );
      }
      busAddr = _parseDbusAddress(res.stdout.toString());
      if (busAddr == null) {
        return AutostartResult(
          attempted: true,
          succeeded: false,
          detail: 'dbus-launch produced no DBUS_SESSION_BUS_ADDRESS: '
              '${res.stdout}.',
        );
      }
      if (!_envSetter('DBUS_SESSION_BUS_ADDRESS', busAddr)) {
        return AutostartResult(
          attempted: true,
          succeeded: false,
          detail: 'Could not export DBUS_SESSION_BUS_ADDRESS into this process.',
        );
      }
    }

    // 3) Start the secrets component of gnome-keyring.
    final startRes =
        await _runner(daemonPath, ['--start', '--components=secrets']);
    if (startRes.exitCode != 0) {
      return AutostartResult(
        attempted: true,
        succeeded: false,
        detail: 'gnome-keyring-daemon --start exited ${startRes.exitCode}: '
            '${startRes.stderr}.',
      );
    }

    // 4) Confirm via the real round-trip probe.
    final ok = await retryProbe();
    return AutostartResult(
      attempted: true,
      succeeded: ok,
      detail: ok
          ? null
          : 'Keyring started but the round-trip probe still failed — a restart '
              'of the app may be needed so libsecret re-connects.',
    );
  }

  Future<String?> _which(String name) async {
    try {
      final res = await _runner('which', [name]);
      if (res.exitCode != 0) return null;
      final out = res.stdout.toString().trim();
      return out.isEmpty ? null : out;
    } catch (e) {
      debugPrint('SecureStorageReadiness: which($name) failed: $e');
      return null;
    }
  }

  /// Extract the `DBUS_SESSION_BUS_ADDRESS='…'` value from `dbus-launch`'s
  /// `--sh-syntax` output. Returns `null` if not found.
  static String? _parseDbusAddress(String output) {
    // Lines look like:  DBUS_SESSION_BUS_ADDRESS='unix:abstract=/tmp/dbus-…,guid=…';
    final regex = RegExp(
      r'''DBUS_SESSION_BUS_ADDRESS=['"]([^'"]+)['"]''',
    );
    final match = regex.firstMatch(output);
    return match?.group(1);
  }
}

/// Outcome of [LinuxSecretServiceAutostart.attempt].
class AutostartResult {
  const AutostartResult({
    required this.attempted,
    required this.succeeded,
    required this.detail,
  });

  /// Whether any start step was tried (vs. "not installed, nothing to try").
  final bool attempted;
  /// Whether the retry probe confirmed secrets can now be persisted.
  final bool succeeded;
  /// Human note for the readiness result's technical detail (may be `null`).
  final String? detail;
}

/// Orchestrates the readiness check.
///
/// Typical use:
/// ```dart
/// final readiness = await SecureStorageReadiness().check();
/// switch (readiness) {
///   case StorageReady():     // proceed to createProfile
///   case StorageUnavailable(:final reason):  // render actionable panel
/// }
/// ```
class SecureStorageReadiness {
  SecureStorageReadiness({
    SecureStorageProbe? probe,
    SecretServiceAutostart? autostart,
  })  : _probe = probe ?? const FlutterSecureStorageProbe(),
        _autostart = autostart ?? LinuxSecretServiceAutostart();

  final SecureStorageProbe _probe;
  final SecretServiceAutostart _autostart;

  /// Sentinel key/value used for the round-trip. Namespaced so it never
  /// collides with a real keypair id.
  static const String _probeKey = '__icp_secure_storage_readiness_probe__';
  static const String _probeValue = 'ok';

  /// Probe once. On Linux, if the first probe fails, attempt a gnome-keyring
  /// auto-start and retry. Off-Linux, probe once (no Secret Service needed).
  Future<StorageReadiness> check() async {
    // Web / non-Linux: no Secret Service concept; a single probe is decisive.
    if (kIsWeb || !Platform.isLinux) {
      return _probeOnce();
    }

    final first = await _probeOnce();
    if (first is StorageReady) return first;

    // Unavailable on Linux: try to fix the environment, then re-probe.
    final auto = await _autostart.attempt(
      retryProbe: () async {
        final retry = await _probeOnce();
        return retry is StorageReady;
      },
    );
    if (auto.succeeded) return const StorageReady();
    // Auto-start did not recover. Preserve the ORIGINAL probe failure reason
    // (so the user keeps the precise message + the right install command) and
    // annotate it with what auto-start tried.
    return (first as StorageUnavailable).withAutostartNote(auto);
  }

  Future<StorageReadiness> _probeOnce() async {
    try {
      await _probe.write(key: _probeKey, value: _probeValue);
      final readBack = await _probe.read(key: _probeKey);
      if (readBack != _probeValue) {
        // Write didn't throw but read is null/wrong → silent data loss. NEVER
        // swallow (a profile created here would lose its private key forever).
        return StorageUnavailable.silentDataLoss();
      }
      await _probe.delete(key: _probeKey);
      return const StorageReady();
    } on PlatformException catch (e) {
      return StorageUnavailable.platformException(e);
    } on MissingPluginException {
      return StorageUnavailable.missingPlugin();
    }
  }
}

/// Map an arbitrary error caught during profile creation to a friendly,
/// NEW-4-compliant message. Used by the wizard's residual `catch` so a raw
/// `PlatformException(…)` string is never shown even if the keyring goes down
/// between the readiness probe and `createProfile`.
String humanizeSecureStorageError(Object error) {
  switch (error) {
    case PlatformException(:final code, :final message):
      final looksLikeKeyring = code.toLowerCase().contains('libsecret') ||
          code.toLowerCase().contains('keyring') ||
          (message ?? '').toLowerCase().contains('libsecret') ||
          (message ?? '').toLowerCase().contains('keyring') ||
          (message ?? '').toLowerCase().contains('unlock');
      if (looksLikeKeyring) {
        return "Couldn't access the system keyring. "
            'Tap Retry after installing/starting gnome-keyring (see the setup guide).';
      }
      return 'Secure storage reported an error (code: $code). '
          'Tap Retry, or see the setup guide.';
    case MissingPluginException():
      return 'Secure storage backend is missing. '
          'On Linux, install and start gnome-keyring (see the setup guide).';
    default:
      // Surface the runtime type but never the raw PlatformException string.
      var detail = error.toString().replaceAll('Exception: ', '');
      // Defensive (NEW-4): if a PlatformException was re-wrapped as a plain
      // Exception somewhere up the stack, do not let its verbatim string leak.
      if (detail.contains('PlatformException')) {
        detail = 'secure storage reported an error';
      }
      return 'Could not create the profile ($detail). Please try again.';
  }
}
