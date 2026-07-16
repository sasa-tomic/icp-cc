import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'account_signature_service.dart';
import 'passkey_authenticator.dart';
import 'vault_crypto_service.dart';
import 'api_routes.dart';
import '../models/profile_keypair.dart';
import '../utils/passkey_platform.dart';
import '../utils/principal.dart';
import '../rust/native_bridge.dart';
import '../theme/app_design_system.dart';

// ─── A-4 vault wire-contract field names (single-source-of-truth) ───────────
// These are the JSON keys for /api/v1/vault, byte-identical to the W4 backend
// handlers in backend/src/handlers/vault.rs. Defined ONCE here; both createVault
// and updateVault build their bodies via _vaultRequestBody below. The password is
// intentionally NOT in this list — A-4 zero-knowledge: the server never sees
// the password (it stays on-device, consumed only by VaultCryptoService FFI).
//
// W7-12: the AES-GCM nonce field is `blob_nonce` on the wire (renamed from
// `nonce` to avoid clashing with the replay-prevention `nonce` auth field).
const String kVaultFieldEncryptedData = 'encrypted_data';
const String kVaultFieldSalt = 'salt';
const String kVaultFieldBlobNonce = 'blob_nonce';

// ─── W7-12..14 signature-gate action names (single-source-of-truth) ─────────
// Mirrored EXACTLY by the backend consts in each handler. Both sides bake this
// string into the canonical payload; a mismatch → 401.
const String kVaultCreateAction = 'vault:create';
const String kVaultUpdateAction = 'vault:update';
const String kVaultGetAction = 'vault:get';
const String kPasskeyRegisterAction = 'passkey:register';
const String kPasskeyDeleteAction = 'passkey:delete';
const String kRecoveryGenerateAction = 'recovery:generate';

class PasskeyService {
  static final PasskeyService _instance = PasskeyService._internal();
  factory PasskeyService() => _instance;
  PasskeyService._internal() : _httpClient = http.Client();

  String get _baseUrl => ApiRoutes.base;
  static final Duration _timeout = AppDurations.networkRequest;
  http.Client _httpClient;
  final NativePasskeyAuthenticator _authenticator =
      NativePasskeyAuthenticator();

  @visibleForTesting
  void overrideHttpClient(http.Client client) => _httpClient = client;

  static const _uuid = Uuid();

  /// Builds the five signature-gate fields for an account-scoped request
  /// (W7-12..14), signing the canonical payload `{action, account_id, ...extra,
  /// nonce, ts}` with the caller's Ed25519 keypair. The backend resolves
  /// `account_id` SERVER-SIDE from [keypair.publicKey] and verifies the
  /// signature over the identical canonical bytes.
  ///
  /// [action] MUST be one of the `k*Action` consts above (single source shared
  /// with the backend). [extraFields] carries any business fields bound into
  /// the signature (none for vault; the wire body carries the opaque blob
  /// separately).
  static Future<_SignedAccountFields> _signAccountRequest({
    required ProfileKeypair keypair,
    required String action,
    Map<String, dynamic> extraFields = const {},
    int? timestamp,
    String? nonce,
  }) async {
    final ts = timestamp ??
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final resolvedNonce = nonce ?? _uuid.v4();
    final payload = <String, dynamic>{
      'action': action,
      ...extraFields,
      'nonce': resolvedNonce,
      'ts': ts,
    };
    final signature = await AccountSignatureService.signCanonicalPayload(
      keypair: keypair,
      payload: payload,
    );
    return _SignedAccountFields(
      signature: signature,
      authorPublicKey: keypair.publicKey,
      authorPrincipal: PrincipalUtils.textFromRecord(keypair),
      timestamp: ts,
      nonce: resolvedNonce,
    );
  }

