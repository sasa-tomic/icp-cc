import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'passkey_authenticator.dart';
import '../config/app_config.dart';
import '../utils/passkey_platform.dart';

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
          'Passkeys not supported on this platform. Use Web (flutter run -d chrome).');
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
          'Passkeys not supported on this platform. Use Web (flutter run -d chrome).');
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

  Future<void> createVault({
    required String accountId,
    required String password,
    required String data,
  }) async {
    await _post('/vault', {
      'account_id': accountId,
      'password': password,
      'data': base64Encode(utf8.encode(data)),
    });
  }

  Future<VaultData?> getVault(String accountId) async {
    try {
      final response = await _get('/vault?account_id=$accountId');
      return VaultData.fromJson(response['data']);
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('not found')) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> updateVault({
    required String accountId,
    required String password,
    required String data,
  }) async {
    await _put('/vault', {
      'account_id': accountId,
      'password': password,
      'data': base64Encode(utf8.encode(data)),
    });
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
      throw PasskeyException('HTTP ${response.statusCode}: $error');
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
  PasskeyException(this.message);
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
