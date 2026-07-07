import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'passkey_authenticator.dart';
import 'vault_crypto_service.dart';
import '../config/app_config.dart';
import '../utils/passkey_platform.dart';
import '../rust/native_bridge.dart';

// ─── A-4 vault wire-contract field names (single-source-of-truth) ───────────
// These are the JSON keys for /api/v1/vault, byte-identical to the W4 backend
// handlers in backend/src/main.rs. Defined ONCE here; both createVault and
// updateVault build their bodies via _vaultRequestBody below. The password is
// intentionally NOT in this list — A-4 zero-knowledge: the server never sees
// the password (it stays on-device, consumed only by VaultCryptoService FFI).
const String kVaultFieldAccountId = 'account_id';
const String kVaultFieldEncryptedData = 'encrypted_data';
const String kVaultFieldSalt = 'salt';
const String kVaultFieldNonce = 'nonce';

class PasskeyService {
  static final PasskeyService _instance = PasskeyService._internal();
  factory PasskeyService() => _instance;
  PasskeyService._internal() : _httpClient = http.Client();

  String get _baseUrl => '${AppConfig.apiEndpoint}/api/v1';
  final Duration _timeout = const Duration(seconds: 30);
  http.Client _httpClient;
  final NativePasskeyAuthenticator _authenticator =
      NativePasskeyAuthenticator();

  @visibleForTesting
  void overrideHttpClient(http.Client client) => _httpClient = client;

  Future<PasskeyRegistrationResult> registerPasskey({
    required String accountId,
    required String username,
    String? deviceName,
  }) async {
    if (!PasskeyPlatform.isSupported) {
      throw PasskeyException(
          "Passkeys aren't available on this platform. Use the app on macOS, Windows, or Android.");
    }

    final startResponse = await _post('/passkey/register/start', {
      'account_id': accountId,
      'username': username,
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
    required String passkeyId,
    required String accountId,
  }) async {
    await _delete('/passkey/$passkeyId', body: {'account_id': accountId});
  }

  Future<RecoveryCodesResult> generateRecoveryCodes(String accountId) async {
    final response =
        await _post('/recovery/generate', {'account_id': accountId});
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
  /// stores the opaque `encrypted_data`/`salt`/`nonce` triple).
  ///
  /// Wire contract (matches W4 backend `vault_create`):
  ///   POST /api/v1/vault  { account_id, encrypted_data, salt, nonce }  (b64)
  ///   → { "success": true }
  Future<void> createVault({
    required String accountId,
    required String password,
    required String plaintext,
    VaultCryptoService vaultCrypto = const VaultCryptoService(),
  }) async {
    final blob = await vaultCrypto.encrypt(
      password: password,
      plaintext: plaintext,
    );
    await _post('/vault', _vaultRequestBody(accountId, blob));
  }

  Future<VaultData?> getVault(String accountId) async {
    try {
      final response = await _get('/vault?account_id=$accountId');
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
  /// as [createVault] but PUT; the password again never leaves the device.
  Future<void> updateVault({
    required String accountId,
    required String password,
    required String plaintext,
    VaultCryptoService vaultCrypto = const VaultCryptoService(),
  }) async {
    final blob = await vaultCrypto.encrypt(
      password: password,
      plaintext: plaintext,
    );
    await _put('/vault', _vaultRequestBody(accountId, blob));
  }

  /// Builds the opaque-blob request body for createVault/updateVault.
  /// Defined ONCE so the wire shape can drift in exactly one place.
  static Map<String, String> _vaultRequestBody(
    String accountId,
    EncryptedVaultResult blob,
  ) {
    return <String, String>{
      kVaultFieldAccountId: accountId,
      kVaultFieldEncryptedData: blob.encryptedDataB64,
      kVaultFieldSalt: blob.saltB64,
      kVaultFieldNonce: blob.nonceB64,
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
