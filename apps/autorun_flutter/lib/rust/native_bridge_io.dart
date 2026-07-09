/// Real FFI bridge to the Rust core (`libicp_core`) — IO platforms only.
///
/// This file is selected by [native_bridge.dart]'s conditional export on
/// non-Web targets. It freely uses `dart:ffi`. Pure-Dart shared types
/// ([RustKeypairResult], [EncryptedVaultResult], [VaultEncryptionException],
/// [VaultDecryptionException]) are imported from the facade.
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/foundation.dart';

import 'native_bridge.dart';

/// On IO/native the QuickJS engine is the in-process rquickjs FFI — always
/// available (or surfaced as a per-call `null`/error by [RustBridgeLoader] when
/// `libicp_core` is missing). There is no async WASM load to await, so the probe
/// is immediately [QuickJsReady]. The Web counterpart (in `native_bridge_web.dart`)
/// loads the singleton engine instead.
Future<QuickJsReadiness> probeQuickJsReadiness() async => const QuickJsReady();

class _Symbols {
  static const String generate = 'icp_generate_keypair';
  static const String principalFromPublicKey = 'icp_principal_from_public_key';
  static const String signMessage = 'icp_sign_message';
  static const String free = 'icp_free_string';
  static const String fetchCandid = 'icp_fetch_candid';
  static const String parseCandid = 'icp_parse_candid';
  static const String callAnonymous = 'icp_call_anonymous';
  static const String callAuthenticated = 'icp_call_authenticated';
  static const String jsExec = 'icp_js_exec';
  static const String jsLint = 'icp_js_lint';
  static const String jsValidateComprehensive = 'icp_js_validate_comprehensive';
  static const String jsAppInit = 'icp_js_app_init';
  static const String jsAppView = 'icp_js_app_view';
  static const String jsAppUpdate = 'icp_js_app_update';
  static const String encryptVault = 'icp_encrypt_vault';
  static const String decryptVault = 'icp_decrypt_vault';
}

class RustBridgeLoader {
  const RustBridgeLoader();

  static ffi.DynamicLibrary? _cachedLib;
  static bool _libResolved = false;

  static _FreeDart? _cachedFree;

  ffi.DynamicLibrary? _open() {
    if (_libResolved) return _cachedLib;
    _cachedLib = _resolveLibrary();
    _libResolved = true;
    return _cachedLib;
  }

  ffi.DynamicLibrary? _resolveLibrary() {
    if (Platform.isAndroid) {
      try {
        return ffi.DynamicLibrary.open('libicp_core.so');
      } on ArgumentError catch (e) {
        debugPrint('native_bridge: Android libicp_core.so open failed: $e');
        return null;
      }
    }
    if (Platform.isIOS) {
      try {
        return ffi.DynamicLibrary.process();
      } on ArgumentError catch (e) {
        debugPrint('native_bridge: iOS process library failed: $e');
        return null;
      }
    }
    if (Platform.isMacOS) {
      final paths = [
        'libicp_core.dylib',
        'build/macos/Build/Products/Debug/libicp_core.dylib',
        'build/macos/Build/Products/Release/libicp_core.dylib',
      ];
      for (final path in paths) {
        try {
          return ffi.DynamicLibrary.open(path);
        } on ArgumentError catch (e) {
          debugPrint('native_bridge: macOS $path open failed: $e');
        }
      }
      return null;
    }
    if (Platform.isLinux) {
      final paths = [
        'libicp_core.so',
        'build/linux/x64/debug/bundle/lib/libicp_core.so',
        'build/linux/x64/release/bundle/lib/libicp_core.so',
      ];
      for (final path in paths) {
        try {
          return ffi.DynamicLibrary.open(path);
        } on ArgumentError catch (e) {
          debugPrint('native_bridge: Linux $path open failed: $e');
        }
      }
      return null;
    }
    if (Platform.isWindows) {
      try {
        return ffi.DynamicLibrary.open('icp_core.dll');
      } on ArgumentError catch (e) {
        debugPrint('native_bridge: Windows icp_core.dll open failed: $e');
        return null;
      }
    }
    return null;
  }

  _FreeDart _freeOf(ffi.DynamicLibrary lib) {
    final _FreeDart? cached = _cachedFree;
    if (cached != null && identical(_cachedLib, lib)) return cached;
    final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
    _cachedFree = free;
    return free;
  }

