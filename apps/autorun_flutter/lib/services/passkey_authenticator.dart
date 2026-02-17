export 'passkey_authenticator_stub.dart'
    if (dart.library.html) 'passkey_authenticator_native.dart'
    if (dart.library.io) 'passkey_authenticator_native.dart';
