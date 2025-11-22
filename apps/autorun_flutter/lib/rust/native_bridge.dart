import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart' as pkg_ffi;

class _Symbols {
  static const String generate = 'icp_generate_keypair';
  static const String principalFromPublicKey = 'icp_principal_from_public_key';
  static const String signMessage = 'icp_sign_message';
  static const String free = 'icp_free_string';
  static const String fetchCandid = 'icp_fetch_candid';
  static const String parseCandid = 'icp_parse_candid';
  static const String callAnonymous = 'icp_call_anonymous';
  static const String callAuthenticated = 'icp_call_authenticated';
  static const String luaExec = 'icp_lua_exec';
  static const String luaLint = 'icp_lua_lint';
  static const String luaValidateComprehensive =
      'icp_lua_validate_comprehensive';
  static const String luaAppInit = 'icp_lua_app_init';
  static const String luaAppView = 'icp_lua_app_view';
  static const String luaAppUpdate = 'icp_lua_app_update';
}

class RustKeypairResult {
  RustKeypairResult({
    required this.publicKeyB64,
    required this.privateKeyB64,
    required this.principalText,
  });
  final String publicKeyB64;
  final String privateKeyB64;
  final String principalText;
}

class RustBridgeLoader {
  const RustBridgeLoader();

  ffi.DynamicLibrary? _open() {
    if (Platform.isAndroid) {
      try {
        return ffi.DynamicLibrary.open('libicp_core.so');
      } catch (_) {
        return null;
      }
    }
    if (Platform.isIOS) {
      try {
        return ffi.DynamicLibrary.process();
      } catch (_) {
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
        } catch (_) {}
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
        } catch (_) {}
      }
      return null;
    }
    if (Platform.isWindows) {
      try {
        return ffi.DynamicLibrary.open('icp_core.dll');
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  RustKeypairResult? generateKeypair({required int alg, String? mnemonic}) {
    final lib = _open();
    if (lib == null) return null;

    final generate = lib.lookupFunction<_GenNative, _GenDart>(
      _Symbols.generate,
    );
    final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);

    final ffi.Pointer<pkg_ffi.Utf8> strPtr =
        mnemonic == null ? ffi.nullptr : mnemonic.toNativeUtf8();
    final ffi.Pointer<ffi.Int8> arg =
        strPtr == ffi.nullptr ? ffi.nullptr : strPtr.cast<ffi.Int8>();
    final ffi.Pointer<ffi.Int8> res = generate(alg, arg);
    // Memory managed by toNativeUtf8() - no manual free needed
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

  /// Derive principal text from algorithm and public key.
  /// [alg]: 0 = ed25519, 1 = secp256k1
  /// [publicKeyB64]: base64-encoded public key
  String? principalFromPublicKey(
      {required int alg, required String publicKeyB64}) {
    final lib = _open();
    if (lib == null) return null;

    final fn = lib
        .lookupFunction<_GenNative, _GenDart>(_Symbols.principalFromPublicKey);
    final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);

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

  /// Sign a message with a private key.
  /// [alg]: 0 = Ed25519, 1 = secp256k1
  /// [messageB64]: base64-encoded message
  /// [privateKeyB64]: base64-encoded private key
  /// Returns JSON: {"ok": true, "signature": "<base64>"} or {"ok": false, "error": "..."}
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
    final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);

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
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
      return out;
    } finally {
      // Free the allocated memory - toNativeUtf8() returns managed memory
    }
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
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      // Memory managed by toNativeUtf8() - no manual free needed
    }
  }

  String? callAnonymous({
    required String canisterId,
    required String method,
    required int kind,
    String args = '()',
    String? host,
  }) {
    final lib = _open();
    if (lib == null) return null;
    final cid = canisterId.toNativeUtf8().cast<ffi.Int8>();
    final m = method.toNativeUtf8().cast<ffi.Int8>();
    final a = args.toNativeUtf8().cast<ffi.Int8>();
    final h = host == null ? ffi.nullptr : host.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib.lookupFunction<_CallAnonNative, _CallAnonDart>(
          _Symbols.callAnonymous);
      final res = fn(cid.cast(), m.cast(), kind, a.cast(), h.cast());
      if (res == ffi.nullptr) return null;
      try {
        final s = res.cast<pkg_ffi.Utf8>().toDartString();
        return s;
      } finally {
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      // Memory managed by toNativeUtf8() - no manual free needed
    }
  }

  String? callAuthenticated({
    required String canisterId,
    required String method,
    required int kind,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) {
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
      final res = fn(cid.cast(), m.cast(), kind, a.cast(), k.cast(), h.cast());
      if (res == ffi.nullptr) return null;
      try {
        final s = res.cast<pkg_ffi.Utf8>().toDartString();
        return s;
      } finally {
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      // Memory managed by toNativeUtf8() - no manual free needed
    }
  }

  String? luaExec({required String script, String? jsonArg}) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    final a =
        jsonArg == null ? ffi.nullptr : jsonArg.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn =
          lib.lookupFunction<_Str2StrNative, _Str2StrDart>(_Symbols.luaExec);
      final res = fn(s.cast(), a.cast());
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      // Memory managed by toNativeUtf8() - no manual free needed
    }
  }

  String? luaLint({required String script}) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn =
          lib.lookupFunction<_Str1StrNative, _Str1StrDart>(_Symbols.luaLint);
      final res = fn(s.cast());
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      // Memory managed by toNativeUtf8() - no manual free needed
    }
  }

  String? validateLuaComprehensive({
    required String script,
    bool isExample = false,
    bool isTest = false,
    bool isProduction = false,
  }) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib.lookupFunction<_LuaValidateComprehensiveNative,
          _LuaValidateComprehensiveDart>(
        _Symbols.luaValidateComprehensive,
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
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      // Memory managed by toNativeUtf8() - no manual free needed
    }
  }

  // ---- TEA-style Lua app ----
  String? luaAppInit(
      {required String script, String? jsonArg, int budgetMs = 50}) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    final a =
        jsonArg == null ? ffi.nullptr : jsonArg.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib.lookupFunction<_LuaAppInitNative, _LuaAppInitDart>(
          _Symbols.luaAppInit);
      final res = fn(s.cast(), a.cast(), budgetMs);
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      // Memory managed by toNativeUtf8() - no manual free needed
    }
  }

  String? luaAppView(
      {required String script, required String stateJson, int budgetMs = 50}) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8().cast<ffi.Int8>();
    final st = stateJson.toNativeUtf8().cast<ffi.Int8>();
    try {
      final fn = lib.lookupFunction<_LuaAppViewNative, _LuaAppViewDart>(
          _Symbols.luaAppView);
      final res = fn(s.cast(), st.cast(), budgetMs);
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      // Memory managed by toNativeUtf8() - no manual free needed
    }
  }

  String? luaAppUpdate(
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
      final fn = lib.lookupFunction<_LuaAppUpdateNative, _LuaAppUpdateDart>(
          _Symbols.luaAppUpdate);
      final res = fn(s.cast(), m.cast(), st.cast(), budgetMs);
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      // Memory managed by toNativeUtf8() - no manual free needed
    }
  }
}

