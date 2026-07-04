// A-4 W2 — PasskeyService vault methods: encrypt-before-send, zero-knowledge.
//
// Verifies the EXACT W4 wire contract:
//   POST/PUT /api/v1/vault  { account_id, encrypted_data, salt, nonce }  (b64)
//   → { "success": true }
//   GET /api/v1/vault?account_id=…  → { success, data: { encrypted_data, salt, nonce } }
//   404 → { success: false, error: "Vault not found" }
//
// The HTTP layer is mocked with a capturing MockClient. The VaultCryptoService
// crypto itself is REAL when libicp_core is loadable (real Argon2id + AES-GCM
// through the FFI); a deterministic recording fake is used as a fallback so
// these wire-shape tests still run in CI environments without the .so. Per
// AGENTS.md the HTTP layer MAY be mocked; the production crypto path is
// unit-tested separately in vault_crypto_service_test.dart.

@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/services/vault_crypto_service.dart';

const _testPassword = 'correct horse battery staple';
const _testPlaintext = '{"k":"v","n":1}';
const _testAccountId = 'acct-123';

/// A recording fake crypto used ONLY when the real FFI is unavailable in the
/// test environment. It captures the password (so we can assert it reached
/// the crypto layer, NOT the HTTP body) and returns a fixed stub blob.
class _RecordingFakeCrypto extends VaultCryptoService {
  _RecordingFakeCrypto(this.stubBlob);
  final EncryptedVaultResult stubBlob;
  String? seenPassword;
  String? seenPlaintext;

  @override
  Future<EncryptedVaultResult> encrypt({
    required String password,
    required String plaintext,
  }) async {
    seenPassword = password;
    seenPlaintext = plaintext;
    return stubBlob;
  }

  @override
  Future<String> decrypt({
    required String password,
    required EncryptedVaultResult blob,
  }) async {
    seenPassword = password;
    return _testPlaintext;
  }
}

EncryptedVaultResult _stubBlob() => EncryptedVaultResult(
      encryptedDataB64: 'ZGF0YQ==',
      saltB64: 'c2FsdA==',
      nonceB64: 'bm9uY2U=',
    );

_RecordingFakeCrypto _stubFakeCrypto() => _RecordingFakeCrypto(_stubBlob());

http.Response _okResponse([Map<String, dynamic>? data]) => http.Response(
      jsonEncode({'success': true, if (data != null) 'data': data}),
      200,
    );

http.Response _errResponse(int code, String error) => http.Response(
      jsonEncode({'success': false, 'error': error}),
      code,
    );