  RustKeypairResult? generateKeypair({required int alg, String? mnemonic}) {
    final lib = _open();
    if (lib == null) return null;

    final generate = lib.lookupFunction<_GenNative, _GenDart>(
      _Symbols.generate,
    );
    final free = _freeOf(lib);

    final ffi.Pointer<pkg_ffi.Utf8> strPtr =
        mnemonic == null ? ffi.nullptr : mnemonic.toNativeUtf8();
    final ffi.Pointer<ffi.Int8> arg =
        strPtr == ffi.nullptr ? ffi.nullptr : strPtr.cast<ffi.Int8>();
    final ffi.Pointer<ffi.Int8> res = generate(alg, arg);
    if (res == ffi.nullptr) return null;
    try {
      final String jsonStr = res.cast<pkg_ffi.Utf8>().toDartString();
      final Map<String, dynamic> obj =
          json.decode(jsonStr) as Map<String, dynamic>;
      return RustKeypairResult(
        publicKeyB64: obj['public_key_b64'] as String,
        privateKeyB64: obj['private_key_b64'] as String,
        principalText: obj['principal_text'] as String,
      );
    } finally {
      free(res);
    }
  }

  String? principalFromPublicKey(
      {required int alg, required String publicKeyB64}) {
    final lib = _open();
    if (lib == null) return null;

    final fn = lib
        .lookupFunction<_GenNative, _GenDart>(_Symbols.principalFromPublicKey);
    final free = _freeOf(lib);

    final pk = publicKeyB64.toNativeUtf8().cast<ffi.Int8>();
    final res = fn(alg, pk);
    if (res == ffi.nullptr) return null;
    try {
      final s = res.cast<pkg_ffi.Utf8>().toDartString();
      return s.isEmpty ? null : s;
    } finally {
      free(res);
    }
  }

  String? signMessage({
    required int alg,
    required String messageB64,
    required String privateKeyB64,
  }) {
    final lib = _open();
    if (lib == null) return null;

    final fn = lib.lookupFunction<_SignMessageNative, _SignMessageDart>(
      _Symbols.signMessage,
    );
    final free = _freeOf(lib);

    final msg = messageB64.toNativeUtf8().cast<ffi.Int8>();
    final pk = privateKeyB64.toNativeUtf8().cast<ffi.Int8>();
    final res = fn(alg, msg, pk);
    if (res == ffi.nullptr) return null;
    try {
      return res.cast<pkg_ffi.Utf8>().toDartString();
    } finally {
      free(res);
    }
  }