// Convenience wrapper class for easier access
class NativeBridge {
  final RustBridgeLoader _loader = const RustBridgeLoader();

  String validateLuaComprehensive({
    required String script,
    bool isExample = false,
    bool isTest = false,
    bool isProduction = false,
  }) {
    return _loader.validateLuaComprehensive(
          script: script,
          isExample: isExample,
          isTest: isTest,
          isProduction: isProduction,
        ) ??
        '';
  }

  // Other convenience methods can be added here as needed
  String? luaExec({required String script, String? jsonArg}) {
    return _loader.luaExec(script: script, jsonArg: jsonArg);
  }

  String? luaLint({required String script}) {
    return _loader.luaLint(script: script);
  }
}

typedef _GenNative = ffi.Pointer<ffi.Int8> Function(
    ffi.Int32, ffi.Pointer<ffi.Int8>);
typedef _GenDart = ffi.Pointer<ffi.Int8> Function(int, ffi.Pointer<ffi.Int8>);

typedef _SignMessageNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Int32, // alg
  ffi.Pointer<ffi.Int8>, // message_b64
  ffi.Pointer<ffi.Int8>, // private_key_b64
);
typedef _SignMessageDart = ffi.Pointer<ffi.Int8> Function(
  int,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Int8>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Int8>);

// Helper low-arity string-returning functions
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

typedef _LuaValidateComprehensiveNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>, // script
  ffi.Int32, // is_example
  ffi.Int32, // is_test
  ffi.Int32, // is_production
);
typedef _LuaValidateComprehensiveDart = ffi.Pointer<ffi.Int8> Function(
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

// Lua app FFI typedefs
typedef _LuaAppInitNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>, // script
  ffi.Pointer<ffi.Int8>, // json_arg
  ffi.Uint64, // budget_ms
);
typedef _LuaAppInitDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  int,
);
typedef _LuaAppViewNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>, // script
  ffi.Pointer<ffi.Int8>, // state_json
  ffi.Uint64, // budget_ms
);
typedef _LuaAppViewDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  int,
);
typedef _LuaAppUpdateNative = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>, // script
  ffi.Pointer<ffi.Int8>, // msg_json
  ffi.Pointer<ffi.Int8>, // state_json
  ffi.Uint64, // budget_ms
);
typedef _LuaAppUpdateDart = ffi.Pointer<ffi.Int8> Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  int,
);