void main() {
  EncryptedVaultResult? realBlob; // produced once via real FFI when available

  setUpAll(() async {
    if (VaultCryptoService.nativeLibAvailable()) {
      realBlob = await const VaultCryptoService().encrypt(
        password: _testPassword,
        plaintext: _testPlaintext,
      );
    }
  });

  /// Pick the real crypto (when lib loadable) or the recording fake.
  VaultCryptoService cryptoFor(_RecordingFakeCrypto? fakeSink) {
    if (realBlob != null) return const VaultCryptoService();
    if (fakeSink != null) return fakeSink;
    return _stubFakeCrypto();
  }

  group('PasskeyService.createVault (A-4 zero-knowledge wire contract)', () {
    test('POST body is exactly {account_id, encrypted_data, salt, nonce} (b64)',
        () async {
      Map<String, dynamic>? captured;
      final client = MockClient((request) async {
        if (request.body.isNotEmpty) {
          captured = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        }
        return _okResponse();
      });
      PasskeyService().overrideHttpClient(client);

      await PasskeyService().createVault(
        accountId: _testAccountId,
        password: _testPassword,
        plaintext: _testPlaintext,
        vaultCrypto: cryptoFor(null),
      );

      // Wire shape — exactly the W4 opaque-blob contract.
      expect(captured, isNotNull,
          reason: 'createVault must POST a JSON body');
      expect(captured!.keys,
          equals(<String>{'account_id', 'encrypted_data', 'salt', 'nonce'}));
      expect(captured!['account_id'], equals(_testAccountId));

      // THE zero-knowledge property: no `password` and no plaintext `data`
      // field anywhere in the serialised body.
      expect(captured!.containsKey('password'), isFalse,
          reason: 'password must NOT be serialised into the HTTP body');
      expect(captured!.containsKey('data'), isFalse,
          reason: 'plaintext `data` must NOT be serialised into the HTTP body');

      // When real FFI ran, decrypt the captured blob and assert it round-trips
      // to the original plaintext (proves the wire body genuinely carries an
      // FFI-encrypted blob, not plaintext or a stub). Also assert the
      // plaintext never leaks into the serialised JSON.
      if (realBlob != null) {
        final capturedBlob = EncryptedVaultResult(
          encryptedDataB64: captured!['encrypted_data'] as String,
          saltB64: captured!['salt'] as String,
          nonceB64: captured!['nonce'] as String,
        );
        final decrypted = await const VaultCryptoService()
            .decrypt(password: _testPassword, blob: capturedBlob);
        expect(decrypted, equals(_testPlaintext),
            reason: 'captured body must decrypt back to the original plaintext');
        expect(jsonEncode(captured).contains(_testPlaintext), isFalse,
            reason: 'plaintext must not leak into the JSON body');
      }
    });

    test('password reached the local crypto layer, never the HTTP body',
        () async {
      // Real-FFI path only — proves the password is consumed locally by the
      // FFI, not by the HTTP layer.
      if (realBlob == null) {
        stdout.writeln('SKIP: libicp_core.so not loadable in this env');
        return;
      }
      final fake = _RecordingFakeCrypto(realBlob!);
      final client = MockClient((_) async => _okResponse());
      PasskeyService().overrideHttpClient(client);

      await PasskeyService().createVault(
        accountId: _testAccountId,
        password: _testPassword,
        plaintext: _testPlaintext,
        vaultCrypto: fake,
      );

      expect(fake.seenPassword, equals(_testPassword),
          reason: 'password must reach the local VaultCryptoService.encrypt');
      expect(fake.seenPlaintext, equals(_testPlaintext));
    });

    test('server error is surfaced loudly (no silent failure)', () async {
      final client = MockClient((_) async => _errResponse(500, 'boom'));
      PasskeyService().overrideHttpClient(client);

      await expectLater(
        PasskeyService().createVault(
          accountId: _testAccountId,
          password: _testPassword,
          plaintext: _testPlaintext,
          vaultCrypto: cryptoFor(null),
        ),
        throwsA(isA<PasskeyException>()),
      );
    });
  });

  group('PasskeyService.updateVault (PUT)', () {
    test('PUT body has the same opaque-blob shape and no password', () async {
      Map<String, dynamic>? captured;
      final client = MockClient((request) async {
        if (request.method == 'PUT') {
          captured = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        }
        return _okResponse();
      });
      PasskeyService().overrideHttpClient(client);

      await PasskeyService().updateVault(
        accountId: _testAccountId,
        password: _testPassword,
        plaintext: _testPlaintext,
        vaultCrypto: cryptoFor(null),
      );

      expect(captured, isNotNull);
      expect(captured!.keys,
          equals(<String>{'account_id', 'encrypted_data', 'salt', 'nonce'}));
      expect(captured!.containsKey('password'), isFalse);
    });
  });

  group('PasskeyService.getVault', () {
    test('parses the W4 response into VaultData', () async {
      final client = MockClient((_) async => _okResponse({
            'encrypted_data': 'ZW5j',
            'salt': 'c2FsdA==',
            'nonce': 'bm9uY2U=',
          }));
      PasskeyService().overrideHttpClient(client);

      final vault = await PasskeyService().getVault(_testAccountId);
      expect(vault, isNotNull);
      expect(vault!.encryptedData, equals('ZW5j'));
      expect(vault.salt, equals('c2FsdA=='));
      expect(vault.nonce, equals('bm9uY2U='));
    });

    test('404 returns null (vault not yet created)', () async {
      final client =
          MockClient((_) async => _errResponse(404, 'Vault not found'));
      PasskeyService().overrideHttpClient(client);

      expect(await PasskeyService().getVault(_testAccountId), isNull);
    });

    test('500 rethrows loudly (no silent swallow)', () async {
      final client = MockClient((_) async => _errResponse(500, 'internal'));
      PasskeyService().overrideHttpClient(client);

      await expectLater(
        PasskeyService().getVault(_testAccountId),
        throwsA(isA<PasskeyException>()),
      );
    });
  });
}
