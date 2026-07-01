import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class ScriptIntegrityException implements Exception {
  ScriptIntegrityException(this.message);
  final String message;

  @override
  String toString() => 'ScriptIntegrityException: $message';
}

class ScriptIntegrityService {
  String computeChecksum(String bundle) {
    final bytes = utf8.encode(bundle);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void verifyChecksum(String bundle, String expectedChecksum,
      {String? scriptId}) {
    final actualChecksum = computeChecksum(bundle);
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

  bool hasValidChecksum(String bundle, String expectedChecksum) {
    try {
      verifyChecksum(bundle, expectedChecksum);
      return true;
    } on ScriptIntegrityException catch (e) {
      debugPrint('ScriptIntegrityService.hasValidChecksum: $e');
      return false;
    }
  }
}
