/// libc `setenv` via FFI — IO platforms only.
library;

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/foundation.dart' show debugPrint;

bool setProcessEnvImpl(String name, String value) {
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
      return setenv(namePtr, valuePtr, 1) == 0;
    } finally {
      pkg_ffi.calloc.free(namePtr);
      pkg_ffi.calloc.free(valuePtr);
    }
  } catch (e) {
    debugPrint('libc_setenv: setenv failed for $name: $e');
    return false;
  }
}