  Future<PasskeyRegistrationResult> registerPasskey({
    required ProfileKeypair keypair,
    required String accountId,
    required String username,
    String? deviceName,
  }) async {
    if (!PasskeyPlatform.isSupported) {
      throw PasskeyException(
          "Passkeys aren't available on this platform. Use the app on macOS, Windows, or Android.");
    }

    // W7-13: signature-gated. The backend resolves accountId from the verified
    // public key and binds the new credential to that proven owner — closing
    // the account-takeover exploit where anyone could enrol their authenticator
    // on any account.
    final startAuth = await _signAccountRequest(
      keypair: keypair,
      action: kPasskeyRegisterAction,
      extraFields: {'account_id': accountId},
    );
    final startResponse = await _post('/passkey/register/start', {
      'username': username,
      'signature': startAuth.signature,
      'author_public_key': startAuth.authorPublicKey,
      'author_principal': startAuth.authorPrincipal,
      'timestamp': startAuth.timestamp,
      'nonce': startAuth.nonce,
    });
    final options = startResponse['data'];
    final challengeId = options['challenge_id'] as String;
    final webAuthnOptions = options['options'] as Map<String, dynamic>;

    final credential = await _authenticator.register(webAuthnOptions);

    final finishResponse = await _post('/passkey/register/finish', {
      'challenge_id': challengeId,
      'credential': credential,
      'device_name': deviceName,
      'device_type': _getPlatformDeviceType(),
    });

    return PasskeyRegistrationResult.fromJson(finishResponse['data']);
  }

  Future<PasskeyAuthResult> authenticateWithPasskey({
    required String accountId,
  }) async {
    if (!PasskeyPlatform.isSupported) {
      throw PasskeyException(
          "Passkeys aren't available on this platform. Use the app on macOS, Windows, or Android.");
    }

    final startResponse = await _post('/passkey/authenticate/start', {
      'account_id': accountId,
    });
    final options = startResponse['data'];
    final challengeId = options['challenge_id'] as String;
    final webAuthnOptions = options['options'] as Map<String, dynamic>;

    final credential = await _authenticator.authenticate(webAuthnOptions);

    final finishResponse = await _post('/passkey/authenticate/finish', {
      'challenge_id': challengeId,
      'credential': credential,
    });

    return PasskeyAuthResult(
      accountId: finishResponse['data']['account_id'] as String,
    );
  }

  Future<List<PasskeyInfo>> listPasskeys(String accountId) async {
    final response = await _get('/passkey/list/$accountId');
    final data = response['data'] as List;
    return data.map((p) => PasskeyInfo.fromJson(p)).toList();
  }

  Future<void> deletePasskey({
    required ProfileKeypair keypair,
    required String accountId,
    required String passkeyId,
  }) async {
    // W7-13: signature-gated. The backend resolves accountId from the verified
    // public key and scopes the delete to that account — only the owner can
    // delete their passkey.
    final auth = await _signAccountRequest(
      keypair: keypair,
      action: kPasskeyDeleteAction,
      extraFields: {'passkey_id': passkeyId, 'account_id': accountId},
    );
    await _delete('/passkey/$passkeyId', body: {
      'signature': auth.signature,
      'author_public_key': auth.authorPublicKey,
      'author_principal': auth.authorPrincipal,
      'timestamp': auth.timestamp,
      'nonce': auth.nonce,
    });
  }

  /// W7-14: signature-gated. The caller proves ownership of an account keypair;
  /// the backend resolves accountId from the verified public key and mints the
  /// plaintext codes for THAT account only. Closes the exploit where anyone
  /// could mint+receive plaintext codes for ANY account (W7-005).
  Future<RecoveryCodesResult> generateRecoveryCodes({
    required ProfileKeypair keypair,
    required String accountId,
  }) async {
    final auth = await _signAccountRequest(
      keypair: keypair,
      action: kRecoveryGenerateAction,
      extraFields: {'account_id': accountId},
    );
    final response = await _post('/recovery/generate', {
      'signature': auth.signature,
      'author_public_key': auth.authorPublicKey,
      'author_principal': auth.authorPrincipal,
      'timestamp': auth.timestamp,
      'nonce': auth.nonce,
    });
    return RecoveryCodesResult.fromJson(response['data']);
  }

  Future<bool> verifyRecoveryCode({
    required String accountId,
    required String code,
  }) async {
    final response = await _post('/recovery/verify', {
      'account_id': accountId,
      'code': code,
    });
    return response['data']['valid'] as bool;
  }

  Future<int> getRecoveryCodeStatus(String accountId) async {
    final response = await _get('/recovery/status/$accountId');
    return response['data']['remaining_codes'] as int;
  }

