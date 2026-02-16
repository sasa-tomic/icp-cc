import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cbor/cbor.dart';

import 'fake_passkey_authenticator.dart';

Uint8List _base64UrlDecode(String encoded) {
  String normalized = encoded;
  final paddingNeeded = (4 - (normalized.length % 4)) % 4;
  normalized += '=' * paddingNeeded;
  return base64Url.decode(normalized);
}

void main() {
  group('FakePasskeyAuthenticator', () {
    late FakePasskeyAuthenticator authenticator;

    setUp(() {
      authenticator = FakePasskeyAuthenticator();
    });

    group('registration', () {
      test('generates valid registration response structure', () async {
        final request = FakeRegisterRequest(
          challenge: 'test-challenge-base64url',
          rpId: 'example.com',
          rpName: 'Test App',
          userId: 'user-123',
          userName: 'testuser',
          userDisplayName: 'Test User',
          origin: 'https://example.com',
        );

        final response = await authenticator.register(request);

        expect(response.id, isNotEmpty);
        expect(response.rawId, equals(response.id));
        expect(response.clientDataJSON, isNotEmpty);
        expect(response.attestationObject, isNotEmpty);
        expect(response.transports, contains('internal'));
      });

      test('stores credential after registration', () async {
        final request = FakeRegisterRequest(
          challenge: 'test-challenge',
          rpId: 'example.com',
          rpName: 'Test App',
          userId: 'user-123',
          userName: 'testuser',
          userDisplayName: 'Test User',
          origin: 'https://example.com',
        );

        final response = await authenticator.register(request);

        final credential = authenticator.getCredential(response.id);
        expect(credential, isNotNull);
        expect(credential!.id, equals(response.id));
        expect(credential.rpId, equals('example.com'));
        expect(credential.userHandle, equals('user-123'));
      });

      test('clientDataJSON contains correct fields', () async {
        final request = FakeRegisterRequest(
          challenge: 'dGVzdC1jaGFsbGVuZ2U',
          rpId: 'example.com',
          rpName: 'Test App',
          userId: 'user-123',
          userName: 'testuser',
          userDisplayName: 'Test User',
          origin: 'https://example.com',
        );

        final response = await authenticator.register(request);

        final clientDataJson = utf8.decode(
          _base64UrlDecode(response.clientDataJSON),
        );
        final clientData = jsonDecode(clientDataJson) as Map<String, dynamic>;

        expect(clientData['type'], equals('webauthn.create'));
        expect(clientData['challenge'], equals('dGVzdC1jaGFsbGVuZ2U'));
        expect(clientData['origin'], equals('https://example.com'));
        expect(clientData['crossOrigin'], isFalse);
      });

      test('attestationObject is valid CBOR', () async {
        final request = FakeRegisterRequest(
          challenge: 'test-challenge',
          rpId: 'example.com',
          rpName: 'Test App',
          userId: 'user-123',
          userName: 'testuser',
          userDisplayName: 'Test User',
          origin: 'https://example.com',
        );

        final response = await authenticator.register(request);

        final attestationBytes = _base64UrlDecode(response.attestationObject);
        final attestation = cborDecode(attestationBytes) as CborMap;

        expect(attestation[CborString('fmt')], equals(CborString('packed')));
        expect(attestation[CborString('authData')], isA<CborBytes>());
        expect(attestation[CborString('attStmt')], isA<CborMap>());
      });

      test('attestation statement contains algorithm and signature', () async {
        final request = FakeRegisterRequest(
          challenge: 'test-challenge',
          rpId: 'example.com',
          rpName: 'Test App',
          userId: 'user-123',
          userName: 'testuser',
          userDisplayName: 'Test User',
          origin: 'https://example.com',
        );

        final response = await authenticator.register(request);

        final attestationBytes = _base64UrlDecode(response.attestationObject);
        final attestation = cborDecode(attestationBytes) as CborMap;
        final attStmt = attestation[CborString('attStmt')] as CborMap;

        expect(attStmt[CborString('alg')], equals(CborSmallInt(-7)));
        expect(attStmt[CborString('sig')], isA<CborBytes>());

        final sig = (attStmt[CborString('sig')] as CborBytes).bytes;
        expect(sig[0], equals(0x30));
      });

      test('authenticatorData has correct structure', () async {
        final request = FakeRegisterRequest(
          challenge: 'test-challenge',
          rpId: 'example.com',
          rpName: 'Test App',
          userId: 'user-123',
          userName: 'testuser',
          userDisplayName: 'Test User',
          origin: 'https://example.com',
        );

        final response = await authenticator.register(request);

        final attestationBytes = _base64UrlDecode(response.attestationObject);
        final attestation = cborDecode(attestationBytes) as CborMap;
        final authData =
            (attestation[CborString('authData')] as CborBytes).bytes;

        expect(authData.length, greaterThan(37));

        final rpIdHash = authData.sublist(0, 32);
        expect(rpIdHash.every((b) => b >= 0), isTrue);

        final flags = authData[32];
        expect(flags & AuthFlags.up, equals(AuthFlags.up));
        expect(flags & AuthFlags.uv, equals(AuthFlags.uv));
        expect(flags & AuthFlags.at, equals(AuthFlags.at));
      });

      test('generates unique credential IDs', () async {
        final request = FakeRegisterRequest(
          challenge: 'test-challenge',
          rpId: 'example.com',
          rpName: 'Test App',
          userId: 'user-123',
          userName: 'testuser',
          userDisplayName: 'Test User',
          origin: 'https://example.com',
        );

        final response1 = await authenticator.register(request);
        authenticator.clearCredentials();
        final response2 = await authenticator.register(request);

        expect(response1.id, isNot(equals(response2.id)));
      });

      test('toJson produces valid credential structure', () async {
        final request = FakeRegisterRequest(
          challenge: 'test-challenge',
          rpId: 'example.com',
          rpName: 'Test App',
          userId: 'user-123',
          userName: 'testuser',
          userDisplayName: 'Test User',
          origin: 'https://example.com',
        );

        final response = await authenticator.register(request);
        final json = response.toJson();

        expect(json['id'], isNotEmpty);
        expect(json['rawId'], isNotEmpty);
        expect(json['type'], equals('public-key'));
        expect(json['response']['clientDataJSON'], isNotEmpty);
        expect(json['response']['attestationObject'], isNotEmpty);
      });
    });

    group('authentication', () {
      test('authenticates with registered credential', () async {
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

        final authRequest = FakeAuthenticateRequest(
          challenge: 'auth-challenge',
          rpId: 'example.com',
          origin: 'https://example.com',
          allowCredentials: [regResponse.id],
        );
        final authResponse = await authenticator.authenticate(authRequest);

        expect(authResponse.id, equals(regResponse.id));
        expect(authResponse.rawId, equals(regResponse.id));
        expect(authResponse.clientDataJSON, isNotEmpty);
        expect(authResponse.authenticatorData, isNotEmpty);
        expect(authResponse.signature, isNotEmpty);
      });

      test('clientDataJSON has webauthn.get type', () async {
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

        final authRequest = FakeAuthenticateRequest(
          challenge: 'YXV0aC1jaGFsbGVuZ2U',
          rpId: 'example.com',
          origin: 'https://example.com',
          allowCredentials: [regResponse.id],
        );
        final authResponse = await authenticator.authenticate(authRequest);

        final clientDataJson = utf8.decode(
          _base64UrlDecode(authResponse.clientDataJSON),
        );
        final clientData = jsonDecode(clientDataJson) as Map<String, dynamic>;

        expect(clientData['type'], equals('webauthn.get'));
        expect(clientData['challenge'], equals('YXV0aC1jaGFsbGVuZ2U'));
      });

      test('authenticatorData has correct flags (no AT)', () async {
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

        final authRequest = FakeAuthenticateRequest(
          challenge: 'auth-challenge',
          rpId: 'example.com',
          origin: 'https://example.com',
          allowCredentials: [regResponse.id],
        );
        final authResponse = await authenticator.authenticate(authRequest);

        final authData = _base64UrlDecode(authResponse.authenticatorData);

        expect(authData.length, equals(37));

        final flags = authData[32];
        expect(flags & AuthFlags.up, equals(AuthFlags.up));
        expect(flags & AuthFlags.uv, equals(AuthFlags.uv));
        expect(flags & AuthFlags.at, equals(0));
      });

      test('signature is valid DER format', () async {
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

        final authRequest = FakeAuthenticateRequest(
          challenge: 'auth-challenge',
          rpId: 'example.com',
          origin: 'https://example.com',
          allowCredentials: [regResponse.id],
        );
        final authResponse = await authenticator.authenticate(authRequest);

        final sig = _base64UrlDecode(authResponse.signature);

        expect(sig[0], equals(0x30));
      });

      test('counter increments on authentication', () async {
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

        final authRequest = FakeAuthenticateRequest(
          challenge: 'auth-challenge',
          rpId: 'example.com',
          origin: 'https://example.com',
          allowCredentials: [regResponse.id],
        );

        final auth1 = await authenticator.authenticate(authRequest);
        final auth2 = await authenticator.authenticate(authRequest);

        final authData1 = _base64UrlDecode(auth1.authenticatorData);
        final authData2 = _base64UrlDecode(auth2.authenticatorData);

        final counter1 = (authData1[33] << 24) |
            (authData1[34] << 16) |
            (authData1[35] << 8) |
            authData1[36];
        final counter2 = (authData2[33] << 24) |
            (authData2[34] << 16) |
            (authData2[35] << 8) |
            authData2[36];

        expect(counter2, equals(counter1 + 1));
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

      test('toJson produces valid assertion structure', () async {
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

        final authRequest = FakeAuthenticateRequest(
          challenge: 'auth-challenge',
          rpId: 'example.com',
          origin: 'https://example.com',
          allowCredentials: [regResponse.id],
        );
        final authResponse = await authenticator.authenticate(authRequest);
        final json = authResponse.toJson();

        expect(json['id'], isNotEmpty);
        expect(json['rawId'], isNotEmpty);
        expect(json['type'], equals('public-key'));
        expect(json['response']['clientDataJSON'], isNotEmpty);
        expect(json['response']['authenticatorData'], isNotEmpty);
        expect(json['response']['signature'], isNotEmpty);
      });
    });

    group('credential management', () {
      test('clearCredentials removes all credentials', () async {
        final request = FakeRegisterRequest(
          challenge: 'test-challenge',
          rpId: 'example.com',
          rpName: 'Test App',
          userId: 'user-123',
          userName: 'testuser',
          userDisplayName: 'Test User',
          origin: 'https://example.com',
        );

        final response = await authenticator.register(request);
        expect(authenticator.getCredential(response.id), isNotNull);

        authenticator.clearCredentials();

        expect(authenticator.getCredential(response.id), isNull);
      });
    });

    group('request parsing', () {
      test('FakeRegisterRequest.fromJson parses backend response', () {
        final json = {
          'challenge': 'dGVzdC1jaGFsbGVuZ2U',
          'rp': {'id': 'example.com', 'name': 'Test App'},
          'user': {
            'id': 'dXNlci0xMjM',
            'name': 'testuser',
            'displayName': 'Test User',
          },
        };

        final request = FakeRegisterRequest.fromJson(json);

        expect(request.challenge, equals('dGVzdC1jaGFsbGVuZ2U'));
        expect(request.rpId, equals('example.com'));
        expect(request.rpName, equals('Test App'));
        expect(request.userId, equals('dXNlci0xMjM'));
        expect(request.userName, equals('testuser'));
        expect(request.userDisplayName, equals('Test User'));
        expect(request.origin, equals('https://example.com'));
      });

      test('FakeAuthenticateRequest.fromJson parses backend response', () {
        final json = {
          'challenge': 'YXV0aC1jaGFsbGVuZ2U',
          'rpId': 'example.com',
          'allowCredentials': [
            {'id': 'cred-1', 'type': 'public-key'},
            {'id': 'cred-2', 'type': 'public-key'},
          ],
        };

        final request = FakeAuthenticateRequest.fromJson(json);

        expect(request.challenge, equals('YXV0aC1jaGFsbGVuZ2U'));
        expect(request.rpId, equals('example.com'));
        expect(request.allowCredentials, equals(['cred-1', 'cred-2']));
        expect(request.origin, equals('https://example.com'));
      });

      test('FakeAuthenticateRequest.fromJson handles empty allowCredentials',
          () {
        final json = {
          'challenge': 'YXV0aC1jaGFsbGVuZ2U',
          'rpId': 'example.com',
        };

        final request = FakeAuthenticateRequest.fromJson(json);

        expect(request.allowCredentials, isEmpty);
      });
    });
  });
}
