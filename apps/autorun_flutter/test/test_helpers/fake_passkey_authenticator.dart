import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:cbor/cbor.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/pointycastle.dart';

/// Fake WebAuthn authenticator for testing.
///
/// Generates spec-compliant WebAuthn responses that pass backend verification.
/// Based on webauthn-rs SoftPasskey implementation and W3C WebAuthn Level 3 spec.
///
/// Usage:
/// ```dart
/// final fake = FakePasskeyAuthenticator();
///
/// // Registration
/// final regResponse = await fake.register(regRequestFromBackend);
///
/// // Authentication
/// final authResponse = await fake.authenticate(authRequestFromBackend);
/// ```
class FakePasskeyAuthenticator {
  final Map<String, StoredCredential> _credentials = {};
  int _counter = 0;
  final Random _random = Random.secure();

  static final _aaguid = Uint8List.fromList(List.filled(16, 0));

  StoredCredential? getCredential(String credentialId) {
    return _credentials[credentialId];
  }

  void clearCredentials() {
    _credentials.clear();
    _counter = 0;
  }

  /// Generates a WebAuthn registration response.
  Future<FakeRegisterResponse> register(FakeRegisterRequest request) async {
    final credentialId = _generateCredentialId();
    final keyPair = _generateP256KeyPair();

    final clientDataJson = _buildClientDataJson(
      type: 'webauthn.create',
      challenge: request.challenge,
      origin: request.origin,
    );
    final clientDataHash = sha256.convert(utf8.encode(clientDataJson)).bytes;

    final rpIdHash = sha256.convert(utf8.encode(request.rpId)).bytes;

    final ecPublicKey = keyPair.publicKey as ECPublicKey;
    final x = _bigIntToFixedBytes(ecPublicKey.Q!.x!.toBigInteger()!, 32);
    final y = _bigIntToFixedBytes(ecPublicKey.Q!.y!.toBigInteger()!, 32);
    final cosePublicKey = _buildCosePublicKey(x, y);

    final attestedCredData = _buildAttestedCredentialData(
      credentialId: credentialId,
      cosePublicKey: cosePublicKey,
    );

    final authData = _buildAuthenticatorData(
      rpIdHash: rpIdHash,
      flags: AuthFlags.up | AuthFlags.uv | AuthFlags.at,
      signCount: _counter,
      attestedCredentialData: attestedCredData,
    );

    final signatureData = Uint8List.fromList([...authData, ...clientDataHash]);
    final signature = _signES256(keyPair, signatureData);

    final attestationObject = _buildAttestationObject(
      authData: authData,
      signature: signature,
    );

    final credentialIdEncoded = _base64UrlEncode(credentialId);
    final credential = StoredCredential(
      id: credentialIdEncoded,
      keyPair: keyPair,
      rpId: request.rpId,
      userHandle: request.userId,
    );
    _credentials[credentialIdEncoded] = credential;

    return FakeRegisterResponse(
      id: credentialIdEncoded,
      rawId: credentialIdEncoded,
      clientDataJSON: _base64UrlEncode(utf8.encode(clientDataJson)),
      attestationObject: _base64UrlEncode(attestationObject),
      transports: ['internal'],
    );
  }

  /// Generates a WebAuthn authentication response.
  Future<FakeAuthenticateResponse> authenticate(
    FakeAuthenticateRequest request,
  ) async {
    if (request.allowCredentials.isEmpty) {
      throw ArgumentError('No allowed credentials provided');
    }

    final credId = request.allowCredentials.first;
    final credential = _credentials[credId];
    if (credential == null) {
      throw StateError('Credential not found: $credId');
    }

    _counter++;

    final clientDataJson = _buildClientDataJson(
      type: 'webauthn.get',
      challenge: request.challenge,
      origin: request.origin,
    );
    final clientDataHash = sha256.convert(utf8.encode(clientDataJson)).bytes;

    final rpIdHash = sha256.convert(utf8.encode(request.rpId)).bytes;

    final authData = _buildAuthenticatorData(
      rpIdHash: rpIdHash,
      flags: AuthFlags.up | AuthFlags.uv,
      signCount: _counter,
    );

    final signatureData = Uint8List.fromList([...authData, ...clientDataHash]);
    final signature = _signES256(credential.keyPair, signatureData);

    return FakeAuthenticateResponse(
      id: credId,
      rawId: credId,
      clientDataJSON: _base64UrlEncode(utf8.encode(clientDataJson)),
      authenticatorData: _base64UrlEncode(authData),
      signature: _base64UrlEncode(signature),
      userHandle: credential.userHandle.isNotEmpty
          ? _base64UrlEncode(utf8.encode(credential.userHandle))
          : '',
    );
  }