  Future<String?> fetchCandid(
      {required String canisterId, String? host}) async {
    final lib = _open();
    if (lib == null) return null;
    final cid = canisterId.toNativeUtf8().cast<ffi.Int8>();
    final h = host == null ? ffi.nullptr : host.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib
          .lookupFunction<_Str2StrNative, _Str2StrDart>(_Symbols.fetchCandid);
      final res = fn(cid.cast(), h.cast());
      if (res == ffi.nullptr) return null;
      String? out;
      try {
        final String s = res.cast<pkg_ffi.Utf8>().toDartString();
        out = s.trim().isEmpty ? null : s;
      } finally {
        final free = _freeOf(lib);
        free(res);
      }
      return out;
    } finally {}
  }

  String? parseCandid({required String candidText}) {
    final lib = _open();
    if (lib == null) return null;
    final txt = candidText.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib
          .lookupFunction<_Str1StrNative, _Str1StrDart>(_Symbols.parseCandid);
      final res = fn(txt.cast());
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        final free = _freeOf(lib);
        free(res);
      }
    } finally {}
  }

  /// R-3b WU-4 — widened to `Future<String?>` for facade uniformity with the
  /// Web target (agent-js calls are inherently async). The FFI call itself
  /// remains synchronous; `async` auto-wraps the result (no isolate overhead —
  /// the ~ms-scale FFI call doesn't warrant `Isolate.run`). Greenfield, no
  /// back-compat (plan §7.6).
  Future<String?> callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) async {
    final lib = _open();
    if (lib == null) return null;
    final cid = canisterId.toNativeUtf8().cast<ffi.Int8>();
    final m = method.toNativeUtf8().cast<ffi.Int8>();
    final a = args.toNativeUtf8().cast<ffi.Int8>();
    final h = host == null ? ffi.nullptr : host.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib.lookupFunction<_CallAnonNative, _CallAnonDart>(
          _Symbols.callAnonymous);
      final res = fn(cid.cast(), m.cast(), mode, a.cast(), h.cast());
      if (res == ffi.nullptr) return null;
      try {
        final s = res.cast<pkg_ffi.Utf8>().toDartString();
        return s;
      } finally {
        final free = _freeOf(lib);
        free(res);
      }
    } finally {}
  }

  /// R-3b WU-4 — widened to `Future<String?>` (see [callAnonymous]).
  Future<String?> callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) async {
    final lib = _open();
    if (lib == null) return null;
    final cid = canisterId.toNativeUtf8().cast<ffi.Int8>();
    final m = method.toNativeUtf8().cast<ffi.Int8>();
    final a = args.toNativeUtf8().cast<ffi.Int8>();
    final k = privateKeyB64.toNativeUtf8().cast<ffi.Int8>();
    final h = host == null ? ffi.nullptr : host.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib.lookupFunction<_CallAuthNative, _CallAuthDart>(
          _Symbols.callAuthenticated);
      final res = fn(cid.cast(), m.cast(), mode, a.cast(), k.cast(), h.cast());
      if (res == ffi.nullptr) return null;
      try {
        final s = res.cast<pkg_ffi.Utf8>().toDartString();
        return s;
      } finally {
        final free = _freeOf(lib);
        free(res);
      }
    } finally {}
  }

  String? jsExec({required String script, String? jsonArg}) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    final a =
        jsonArg == null ? ffi.nullptr : jsonArg.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn =
          lib.lookupFunction<_Str2StrNative, _Str2StrDart>(_Symbols.jsExec);
      final res = fn(s.cast(), a.cast());
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        final free = _freeOf(lib);
        free(res);
      }
    } finally {}
  }

  String? jsLint({required String script}) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn =
          lib.lookupFunction<_Str1StrNative, _Str1StrDart>(_Symbols.jsLint);
      final res = fn(s.cast());
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        final free = _freeOf(lib);
        free(res);
      }
    } finally {}
  }

  String? validateJsComprehensive({
    required String script,
    bool isExample = false,
    bool isTest = false,
    bool isProduction = false,
  }) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib.lookupFunction<_ValidateComprehensiveNative,
          _ValidateComprehensiveDart>(
        _Symbols.jsValidateComprehensive,
      );
      final res = fn(
        s.cast(),
        isExample ? 1 : 0,
        isTest ? 1 : 0,
        isProduction ? 1 : 0,
      );
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        _freeOf(lib)(res);
      }
    } finally {}
  }

  String? jsAppInit(
      {required String script, String? jsonArg, int budgetMs = 50}) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    final a =
        jsonArg == null ? ffi.nullptr : jsonArg.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib.lookupFunction<_AppInitNative, _AppInitDart>(
          _Symbols.jsAppInit);
      final res = fn(s.cast(), a.cast(), budgetMs);
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        _freeOf(lib)(res);
      }
    } finally {}
  }

  String? jsAppView(
      {required String script, required String stateJson, int budgetMs = 50}) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    final st = stateJson.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn =
          lib.lookupFunction<_AppViewNative, _AppViewDart>(_Symbols.jsAppView);
      final res = fn(s.cast(), st.cast(), budgetMs);
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        _freeOf(lib)(res);
      }
    } finally {}
  }

  String? jsAppUpdate(
      {required String script,
      required String msgJson,
      required String stateJson,
      int budgetMs = 50}) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    final m = msgJson.toNativeUtf8().cast<ffi.Int8>();
    final st = stateJson.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib.lookupFunction<_AppUpdateNative, _AppUpdateDart>(
          _Symbols.jsAppUpdate);
      final res = fn(s.cast(), m.cast(), st.cast(), budgetMs);
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        _freeOf(lib)(res);
      }
    } finally {}
  }

  /// Encrypt `plaintextB64` under `password` (Argon2id + AES-256-GCM).
  ///
  /// Returns a [Future] to keep the conditional-export signature uniform with
  /// the Web target, whose Argon2id KDF (`package:cryptography`'s
  /// `DartArgon2id`) is cooperatively async. On IO the underlying FFI call is
  /// still synchronous and CPU-bound; callers run this inside a background
  /// isolate via `Isolate.run` (see `VaultCryptoService`) so the UI stays
  /// responsive during the ~0.1–1 s derivation.
  Future<EncryptedVaultResult?> encryptVault({
    required String password,
    required String plaintextB64,
  }) async {
    final lib = _open();
    if (lib == null) return null;

    final fn = lib.lookupFunction<_EncryptVaultNative, _EncryptVaultDart>(
      _Symbols.encryptVault,
    );
    final free = _freeOf(lib);

    final pwd = password.toNativeUtf8().cast<ffi.Int8>();
    final pt = plaintextB64.toNativeUtf8().cast<ffi.Int8>();
    final res = fn(pwd, pt);
    if (res == ffi.nullptr) return null;
    try {
      final jsonStr = res.cast<pkg_ffi.Utf8>().toDartString();
      final obj = json.decode(jsonStr) as Map<String, dynamic>;
      if (obj['ok'] != true) {
        throw VaultEncryptionException(
            obj['error'] as String? ?? 'Encryption failed');
      }
      return EncryptedVaultResult(
        encryptedDataB64: obj['encrypted_data'] as String,
        saltB64: obj['salt'] as String,
        nonceB64: obj['nonce'] as String,
      );
    } finally {
      free(res);
    }
  }

  /// Decrypt an Argon2id + AES-256-GCM blob. Throws
  /// [VaultDecryptionException] on a wrong password / tampered ciphertext.
  ///
  /// Returns a [Future] for signature parity with the Web target (see
  /// [encryptVault]); the FFI call itself remains synchronous.
  Future<String?> decryptVault({
    required String password,
    required String encryptedDataB64,
    required String saltB64,
    required String nonceB64,
  }) async {
    final lib = _open();
    if (lib == null) return null;

    final fn = lib.lookupFunction<_DecryptVaultNative, _DecryptVaultDart>(
      _Symbols.decryptVault,
    );
    final free = _freeOf(lib);

    final pwd = password.toNativeUtf8().cast<ffi.Int8>();
    final ed = encryptedDataB64.toNativeUtf8().cast<ffi.Int8>();
    final salt = saltB64.toNativeUtf8().cast<ffi.Int8>();
    final nonce = nonceB64.toNativeUtf8().cast<ffi.Int8>();
    final res = fn(pwd, ed, salt, nonce);
    if (res == ffi.nullptr) return null;
    try {
      final jsonStr = res.cast<pkg_ffi.Utf8>().toDartString();
      final obj = json.decode(jsonStr) as Map<String, dynamic>;
      if (obj['ok'] != true) {
        throw VaultDecryptionException(
            obj['error'] as String? ?? 'Decryption failed');
      }
      return obj['plaintext'] as String;
    } finally {
      free(res);
    }
  }
}

