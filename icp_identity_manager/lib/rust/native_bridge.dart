import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart' as pkg_ffi;

class _Symbols {
  static const String generate = 'icp_generate_identity';
  static const String free = 'icp_free_string';
}

class RustIdentityResult {
  RustIdentityResult({required this.publicKeyB64, required this.privateKeyB64, required this.principalText});
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

    final generate = lib.lookupFunction<_GenNative, _GenDart>(_Symbols.generate);
    final free = lib.lookupFunction<_FreeNative, _FreeDart>(_Symbols.free);

    final ffi.Pointer<pkg_ffi.Utf8> strPtr =
        mnemonic == null ? ffi.nullptr : mnemonic.toNativeUtf8();
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
      final Map<String, dynamic> obj = json.decode(jsonStr) as Map<String, dynamic>;
      return RustIdentityResult(
        publicKeyB64: obj['public_key_b64'] as String,
        privateKeyB64: obj['private_key_b64'] as String,
        principalText: obj['principal_text'] as String,
      );
    } finally {
      free(res);
    }
  }
}

typedef _GenNative = ffi.Pointer<ffi.Int8> Function(ffi.Int32, ffi.Pointer<ffi.Int8>);
typedef _GenDart = ffi.Pointer<ffi.Int8> Function(int, ffi.Pointer<ffi.Int8>);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Int8>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Int8>);
