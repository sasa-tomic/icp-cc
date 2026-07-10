import 'package:flutter_test/flutter_test.dart';

import 'fake_passkey_authenticator.dart';

// TQ-W6-5: this file previously held ~22 tests that asserted on the fake's OWN
// CBOR/DER/authData re-implementation ("mock-the-mock"). Those tests blessed
// the fixture against its own assumptions and inflated pass counts without
// proving anything about real WebAuthn verification — that coverage belongs in
// `passkey_service_vault_test.dart`, which drives the real PasskeyService.
//
// What remains:
//   * ONE structural-shape test exercising the register → store → authenticate
//     round-trip (the fake must actually manage credential state).
//   * The two negative tests pinning the fake's error contract (these are the
//     behaviours other suites rely on: missing credential / empty allow-list).
//
// The `FakeRegisterRequest.fromJson` / `FakeAuthenticateRequest.fromJson`
// parsing paths were only covered here and are consumed nowhere else, so
// dropping their tests loses no signal about real product behaviour.
void main() {
  group('FakePasskeyAuthenticator', () {
    late FakePasskeyAuthenticator authenticator;

    setUp(() {
      authenticator = FakePasskeyAuthenticator();
    });

    test('register stores the credential and authenticate round-trips it',
        () async {
      final regRequest = FakeRegisterRequest(
        challenge: 'reg-challenge',
        rpId: 'example.com',
        rpName: 'Test App',
        userId: 'user-123',
        userName: 'testuser',
        userDisplayName: 'Test User',
        origin: 'https://example.com',
      );
      final regResponse = await authenticator.register(regRequest);

      // Registration response shape.
      expect(regResponse.id, isNotEmpty);
      expect(regResponse.rawId, equals(regResponse.id));
      expect(regResponse.clientDataJSON, isNotEmpty);
      expect(regResponse.attestationObject, isNotEmpty);
      expect(regResponse.transports, contains('internal'));

      // The credential is actually stored under the originating rpId/user.
      final credential = authenticator.getCredential(regResponse.id);
      expect(credential, isNotNull);
      expect(credential!.id, equals(regResponse.id));
      expect(credential.rpId, equals('example.com'));
      expect(credential.userHandle, equals('user-123'));

      // Authentication with the stored credential round-trips the id and
      // produces a complete assertion response.
      final authResponse = await authenticator.authenticate(
        FakeAuthenticateRequest(
          challenge: 'auth-challenge',
          rpId: 'example.com',
          origin: 'https://example.com',
          allowCredentials: [regResponse.id],
        ),
      );
      expect(authResponse.id, equals(regResponse.id));
      expect(authResponse.rawId, equals(regResponse.id));
      expect(authResponse.clientDataJSON, isNotEmpty);
      expect(authResponse.authenticatorData, isNotEmpty);
      expect(authResponse.signature, isNotEmpty);
    });

    test('throws if credential not found', () async {
      final authRequest = FakeAuthenticateRequest(
        challenge: 'auth-challenge',
        rpId: 'example.com',
        origin: 'https://example.com',
        allowCredentials: ['nonexistent-credential'],
      );

      expect(
        () => authenticator.authenticate(authRequest),
        throwsA(isA<StateError>()),
      );
    });

    test('throws if no allowCredentials', () async {
      final authRequest = FakeAuthenticateRequest(
        challenge: 'auth-challenge',
        rpId: 'example.com',
        origin: 'https://example.com',
        allowCredentials: [],
      );

      expect(
        () => authenticator.authenticate(authRequest),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
