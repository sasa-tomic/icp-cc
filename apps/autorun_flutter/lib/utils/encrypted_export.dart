import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class EncryptedExport {
  static final _aesGcm = AesGcm.with256bits();
  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );

  static Future<String> encrypt(String plainJson, String password) async {
    if (password.isEmpty) {
      throw ArgumentError('Password cannot be empty');
    }

    final plainBytes = utf8.encode(plainJson);

    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final nonceBytes = Uint8List.fromList(
      List<int>.generate(12, (_) => random.nextInt(256)),
    );

    final passwordBytes = utf8.encode(password);
    final secretKey = await _pbkdf2.deriveKey(
      secretKey: SecretKey(passwordBytes),
      nonce: salt,
    );

    final encrypted = await _aesGcm.encrypt(
      plainBytes,
      secretKey: secretKey,
      nonce: nonceBytes,
    );

    final exportMap = <String, dynamic>{
      'v': 1,
      'alg': 'aes256-gcm',
      'kdf': 'pbkdf2-sha256',
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonceBytes),
      'cipher': base64Encode(encrypted.cipherText),
      'mac': base64Encode(encrypted.mac.bytes),
    };

    return jsonEncode(exportMap);
  }

  static Future<String> decrypt(String encryptedJson, String password) async {
    final Map<String, dynamic> exportMap;
    try {
      exportMap = jsonDecode(encryptedJson) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('Invalid encrypted export format: $e');
    }

    if (exportMap['v'] != 1) {
      throw FormatException('Unsupported export version: ${exportMap['v']}');
    }
    if (exportMap['alg'] != 'aes256-gcm') {
      throw FormatException('Unsupported algorithm: ${exportMap['alg']}');
    }

    final salt = base64Decode(exportMap['salt'] as String);
    final nonce = base64Decode(exportMap['nonce'] as String);
    final cipherText = base64Decode(exportMap['cipher'] as String);
    final macBytes = base64Decode(exportMap['mac'] as String);

    final passwordBytes = utf8.encode(password);
    final secretKey = await _pbkdf2.deriveKey(
      secretKey: SecretKey(passwordBytes),
      nonce: salt,
    );

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final List<int> decryptedBytes;
    try {
      decryptedBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
    } catch (e) {
      throw StateError('Decryption failed: wrong password or corrupted data');
    }

    return utf8.decode(decryptedBytes);
  }
}
