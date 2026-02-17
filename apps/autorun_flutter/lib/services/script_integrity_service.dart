import 'dart:convert';

import 'package:crypto/crypto.dart';

class ScriptIntegrityException implements Exception {
  ScriptIntegrityException(this.message);
  final String message;

  @override
  String toString() => 'ScriptIntegrityException: $message';
}

class ScriptIntegrityService {
  String computeChecksum(String luaSource) {
    final bytes = utf8.encode(luaSource);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void verifyChecksum(String luaSource, String expectedChecksum,
      {String? scriptId}) {
    final actualChecksum = computeChecksum(luaSource);
    if (actualChecksum != expectedChecksum) {
      final idInfo = scriptId != null ? ' (script: $scriptId)' : '';
      throw ScriptIntegrityException(
        'Checksum mismatch$idInfo. '
        'Expected: $expectedChecksum, '
        'Actual: $actualChecksum. '
        'The script may have been corrupted or tampered with.',
      );
    }
  }

  bool hasValidChecksum(String luaSource, String expectedChecksum) {
    try {
      verifyChecksum(luaSource, expectedChecksum);
      return true;
    } catch (_) {
      return false;
    }
  }
}
