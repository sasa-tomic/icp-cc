import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart' as pkg_ffi;

class _Symbols {
  static const String generate = 'icp_generate_identity';
  static const String free = 'icp_free_string';
  static const String fetchCandid = 'icp_fetch_candid';
  static const String parseCandid = 'icp_parse_candid';
  static const String callAnonymous = 'icp_call_anonymous';
  static const String callAuthenticated = 'icp_call_authenticated';
  static const String favList = 'icp_favorites_list';
  static const String favAdd = 'icp_favorites_add';
  static const String favRemove = 'icp_favorites_remove';
  static const String luaExec = 'icp_lua_exec';
}

class RustIdentityResult {
  RustIdentityResult({
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
    try {
      if (Platform.isAndroid) return ffi.DynamicLibrary.open('libicp_core.so');
      if (Platform.isIOS) return ffi.DynamicLibrary.process();
      if (Platform.isMacOS) return ffi.DynamicLibrary.open('libicp_core.dylib');
      if (Platform.isLinux) return ffi.DynamicLibrary.open('libicp_core.so');
      if (Platform.isWindows) return ffi.DynamicLibrary.open('icp_core.dll');
      return null;
    } catch (_) {
      return null;
    }
  }

  RustIdentityResult? generateIdentity({required int alg, String? mnemonic}) {
    final lib = _open();
    if (lib == null) return null;

    final generate = lib.lookupFunction<_GenNative, _GenDart>(
      _Symbols.generate,
    );
    final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);

    final ffi.Pointer<pkg_ffi.Utf8> strPtr = mnemonic == null
        ? ffi.nullptr
        : mnemonic.toNativeUtf8();
    final ffi.Pointer<ffi.Int8> arg = strPtr == ffi.nullptr
        ? ffi.nullptr
        : strPtr.cast<ffi.Int8>();
    final ffi.Pointer<ffi.Int8> res = generate(alg, arg);
    if (strPtr != ffi.nullptr) {
      pkg_ffi.malloc.free(strPtr);
    }
    if (res == ffi.nullptr) return null;
    try {
      final String jsonStr = res.cast<pkg_ffi.Utf8>().toDartString();
      final Map<String, dynamic> obj =
          json.decode(jsonStr) as Map<String, dynamic>;
      return RustIdentityResult(
        publicKeyB64: obj['public_key_b64'] as String,
        privateKeyB64: obj['private_key_b64'] as String,
        principalText: obj['principal_text'] as String,
      );
    } finally {
      free(res);
    }
  }

  Future<String?> fetchCandid({required String canisterId, String? host}) async {
    final lib = _open();
    if (lib == null) return null;
    final cid = canisterId.toNativeUtf8();
    final h = host == null ? ffi.nullptr : host.toNativeUtf8();
    try {
      final fn = lib.lookupFunction<_Str2StrNative, _Str2StrDart>(_Symbols.fetchCandid);
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
      pkg_ffi.malloc..free(cid)..free(h);
    }
  }

  String? parseCandid({required String candidText}) {
    final lib = _open();
    if (lib == null) return null;
    final txt = candidText.toNativeUtf8();
    try {
      final fn = lib.lookupFunction<_Str1StrNative, _Str1StrDart>(_Symbols.parseCandid);
      final res = fn(txt.cast());
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      pkg_ffi.malloc.free(txt);
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
    final cid = canisterId.toNativeUtf8();
    final m = method.toNativeUtf8();
    final a = args.toNativeUtf8();
    final h = host == null ? ffi.nullptr : host.toNativeUtf8();
    try {
      final fn = lib.lookupFunction<_CallAnonNative, _CallAnonDart>(_Symbols.callAnonymous);
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
      pkg_ffi.malloc
        ..free(cid)
        ..free(m)
        ..free(a)
        ..free(h);
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
    final cid = canisterId.toNativeUtf8();
    final m = method.toNativeUtf8();
    final a = args.toNativeUtf8();
    final k = privateKeyB64.toNativeUtf8();
    final h = host == null ? ffi.nullptr : host.toNativeUtf8();
    try {
      final fn = lib.lookupFunction<_CallAuthNative, _CallAuthDart>(_Symbols.callAuthenticated);
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
      pkg_ffi.malloc
        ..free(cid)
        ..free(m)
        ..free(a)
        ..free(k)
        ..free(h);
    }
  }

  String? favoritesList() {
    final lib = _open();
    if (lib == null) return null;
    final fn = lib.lookupFunction<_NoargToStringNative, _NoargToStringDart>(_Symbols.favList);
    final res = fn();
    if (res == ffi.nullptr) return null;
    try {
      return res.cast<pkg_ffi.Utf8>().toDartString();
    } finally {
      final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
      free(res);
    }
  }

  String? luaExec({required String script, String? jsonArg}) {
    final lib = _open();
    if (lib == null) return null;
    final s = script.toNativeUtf8();
    final a = jsonArg == null ? ffi.nullptr : jsonArg.toNativeUtf8();
    try {
      final fn = lib.lookupFunction<_Str2StrNative, _Str2StrDart>(_Symbols.luaExec);
      final res = fn(s.cast(), a.cast());
      if (res == ffi.nullptr) return null;
      try {
        return res.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);
        free(res);
      }
    } finally {
      pkg_ffi.malloc
        ..free(s)
        ..free(a);
    }
  }

  int favoritesAdd({required String canisterId, required String method, String? label}) {
    final lib = _open();
    if (lib == null) return -1;
    final cid = canisterId.toNativeUtf8();
    final m = method.toNativeUtf8();
    final l = label == null ? ffi.nullptr : label.toNativeUtf8();
    try {
      final fn = lib.lookupFunction<_FavAddNative, _FavAddDart>(_Symbols.favAdd);
      return fn(cid.cast(), m.cast(), l.cast());
    } finally {
      pkg_ffi.malloc
        ..free(cid)
        ..free(m)
        ..free(l);
    }
  }

  int favoritesRemove({required String canisterId, required String method}) {
    final lib = _open();
    if (lib == null) return -1;
    final cid = canisterId.toNativeUtf8();
    final m = method.toNativeUtf8();
    try {
      final fn = lib.lookupFunction<_FavRemoveNative, _FavRemoveDart>(_Symbols.favRemove);
      return fn(cid.cast(), m.cast());
    } finally {
      pkg_ffi.malloc
        ..free(cid)
        ..free(m);
    }
  }
}

typedef _GenNative =
    ffi.Pointer<ffi.Int8> Function(ffi.Int32, ffi.Pointer<ffi.Int8>);
typedef _GenDart = ffi.Pointer<ffi.Int8> Function(int, ffi.Pointer<ffi.Int8>);

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

typedef _NoargToStringNative = ffi.Pointer<ffi.Int8> Function();
typedef _NoargToStringDart = ffi.Pointer<ffi.Int8> Function();

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

typedef _FavAddNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
typedef _FavAddDart = int Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);

typedef _FavRemoveNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
typedef _FavRemoveDart = int Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
);
