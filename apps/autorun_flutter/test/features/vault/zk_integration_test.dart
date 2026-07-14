// A-4 W5 — Zero-knowledge integration round-trip test.
//
// THE FULL CLIENT → W4 WIRE CONTRACT → STORE → RETRIEVE → CLIENT-DECRYPT PROOF.
//
// This is the acceptance test for the A-4 vault migration: it drives the REAL
// VaultCryptoService (real FFI Argon2id + AES-256-GCM) AND the REAL
// PasskeyService.createVault / getVault body builders, in one coherent flow,
// against a mock HTTP transport that faithfully emulates the W4 opaque-blob
// store. It proves the four ZK properties that make the migration complete:
//
//   1. ROUND-TRIP FIDELITY — encrypt → POST (real service body) → store →
//      GET → decrypt == original plaintext, byte-for-byte.
//   2. CONTRACT SHAPE — request body == {account_id, encrypted_data, salt,
//      nonce} EXACTLY; NO password / data / plaintext key anywhere.
//   3. SERVER-BLINDNESS — the bytes the server holds (the concatenated
//      opaque blob) contain NEITHER the password, the plaintext, NOR any
//      distinctive substring of the plaintext. The server literally cannot
//      read the vault.
//   4. NEGATIVE — wrong password and a tampered STORED blob both fail loud on
//      client decrypt (proves the property survives the round-trip through
//      the wire, complementing W1's raw-crypto negative tests).
//
// ─── HTTP-TRANSPORT HONESTY (AGENTS.md "no false-confidence mocks") ───────────
// The server is PROVABLY a pure opaque-blob store as of A-4 W4. Verified by
//   `rg "encrypt_vault|aes_gcm|Aes256Gcm" backend/src`  →  EMPTY
// (no vault-crypto symbols remain anywhere in backend/src). The W4 handlers
// (backend/src/main.rs vault_create / vault_get / vault_update) only
// base64-decode the four request fields, persist the bytes via the repo, and
// return them verbatim on GET. They perform ZERO crypto and accept NO password
// field.
//
// Therefore the mock transport below loses NO signal: it does byte-identical
// work to the real server (store the four-tuple, echo it back). The
// load-bearing signal — REAL FFI crypto + the EXACT W4 wire contract — runs
// unmodified against the production VaultCryptoService and the production
// PasskeyService body builder. Mocking the HTTP transport is acceptable here
// precisely BECAUSE the server does zero processing on this path; a reader
// must not mistake this for a false-confidence mock.
//
// ─── WHAT THIS ADDS OVER W1 / W2 ─────────────────────────────────────────────
// W1 (vault_crypto_service_test) proves the raw crypto round-trip OFF the wire.
// W2 (passkey_service_vault_test) proves wire-shape fragments in isolation.
// NEITHER unifies both into a single end-to-end proof, and NEITHER asserts the
// server-blindness property on the bytes the server actually holds. This test
// does both. Property 4 is intentionally light here (one test) — the
// exhaustive negative coverage lives in W1.
//
// Guard: skipped when libicp_core cannot be loaded — there is no honest
// fallback for an integration test whose whole point is real end-to-end crypto.

@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/services/vault_crypto_service.dart';
import '../../shared/test_keypair_factory.dart';

const String _password = 'correct horse battery staple';
const String _plaintext = '{"secret":"vault-data","n":42,"note":"ZK"}';
const String _accountId = 'zk-integration-acct';
const Duration _cryptoTimeout = Duration(seconds: 30);

/// The full W7-12 wire-contract body key set for POST/PUT: 5 signature-gate
/// fields + 3 opaque-blob fields. Critically NO `account_id` (resolved
/// server-side from the verified public key). Re-declared here (NOT imported)
/// so a drift in production code is caught by THIS test failing.
const Set<String> _kExpectedBodyKeys = <String>{
  'signature',
  'author_public_key',
  'author_principal',
  'timestamp',
  'nonce', // replay-prevention nonce
  'encrypted_data',
  'salt',
  'blob_nonce', // AES-GCM nonce (renamed from `nonce` in W7-12)
};

/// A faithful emulation of the W7-12 backend as an opaque-blob store: stores
/// the blob from POST/PUT (keyed by the caller's `author_public_key`, exactly
/// as the real backend resolves account_id from the verified public key) and
/// returns those EXACT bytes from POST /vault/get. Performs NO crypto, holds NO
/// password field. See the file header for the honesty rationale.
class _VaultBlobStore {
  // Keyed by author_public_key (the server-resolved account identity).
  final Map<String, _StoredRow> _rows = <String, _StoredRow>{};

