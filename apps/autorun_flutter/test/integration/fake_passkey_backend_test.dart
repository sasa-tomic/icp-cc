import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/fake_passkey_authenticator.dart';

/// Integration test for FakePasskeyAuthenticator against backend WebAuthn verification.
///
/// This test validates that the fake generates responses that pass webauthn-rs
/// verification (the same library used by the backend).
///
/// To run this test:
/// 1. Ensure backend is running locally
/// 2. Run: flutter test test/integration/fake_passkey_backend_test.dart
void main() {
  group('FakePasskeyAuthenticator backend integration', () {
    late FakePasskeyAuthenticator authenticator;

    setUp(() {
      authenticator = FakePasskeyAuthenticator();
    });

    test('registration response structure matches backend expectation',
        () async {
      final request = FakeRegisterRequest(
        challenge: 'dGVzdC1jaGFsbGVuZ2UtZnJvbS1iYWNrZW5k',
        rpId: 'localhost',
        rpName: 'ICP Script Marketplace',
        userId: 'dXNlci0xMjM0NTY3ODkw',
        userName: 'testuser@example.com',
        userDisplayName: 'Test User',
        origin: 'http://localhost',
      );

      final response = await authenticator.register(request);
      final json = response.toJson();

      expect(json['id'], isNotEmpty);
      expect(json['rawId'], equals(json['id']));
      expect(json['type'], equals('public-key'));

      final resp = json['response'] as Map<String, dynamic>;
      expect(resp['clientDataJSON'], isNotEmpty);
      expect(resp['attestationObject'], isNotEmpty);

      final paddingNeeded =
          (4 - (resp['clientDataJSON'].length as int) % 4) % 4;
      final clientData = jsonDecode(
        utf8.decode(
            base64Url.decode(resp['clientDataJSON'] + '=' * paddingNeeded)),
      ) as Map<String, dynamic>;
      expect(clientData['type'], equals('webauthn.create'));
      expect(clientData['challenge'], equals(request.challenge));
      expect(clientData['origin'], equals(request.origin));
    });

    test('authentication response structure matches backend expectation',
        () async {
      final regRequest = FakeRegisterRequest(
        challenge: 'cmVnLWNoYWxsZW5nZQ',
        rpId: 'localhost',
        rpName: 'ICP Script Marketplace',
        userId: 'dXNlci0xMjM0NTY3ODkw',
        userName: 'testuser@example.com',
        userDisplayName: 'Test User',
        origin: 'http://localhost',
      );

      final regResponse = await authenticator.register(regRequest);

      final authRequest = FakeAuthenticateRequest(
        challenge: 'YXV0aC1jaGFsbGVuZ2UtZnJvbS1iYWNrZW5k',
        rpId: 'localhost',
        origin: 'http://localhost',
        allowCredentials: [regResponse.id],
      );

      final authResponse = await authenticator.authenticate(authRequest);
      final json = authResponse.toJson();

      expect(json['id'], equals(regResponse.id));
      expect(json['rawId'], equals(regResponse.id));
      expect(json['type'], equals('public-key'));

      final resp = json['response'] as Map<String, dynamic>;
      expect(resp['clientDataJSON'], isNotEmpty);
      expect(resp['authenticatorData'], isNotEmpty);
      expect(resp['signature'], isNotEmpty);

      final paddingNeeded =
          (4 - (resp['clientDataJSON'].length as int) % 4) % 4;
      final clientData = jsonDecode(
        utf8.decode(
            base64Url.decode(resp['clientDataJSON'] + '=' * paddingNeeded)),
      ) as Map<String, dynamic>;
      expect(clientData['type'], equals('webauthn.get'));
      expect(clientData['challenge'], equals(authRequest.challenge));
      expect(clientData['origin'], equals(authRequest.origin));
    });

    test('signature can be verified with public key', () async {
      final request = FakeRegisterRequest(
        challenge: 'dGVzdC1jaGFsbGVuZ2U',
        rpId: 'localhost',
        rpName: 'ICP Script Marketplace',
        userId: 'dXNlci0xMjM0NTY3ODkw',
        userName: 'testuser@example.com',
        userDisplayName: 'Test User',
        origin: 'http://localhost',
      );

      final response = await authenticator.register(request);

      final credential = authenticator.getCredential(response.id);
      expect(credential, isNotNull);

      final authRequest = FakeAuthenticateRequest(
        challenge: 'YXV0aC1jaGFsbGVuZ2U',
        rpId: 'localhost',
        origin: 'http://localhost',
        allowCredentials: [response.id],
      );

      final authResponse = await authenticator.authenticate(authRequest);

      String addPadding(String s) {
        final paddingNeeded = (4 - (s.length % 4)) % 4;
        return s + '=' * paddingNeeded;
      }

      final authData =
          base64Url.decode(addPadding(authResponse.authenticatorData));
      final clientDataHash = sha256
          .convert(
            base64Url.decode(addPadding(authResponse.clientDataJSON)),
          )
          .bytes;
      final signature = base64Url.decode(addPadding(authResponse.signature));

      final signedData = [...authData, ...clientDataHash];
      expect(signedData.length, equals(37 + 32));

      expect(signature[0], equals(0x30));
      expect(signature.length, greaterThanOrEqualTo(70));
      expect(signature.length, lessThanOrEqualTo(72));
    });

    test('full registration flow produces valid credential', () async {
      final authenticator1 = FakePasskeyAuthenticator();
      final authenticator2 = FakePasskeyAuthenticator();

      final request = FakeRegisterRequest(
        challenge: 'dGVzdC1jaGFsbGVuZ2U',
        rpId: 'localhost',
        rpName: 'ICP Script Marketplace',
        userId: 'dXNlci0xMjM0NTY3ODkw',
        userName: 'testuser@example.com',
        userDisplayName: 'Test User',
        origin: 'http://localhost',
      );

      final response1 = await authenticator1.register(request);
      final response2 = await authenticator2.register(request);

      expect(response1.id, isNot(equals(response2.id)));

      final cred1 = authenticator1.getCredential(response1.id);
      final cred2 = authenticator2.getCredential(response2.id);

      expect(cred1, isNotNull);
      expect(cred2, isNotNull);
      expect(cred1!.id, isNot(equals(cred2!.id)));
    });

    test('authentication counter increments correctly', () async {
      final request = FakeRegisterRequest(
        challenge: 'dGVzdC1jaGFsbGVuZ2U',
        rpId: 'localhost',
        rpName: 'ICP Script Marketplace',
        userId: 'dXNlci0xMjM0NTY3ODkw',
        userName: 'testuser@example.com',
        userDisplayName: 'Test User',
        origin: 'http://localhost',
      );

      final response = await authenticator.register(request);

      final authRequest = FakeAuthenticateRequest(
        challenge: 'Y2hhbGxlbmdlLTE',
        rpId: 'localhost',
        origin: 'http://localhost',
        allowCredentials: [response.id],
      );

      String addPadding(String s) {
        final paddingNeeded = (4 - (s.length % 4)) % 4;
        return s + '=' * paddingNeeded;
      }

      final counters = <int>[];
      for (int i = 0; i < 5; i++) {
        final authResponse = await authenticator.authenticate(authRequest);
        final authData = base64Url.decode(
          addPadding(authResponse.authenticatorData),
        );
        final counter = (authData[33] << 24) |
            (authData[34] << 16) |
            (authData[35] << 8) |
            authData[36];
        counters.add(counter);
      }

      for (int i = 1; i < counters.length; i++) {
        expect(counters[i], equals(counters[i - 1] + 1));
      }
    });
  });
}