  String _buildClientDataJson({
    required String type,
    required String challenge,
    required String origin,
  }) {
    return jsonEncode({
      'type': type,
      'challenge': challenge,
      'origin': origin,
      'crossOrigin': false,
    });
  }

  Uint8List _buildAuthenticatorData({
    required List<int> rpIdHash,
    required int flags,
    required int signCount,
    Uint8List? attestedCredentialData,
  }) {
    final builder = BytesBuilder();

    builder.add(rpIdHash);
    builder.addByte(flags);
    builder.add(_intToBigEndianBytes(signCount, 4));

    if (attestedCredentialData != null) {
      builder.add(attestedCredentialData);
    }

    return builder.toBytes();
  }

  Uint8List _buildAttestedCredentialData({
    required Uint8List credentialId,
    required Uint8List cosePublicKey,
  }) {
    final builder = BytesBuilder();

    builder.add(_aaguid);
    builder.add(_intToBigEndianBytes(credentialId.length, 2));
    builder.add(credentialId);
    builder.add(cosePublicKey);

    return builder.toBytes();
  }

  Uint8List _buildCosePublicKey(Uint8List x, Uint8List y) {
    final coseKey = CborMap({
      CborSmallInt(1): CborSmallInt(2),
      CborSmallInt(3): CborSmallInt(-7),
      CborSmallInt(-1): CborSmallInt(1),
      CborSmallInt(-2): CborBytes(x),
      CborSmallInt(-3): CborBytes(y),
    });

    return Uint8List.fromList(cborEncode(coseKey));
  }

  Uint8List _buildAttestationObject({
    required Uint8List authData,
    required Uint8List signature,
  }) {
    final attestationObject = CborMap({
      CborString('authData'): CborBytes(authData),
      CborString('fmt'): CborString('packed'),
      CborString('attStmt'): CborMap({
        CborString('alg'): CborSmallInt(-7),
        CborString('sig'): CborBytes(signature),
      }),
    });

    return Uint8List.fromList(cborEncode(attestationObject));
  }