  /// Creates a vault on the server as an OPAQUE BLOB (A-4 zero-knowledge).
  ///
  /// [plaintext] is encrypted locally via [VaultCryptoService] BEFORE the
  /// network call; [password] is consumed only by the local FFI and is NEVER
  /// serialised into the request body (the server cannot decrypt — it just
  /// stores the opaque `encrypted_data`/`salt`/`blob_nonce` triple).
  ///
  /// W7-12: signature-gated. [keypair] proves ownership of the account; the
  /// backend resolves `accountId` from its public key (the body's id is
  /// ignored) and verifies an Ed25519 signature over the canonical
  /// `{action:"vault:create", account_id, nonce, ts}` payload. Closes the
  /// overwrite-anyone's-vault IDOR (W7-003).
  Future<void> createVault({
    required ProfileKeypair keypair,
    required String accountId,
    required String password,
    required String plaintext,
    VaultCryptoService vaultCrypto = const VaultCryptoService(),
  }) async {
    final blob = await vaultCrypto.encrypt(
      password: password,
      plaintext: plaintext,
    );
    final auth = await _signAccountRequest(
      keypair: keypair,
      action: kVaultCreateAction,
      extraFields: {'account_id': accountId},
    );
    await _post('/vault', _vaultRequestBody(auth, blob));
  }

