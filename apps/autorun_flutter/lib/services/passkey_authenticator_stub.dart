class NativePasskeyAuthenticator {
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    throw UnsupportedError(
        'Passkeys are not available on this platform. Use the app on macOS, Windows, or Android.');
  }

  Future<Map<String, dynamic>> authenticate(
      Map<String, dynamic> options) async {
    throw UnsupportedError(
        'Passkeys are not available on this platform. Use the app on macOS, Windows, or Android.');
  }
}
