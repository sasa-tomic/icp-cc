/// Web stub for the Rust-core bridge (R-1).
///
/// Selected by [native_bridge.dart]'s conditional export when compiling for the
/// Web. The browser has no `dart:ffi`, no native `libicp_core`, and no libc — so
/// every operation that requires the native core is honestly unavailable and
/// throws [UnsupportedError]. This is a REAL platform implementation (fail-fast),
/// not a mock: it never returns fake/null data. Phase-2 work units (R-2…R-5)
/// will replace these with Web-native equivalents (WebCrypto, WASM QuickJS, …).
library;

import 'native_bridge.dart';

const String _reason =
    'Native core (dart:ffi / libicp_core) is not available on Web — '
    'see R-1 (docs/BROWSER_SUPPORT.md).';

class RustBridgeLoader {
  const RustBridgeLoader();

  RustKeypairResult? generateKeypair({required int alg, String? mnemonic}) =>
      throw UnsupportedError('generateKeypair: $_reason');

  String? principalFromPublicKey(
          {required int alg, required String publicKeyB64}) =>
      throw UnsupportedError('principalFromPublicKey: $_reason');

  String? signMessage({
    required int alg,
    required String messageB64,
    required String privateKeyB64,
  }) =>
      throw UnsupportedError('signMessage: $_reason');

  Future<String?> fetchCandid(
      {required String canisterId, String? host}) async {
    throw UnsupportedError('fetchCandid: $_reason');
  }

  String? parseCandid({required String candidText}) =>
      throw UnsupportedError('parseCandid: $_reason');

  String? callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) =>
      throw UnsupportedError('callAnonymous: $_reason');

  String? callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) =>
      throw UnsupportedError('callAuthenticated: $_reason');

  String? jsExec({required String script, String? jsonArg}) =>
      throw UnsupportedError('jsExec: $_reason');

  String? jsLint({required String script}) =>
      throw UnsupportedError('jsLint: $_reason');

  String? validateJsComprehensive({
    required String script,
    bool isExample = false,
    bool isTest = false,
    bool isProduction = false,
  }) =>
      throw UnsupportedError('validateJsComprehensive: $_reason');

  String? jsAppInit(
      {required String script, String? jsonArg, int budgetMs = 50}) =>
      throw UnsupportedError('jsAppInit: $_reason');

  String? jsAppView(
      {required String script, required String stateJson, int budgetMs = 50}) =>
      throw UnsupportedError('jsAppView: $_reason');

  String? jsAppUpdate(
      {required String script,
      required String msgJson,
      required String stateJson,
      int budgetMs = 50}) =>
      throw UnsupportedError('jsAppUpdate: $_reason');

  EncryptedVaultResult? encryptVault({
    required String password,
    required String plaintextB64,
  }) =>
      throw UnsupportedError('encryptVault: $_reason');

  String? decryptVault({
    required String password,
    required String encryptedDataB64,
    required String saltB64,
    required String nonceB64,
  }) =>
      throw UnsupportedError('decryptVault: $_reason');
}

class NativeBridge {
  String validateJsComprehensive({
    required String script,
    bool isExample = false,
    bool isTest = false,
    bool isProduction = false,
  }) =>
      throw UnsupportedError('validateJsComprehensive: $_reason');

  String? jsExec({required String script, String? jsonArg}) =>
      throw UnsupportedError('jsExec: $_reason');

  String? jsLint({required String script}) =>
      throw UnsupportedError('jsLint: $_reason');
}