  /// Signature-gated vault read (W7-12). Returns the opaque blob for the
  /// account bound to [keypair], or `null` if no vault exists yet (backend 404
  /// → typed `PasskeyException.statusCode == 404`). The blob is ciphertext-only
  /// (zero-knowledge); the gate is defense-in-depth + uniformity with the other
  /// vault routes.
  Future<VaultData?> getVault({
    required ProfileKeypair keypair,
    required String accountId,
  }) async {
    try {
      final auth = await _signAccountRequest(
        keypair: keypair,
        action: kVaultGetAction,
        extraFields: {'account_id': accountId},
      );
      final response = await _post('/vault/get', _vaultGetRequestBody(auth));
      return VaultData.fromJson(response['data']);
    } on PasskeyException catch (e) {
      // Typed status-code check (not string-matching the message): the vault
      // legitimately doesn't exist yet for first-time users, which the backend
      // signals with 404. Any other failure is a real error → rethrow.
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Updates the server-side vault blob (A-4 zero-knowledge). Same contract
  /// as [createVault] but PUT; signature-gated (W7-12). The password again
  /// never leaves the device.
  Future<void> updateVault({
    required ProfileKeypair keypair,
    required String accountId,
    required String password,
    required String plaintext,
    VaultCryptoService vaultCrypto = const VaultCryptoService(),
  }) async {
    final blob = await vaultCrypto.encrypt(
      password: password,
      plaintext: plaintext,
    );
    final auth = await _signAccountRequest(
      keypair: keypair,
      action: kVaultUpdateAction,
      extraFields: {'account_id': accountId},
    );
    await _put('/vault', _vaultRequestBody(auth, blob));
  }

  /// Builds the opaque-blob request body for createVault/updateVault (auth
  /// fields + the opaque blob). Defined ONCE so the wire shape drifts in one
  /// place.
  static Map<String, dynamic> _vaultRequestBody(
    _SignedAccountFields auth,
    EncryptedVaultResult blob,
  ) {
    return <String, dynamic>{
      'signature': auth.signature,
      'author_public_key': auth.authorPublicKey,
      'author_principal': auth.authorPrincipal,
      'timestamp': auth.timestamp,
      'nonce': auth.nonce,
      kVaultFieldEncryptedData: blob.encryptedDataB64,
      kVaultFieldSalt: blob.saltB64,
      kVaultFieldBlobNonce: blob.nonceB64,
    };
  }

  static Map<String, dynamic> _vaultGetRequestBody(_SignedAccountFields auth) {
    return <String, dynamic>{
      'signature': auth.signature,
      'author_public_key': auth.authorPublicKey,
      'author_principal': auth.authorPrincipal,
      'timestamp': auth.timestamp,
      'nonce': auth.nonce,
    };
  }

  String _getPlatformDeviceType() {
    if (kIsWeb) return 'cross-platform';
    return 'platform';
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response =
        await _httpClient.get(Uri.parse('$_baseUrl$path')).timeout(_timeout);
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final response = await _httpClient
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> _put(
      String path, Map<String, dynamic> body) async {
    final response = await _httpClient
        .put(
          Uri.parse('$_baseUrl$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return _handleResponse(response);
  }

  Future<void> _delete(String path, {Map<String, dynamic>? body}) async {
    final request = http.Request('DELETE', Uri.parse('$_baseUrl$path'))
      ..headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    final streamedResponse = await _httpClient.send(request).timeout(_timeout);
    final response = await http.Response.fromStream(streamedResponse);
    _handleResponse(response);
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _tryParseError(response.body);
      throw PasskeyException('HTTP ${response.statusCode}: $error',
          statusCode: response.statusCode);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw PasskeyException(data['error']?.toString() ?? 'Request failed');
    }
    return data;
  }

  String _tryParseError(String body) {
    try {
      final json = jsonDecode(body);
      return json['error']?.toString() ?? body;
    } on FormatException catch (e) {
      debugPrint('PasskeyService._tryParseError: body is not JSON: $e');
      return body;
    }
  }
}

class PasskeyException implements Exception {
  final String message;

  /// HTTP status code when this exception originated from an HTTP response
  /// (null for non-HTTP failures such as platform-unsupported or
  /// `success != true` body errors). Enables a typed status-code check (e.g.
  /// [PasskeyService.getVault] treats 404 as "vault not yet created") instead
  /// of fragile message-string matching.
  final int? statusCode;

  PasskeyException(this.message, {this.statusCode});
  @override
  String toString() => 'PasskeyException: $message';
}

class PasskeyRegistrationResult {
  final String id;
  final String? deviceName;
  final String? deviceType;
  final String createdAt;

  PasskeyRegistrationResult({
    required this.id,
    this.deviceName,
    this.deviceType,
    required this.createdAt,
  });

  factory PasskeyRegistrationResult.fromJson(Map<String, dynamic> json) {
    return PasskeyRegistrationResult(
      id: json['id'] as String,
      deviceName: json['device_name'] as String?,
      deviceType: json['device_type'] as String?,
      createdAt: json['created_at'] as String,
    );
  }
}

class PasskeyAuthResult {
  final String accountId;
  PasskeyAuthResult({required this.accountId});
}

class PasskeyInfo {
  final String id;
  final String? deviceName;
  final String? deviceType;
  final String createdAt;
  final String? lastUsedAt;

  PasskeyInfo({
    required this.id,
    this.deviceName,
    this.deviceType,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory PasskeyInfo.fromJson(Map<String, dynamic> json) {
    return PasskeyInfo(
      id: json['id'] as String,
      deviceName: json['device_name'] as String?,
      deviceType: json['device_type'] as String?,
      createdAt: json['created_at'] as String,
      lastUsedAt: json['last_used_at'] as String?,
    );
  }
}

class RecoveryCodesResult {
  final List<String> codes;
  final int remainingUnused;

  RecoveryCodesResult({required this.codes, required this.remainingUnused});

  factory RecoveryCodesResult.fromJson(Map<String, dynamic> json) {
    return RecoveryCodesResult(
      codes: (json['codes'] as List).cast<String>(),
      remainingUnused: json['remaining_unused'] as int,
    );
  }
}

class VaultData {
  final String encryptedData;
  final String salt;
  final String nonce;

  VaultData(
      {required this.encryptedData, required this.salt, required this.nonce});

  factory VaultData.fromJson(Map<String, dynamic> json) {
    return VaultData(
      encryptedData: json['encrypted_data'] as String,
      salt: json['salt'] as String,
      nonce: json['nonce'] as String,
    );
  }
}

/// The five signature-gate fields produced by `PasskeyService._signAccountRequest`
/// (W7-12..14). Mirrors the backend `EntitlementRequest` / `VaultGetRequest`
/// shape (snake_case on the wire). Built once per request from a fresh
/// `timestamp` (unix seconds) + UUID `nonce` (replay protection is enforced
/// server-side).
class _SignedAccountFields {
  final String signature;
  final String authorPublicKey;
  final String authorPrincipal;
  final int timestamp;
  final String nonce;

  const _SignedAccountFields({
    required this.signature,
    required this.authorPublicKey,
    required this.authorPrincipal,
    required this.timestamp,
    required this.nonce,
  });
}