  /// Most-recent serialised request body captured (for contract-shape asserts).
  Map<String, dynamic>? lastRequestBody;

  http.Client toClient() => MockClient((request) async {
        final method = request.method;
        final path = request.url.path;

        if (path.endsWith('/api/v1/vault') && (method == 'POST' || method == 'PUT')) {
          final body =
              (jsonDecode(request.body) as Map).cast<String, dynamic>();
          lastRequestBody = body;
          // Strict shape check — mirrors the W7-12 contract; rejects drift loudly.
          final bodyKeys = body.keys.toSet();
          final shapeOk = bodyKeys.length == _kExpectedBodyKeys.length &&
              bodyKeys.every(_kExpectedBodyKeys.contains);
          if (!shapeOk) {
            return _resp(400, {
              'success': false,
              'error': 'bad body shape: ${body.keys.toList()}',
            });
          }
          _rows[body['author_public_key'] as String] = _StoredRow(
            encryptedData: body['encrypted_data'] as String,
            salt: body['salt'] as String,
            nonce: body['blob_nonce'] as String,
          );
          return _resp(200, {'success': true});
        }

        // W7-12: GET became POST /vault/get with a signed body. The caller's
        // identity is the author_public_key in the body (server-side resolution
        // emulated).
        if (path.endsWith('/api/v1/vault/get') && method == 'POST') {
          final body =
              (jsonDecode(request.body) as Map).cast<String, dynamic>();
          final publicKey = body['author_public_key'] as String;
          final row = _rows[publicKey];
          if (row == null) {
            return _resp(404, {
              'success': false,
              'error': 'Vault not found',
            });
          }
          return _resp(200, {
            'success': true,
            'data': {
              'encrypted_data': row.encryptedData,
              'salt': row.salt,
              'nonce': row.nonce,
            },
          });
        }

        return _resp(405, {'success': false, 'error': 'method not allowed'});
      });

  /// The opaque bytes the "server" is currently holding for [publicKey],
  /// decoded from base64 and concatenated. This is the lens through which the
  /// server "sees" the vault. Used by the server-blindness assertions.
  List<int> storedBlobBytesFor(String publicKey) {
    final row = _rows[publicKey];
    if (row == null) {
      throw StateError('no stored row for $publicKey');
    }
    return <int>[
      ...base64.decode(row.encryptedData),
      ...base64.decode(row.salt),
      ...base64.decode(row.nonce),
    ];
  }

  /// Mutate the first byte of the stored ciphertext (simulates a tampered or
  /// corrupted server-side store). Decryption's GCM auth-tag MUST then reject.
  void tamperEncryptedData(String publicKey) {
    final row = _rows[publicKey];
    if (row == null) {
      throw StateError('no stored row for $publicKey');
    }
    final bytes = base64.decode(row.encryptedData);
    bytes[0] = bytes[0] ^ 0xFF;
    _rows[publicKey] = _StoredRow(
      encryptedData: base64.encode(bytes),
      salt: row.salt,
      nonce: row.nonce,
    );
  }
}

class _StoredRow {
  _StoredRow({
    required this.encryptedData,
    required this.salt,
    required this.nonce,
  });
  final String encryptedData;
  final String salt;
  final String nonce;
}

http.Response _resp(int code, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), code);

