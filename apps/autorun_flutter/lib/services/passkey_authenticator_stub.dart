class NativePasskeyAuthenticator {
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    throw UnsupportedError(
        'Passkeys not supported on this platform. Use Web (flutter run -d chrome).');
  }

  Future<Map<String, dynamic>> authenticate(
      Map<String, dynamic> options) async {
    throw UnsupportedError(
        'Passkeys not supported on this platform. Use Web (flutter run -d chrome).');
  }
}