class NativeBridge {
  final RustBridgeLoader _loader = const RustBridgeLoader();

  String validateJsComprehensive({
    required String script,
    bool isExample = false,
    bool isTest = false,
    bool isProduction = false,
  }) {
    return _loader.validateJsComprehensive(
          script: script,
          isExample: isExample,
          isTest: isTest,
          isProduction: isProduction,
        ) ??
        '';
  }

  String? jsExec({required String script, String? jsonArg}) {
    return _loader.jsExec(script: script, jsonArg: jsonArg);
  }

  String? jsLint({required String script}) {
    return _loader.jsLint(script: script);
  }
}

typedef _GenNative = ffi.Pointer<ffi.Int8> Function(
    ffi.Int32, ffi.Pointer<ffi.Int8>);
typedef _GenDart = ffi.Pointer<ffi.Int8> Function(int, ffi.Pointer<ffi.Int8>);

typedef _SignMessageNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Int32,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
typedef _SignMessageDart = ffi.Pointer<ffi.Int8> Function(
  int,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Int8>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Int8>);

typedef _Str1StrNative = ffi.Pointer<ffi.Int8> Function(ffi.Pointer<ffi.Int8>);
typedef _Str1StrDart = ffi.Pointer<ffi.Int8> Function(ffi.Pointer<ffi.Int8>);
typedef _Str2StrNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
typedef _Str2StrDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);

typedef _ValidateComprehensiveNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
);
typedef _ValidateComprehensiveDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  int,
  int,
  int,
);

typedef _CallAnonNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Int32,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
typedef _CallAnonDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  int,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);

typedef _CallAuthNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Int32,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
typedef _CallAuthDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  int,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);

typedef _AppInitNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Uint64,
);
typedef _AppInitDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  int,
);
typedef _AppViewNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Uint64,
);
typedef _AppViewDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  int,
);
typedef _AppUpdateNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Uint64,
);
typedef _AppUpdateDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  int,
);

typedef _EncryptVaultNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
typedef _EncryptVaultDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
typedef _DecryptVaultNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
typedef _DecryptVaultDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