/// Byte-sublist search: does [haystack] contain [needle] as a contiguous run?
/// Used for the server-blindness assertions (password/plaintext bytes must NOT
/// appear in the server-held blob bytes).
bool _containsSublist(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  if (needle.length > haystack.length) return false;
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

void main() {
  final VaultCryptoService crypto = const VaultCryptoService();
  // Evaluated once at top level so skip-guards are stable across tests; the
  // integration claim has NO honest fallback when the FFI is unavailable.
  final bool nativeAvailable = VaultCryptoService.nativeLibAvailable();
  late _VaultBlobStore store;
  // W7-12: the signature-gated vault routes sign with the active keypair. One
  // real Ed25519 keypair for the whole file (the mock store keys by its
  // publicKey, mirroring the backend's server-side account resolution).
  late ProfileKeypair keypair;

  setUpAll(() async {
    keypair = await TestKeypairFactory.getEd25519Keypair();
  });

  setUp(() {
    store = _VaultBlobStore();
    // PasskeyService is a process-wide singleton; install our blob-store mock
    // as its HTTP transport. Dart test files run sequentially within a file,
    // so no interleaving concern.
    PasskeyService().overrideHttpClient(store.toClient());
  });

  group('A-4 W5 zero-knowledge integration round-trip', () {
    test(
        '1. encrypt → W4 contract → store → retrieve → decrypt == original '
        '(byte-for-byte)', () async {
      if (!nativeAvailable) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }

      // Real PasskeyService.createVault encrypts [plaintext] locally via the
      // REAL VaultCryptoService (heavy Argon2id + AES-256-GCM inside an
      // isolate) and POSTs the opaque blob over the EXACT W4 contract. The
      // blob below is the one that actually crossed the wire — captured from
      // the mock transport, not pre-computed — so this test proves the
      // production service body builder produces a round-trippable blob.
      await PasskeyService().createVault(
        keypair: keypair,
        accountId: _accountId,
        password: _password,
        plaintext: _plaintext,
      ).timeout(_cryptoTimeout);

      final postedBody = store.lastRequestBody;
      expect(postedBody, isNotNull);
      final wireBlob = EncryptedVaultResult(
        encryptedDataB64: postedBody!['encrypted_data'] as String,
        saltB64: postedBody['salt'] as String,
        nonceB64: postedBody['blob_nonce'] as String,
      );

      // Real PasskeyService.getVault retrieves the stored opaque blob back.
      final retrieved = await PasskeyService().getVault(keypair: keypair, accountId: _accountId);
      expect(retrieved, isNotNull, reason: 'GET must return the stored row');

      // Server returned byte-identical blob fields — the W4 opaque-blob
      // guarantee (no transformation, no re-encryption, no truncation).
      expect(retrieved!.encryptedData, equals(wireBlob.encryptedDataB64));
      expect(retrieved.salt, equals(wireBlob.saltB64));
      expect(retrieved.nonce, equals(wireBlob.nonceB64));

      // Client decrypts the retrieved blob locally — must equal the original
      // plaintext byte-for-byte. String equality on the UTF-8-decoded result
      // is equivalent to byte equality of the underlying encodings; asserted
      // explicitly below for clarity.
      final decrypted = await crypto
          .decrypt(password: _password, blob: wireBlob)
          .timeout(_cryptoTimeout);
      expect(decrypted, equals(_plaintext));
      expect(utf8.encode(decrypted), equals(utf8.encode(_plaintext)),
          reason: 'byte-for-byte equality of the recovered plaintext');
    });

    test('2. POST body shape is exactly the W4 contract '
        '(no password / data / plaintext field)', () async {
      if (!nativeAvailable) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }

      await PasskeyService().createVault(
        keypair: keypair,
        accountId: _accountId,
        password: _password,
        plaintext: _plaintext,
      );

      final body = store.lastRequestBody;
      expect(body, isNotNull, reason: 'createVault must POST a JSON body');

      // THE contract: exactly the W7-12 auth + opaque-blob key set.
      expect(
        body!.keys.toSet(),
        equals(_kExpectedBodyKeys),
        reason: 'wire body MUST be exactly the W7-12 auth + opaque-blob keys',
      );
      // W7-12: account_id is NO LONGER in the body (resolved server-side from
      // the verified public key) — the IDOR fix. The caller's public key IS
      // present so the server can resolve the account.
      expect(body.containsKey('account_id'), isFalse,
          reason: 'account_id must NOT be a body field (resolved server-side)');
      expect(body['author_public_key'], equals(keypair.publicKey));

      // Explicit ZK assertions — neither a `password` NOR any plaintext-bearing
      // key may appear in the body's key set.
      expect(body.containsKey('password'), isFalse,
          reason: 'password MUST NOT be a body field');
      expect(body.containsKey('data'), isFalse,
          reason: 'plaintext `data` field MUST NOT exist');
      expect(body.containsKey('plaintext'), isFalse,
          reason: 'plaintext field MUST NOT exist');

      // Belt-and-braces: the raw serialised body string contains NEITHER the
      // password value NOR the plaintext value.
      final serialised = jsonEncode(body);
      expect(serialised.contains(_password), isFalse,
          reason: 'password value MUST NOT appear anywhere in the body');
      expect(serialised.contains(_plaintext), isFalse,
          reason: 'plaintext value MUST NOT leak into the body');
    });

    test('3. SERVER-BLINDNESS: the stored blob is opaque (the ZK property)',
        () async {
      if (!nativeAvailable) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }

      await PasskeyService().createVault(
        keypair: keypair,
        accountId: _accountId,
        password: _password,
        plaintext: _plaintext,
      );

      // The lens through which the server "sees" the vault: the decoded,
      // concatenated opaque bytes it is storing (ciphertext || salt || nonce).
      final blobBytes = store.storedBlobBytesFor(keypair.publicKey);
      expect(blobBytes, isNotEmpty);

      // THE ZK PROPERTY: NONE of the password, the plaintext, or a
      // distinctive substring of the plaintext may appear in the bytes the
      // server holds. If any did, the server could read the vault — defeating
      // the migration. We check at the BYTE level (cryptographically
      // impossible for these ≥21-byte needles to appear by chance in ~70
      // bytes of ciphertext+salt+nonce; short single tokens like the JSON
      // value "ZK" are deliberately excluded to avoid flaky false positives).
      final plaintextJson = jsonDecode(_plaintext) as Map<String, dynamic>;
      final sensitiveByteRuns = <String, List<int>>{
        'password': utf8.encode(_password),
        'plaintext': utf8.encode(_plaintext),
        // A distinctive 21-char JSON key+value pair lifted from the plaintext
        // — represents "contents of the vault" per the W5 spec.
        '"secret":"vault-data"': utf8.encode('"secret":"vault-data"'),
        // The longest standalone value (10 chars) — also "contents".
        'vault-data value': utf8.encode(plaintextJson['secret'].toString()),
      };

      for (final entry in sensitiveByteRuns.entries) {
        expect(
          _containsSublist(blobBytes, entry.value),
          isFalse,
          reason:
              'server-held blob bytes MUST NOT contain the ${entry.key} (ZK violation)',
        );
      }

      // The blob is base64 ciphertext — it must not even be parseable as
      // JSON, let alone decode to the plaintext (catches a catastrophic
      // "store the plaintext as JSON" regression).
      expect(
        () => jsonDecode(String.fromCharCodes(blobBytes)),
        throwsA(isA<FormatException>()),
        reason: 'opaque blob must not be parseable as JSON',
      );
    });

    test('4. NEGATIVE: wrong password + tampered stored blob both fail loud',
        () async {
      if (!nativeAvailable) {
        stdout.writeln('SKIP: libicp_core.so did not load');
        return;
      }

      await PasskeyService().createVault(
        keypair: keypair,
        accountId: _accountId,
        password: _password,
        plaintext: _plaintext,
      );

      // Reconstruct the blob exactly as the production unlock screen would:
      // straight from getVault's bytes.
      final retrieved = await PasskeyService().getVault(keypair: keypair, accountId: _accountId);
      final originalBlob = EncryptedVaultResult(
        encryptedDataB64: retrieved!.encryptedData,
        saltB64: retrieved.salt,
        nonceB64: retrieved.nonce,
      );

      // (a) Wrong password → AES-256-GCM auth-tag rejection (loud throw, no
      // garbage plaintext).
      await expectLater(
        crypto.decrypt(password: 'WRONG password', blob: originalBlob),
        throwsA(isA<VaultDecryptionException>()),
      );

      // (b) Server-side tamper of stored ciphertext → next GET→decrypt MUST
      // fail loud. Proves the GCM integrity property survives the full
      // client→server→client round-trip (complements W1's raw-crypto tamper
      // test, which never crosses the wire).
      store.tamperEncryptedData(keypair.publicKey);
      final tamperedRetrieved = await PasskeyService().getVault(keypair: keypair, accountId: _accountId);
      final tamperedBlob = EncryptedVaultResult(
        encryptedDataB64: tamperedRetrieved!.encryptedData,
        saltB64: tamperedRetrieved.salt,
        nonceB64: tamperedRetrieved.nonce,
      );
      await expectLater(
        crypto.decrypt(password: _password, blob: tamperedBlob),
        throwsA(isA<VaultDecryptionException>()),
      );
    });

    test('GET for a non-existent account returns null (W4 404 contract path)',
        () async {
      // No crypto needed — purely the W4 404 contract branch which the unlock
      // screen's "first-run, no vault yet" UX relies on. Documents that path
      // at the integration level.
      final retrieved = await PasskeyService().getVault(keypair: keypair, accountId: 'never-created-acct');
      expect(retrieved, isNull);
    });
  });
}
