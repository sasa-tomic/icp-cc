import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

class NativePasskeyAuthenticator {
  final PasskeyAuthenticator _auth = PasskeyAuthenticator();

  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    final credential =
        await _auth.register(RegisterRequestType.fromJson(options));
    return credential.toJson();
  }

  Future<Map<String, dynamic>> authenticate(
      Map<String, dynamic> options) async {
    final credential =
        await _auth.authenticate(AuthenticateRequestType.fromJson(options));
    return credential.toJson();
  }
}