  Uint8List _generateCredentialId() {
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  AsymmetricKeyPair _generateP256KeyPair() {
    final domainParams = ECDomainParameters('secp256r1');
    final keyGen = KeyGenerator('EC');

    final secureRandom = SecureRandom('Fortuna')
      ..seed(KeyParameter(
        Uint8List.fromList(
          List.generate(32, (_) => _random.nextInt(256)),
        ),
      ));

    keyGen.init(ParametersWithRandom(
      ECKeyGeneratorParameters(domainParams),
      secureRandom,
    ));

    return keyGen.generateKeyPair();
  }

  Uint8List _signES256(AsymmetricKeyPair keyPair, Uint8List data) {
    final signer = Signer('SHA-256/DET-ECDSA');
    signer.init(
      true,
      PrivateKeyParameter<PrivateKey>(keyPair.privateKey),
    );

    final signature = signer.generateSignature(data) as ECSignature;

    final r = _bigIntToFixedBytes(signature.r, 32);
    final s = _bigIntToFixedBytes(signature.s, 32);

    return _encodeEcdsaSignatureAsDer(r, s);
  }

  Uint8List _bigIntToFixedBytes(BigInt value, int length) {
    final bytes = Uint8List(length);
    final valueBytes = value.toRadixString(16).padLeft(length * 2, '0');
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(valueBytes.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  Uint8List _encodeEcdsaSignatureAsDer(Uint8List r, Uint8List s) {
    final derR = _encodeDerInteger(r);
    final derS = _encodeDerInteger(s);

    final builder = BytesBuilder();
    builder.add(derR);
    builder.add(derS);
    final sequenceContent = builder.toBytes();
    final sequenceHeader = _encodeDerSequenceHeader(sequenceContent.length);

    return Uint8List.fromList([...sequenceHeader, ...sequenceContent]);
  }

  Uint8List _encodeDerInteger(Uint8List value) {
    var bytes = value;
    if ((bytes.first & 0x80) != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    while (bytes.length > 1 && bytes.first == 0 && (bytes[1] & 0x80) == 0) {
      bytes = Uint8List.sublistView(bytes, 1);
    }
    return Uint8List.fromList([0x02, bytes.length, ...bytes]);
  }

  Uint8List _encodeDerSequenceHeader(int contentLength) {
    if (contentLength < 128) {
      return Uint8List.fromList([0x30, contentLength]);
    } else if (contentLength < 256) {
      return Uint8List.fromList([0x30, 0x81, contentLength]);
    } else {
      return Uint8List.fromList([
        0x30,
        0x82,
        (contentLength >> 8) & 0xFF,
        contentLength & 0xFF,
      ]);
    }
  }

  Uint8List _intToBigEndianBytes(int value, int byteCount) {
    final bytes = Uint8List(byteCount);
    for (int i = 0; i < byteCount; i++) {
      bytes[byteCount - 1 - i] = (value >> (i * 8)) & 0xFF;
    }
    return bytes;
  }

  String _base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class AuthFlags {
  static const int up = 0x01;
  static const int uv = 0x04;
  static const int at = 0x40;
  static const int ed = 0x80;
}

class StoredCredential {
  final String id;
  final AsymmetricKeyPair keyPair;
  final String rpId;
  final String userHandle;

  StoredCredential({
    required this.id,
    required this.keyPair,
    required this.rpId,
    required this.userHandle,
  });
}

class FakeRegisterRequest {
  final String challenge;
  final String rpId;
  final String rpName;
  final String userId;
  final String userName;
  final String userDisplayName;
  final String origin;

  FakeRegisterRequest({
    required this.challenge,
    required this.rpId,
    required this.rpName,
    required this.userId,
    required this.userName,
    required this.userDisplayName,
    required this.origin,
  });

  factory FakeRegisterRequest.fromJson(Map<String, dynamic> json) {
    return FakeRegisterRequest(
      challenge: json['challenge'] as String,
      rpId: json['rp']['id'] as String,
      rpName: json['rp']['name'] as String,
      userId: json['user']['id'] as String,
      userName: json['user']['name'] as String,
      userDisplayName: json['user']['displayName'] as String,
      origin: json['origin'] as String? ?? 'https://${json['rp']['id']}',
    );
  }
}

class FakeRegisterResponse {
  final String id;
  final String rawId;
  final String clientDataJSON;
  final String attestationObject;
  final List<String> transports;

  FakeRegisterResponse({
    required this.id,
    required this.rawId,
    required this.clientDataJSON,
    required this.attestationObject,
    required this.transports,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'rawId': rawId,
        'type': 'public-key',
        'response': {
          'clientDataJSON': clientDataJSON,
          'attestationObject': attestationObject,
          'transports': transports,
        },
      };
}

class FakeAuthenticateRequest {
  final String challenge;
  final String rpId;
  final String origin;
  final List<String> allowCredentials;

  FakeAuthenticateRequest({
    required this.challenge,
    required this.rpId,
    required this.origin,
    required this.allowCredentials,
  });

  factory FakeAuthenticateRequest.fromJson(Map<String, dynamic> json) {
    final allowCreds = (json['allowCredentials'] as List?)
            ?.map((c) => c['id'] as String)
            .toList() ??
        [];

    return FakeAuthenticateRequest(
      challenge: json['challenge'] as String,
      rpId: json['rpId'] as String,
      origin: json['origin'] as String? ?? 'https://${json['rpId']}',
      allowCredentials: allowCreds,
    );
  }
}

class FakeAuthenticateResponse {
  final String id;
  final String rawId;
  final String clientDataJSON;
  final String authenticatorData;
  final String signature;
  final String userHandle;

  FakeAuthenticateResponse({
    required this.id,
    required this.rawId,
    required this.clientDataJSON,
    required this.authenticatorData,
    required this.signature,
    required this.userHandle,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'rawId': rawId,
        'type': 'public-key',
        'response': {
          'clientDataJSON': clientDataJSON,
          'authenticatorData': authenticatorData,
          'signature': signature,
          'userHandle': userHandle,
        },
      };
}
